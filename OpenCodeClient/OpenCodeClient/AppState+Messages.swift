import Foundation
import os

/// Message + diff loading and outbound send (optimistic user message
/// row + async `prompt` request to the server). Older-message pagination
/// (`loadOlderMessagesForCurrentSession`) and the per-session diff load
/// live here too — both are message-tab concerns.
///
/// State lives on `MessageStore`; this extension only orchestrates.
extension AppState {
    nonisolated static func visibleMessages(_ messages: [MessageWithParts], revertMessageID: String?) -> [MessageWithParts] {
        guard let revertMessageID else { return messages }
        return messages.filter { message in
            message.info.id.hasPrefix("temp-") || message.info.id < revertMessageID
        }
    }

    func loadMessages() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let fetchLimit = Self.normalizedMessageFetchLimit(current: loadedMessageLimitBySessionID[sessionID])
            loadedMessageLimitBySessionID[sessionID] = fetchLimit
            let loaded = try await apiClient.messages(sessionID: sessionID, limit: fetchLimit)
            Self.logger.debug("loadMessages: session=\(sessionID, privacy: .public) limit=\(fetchLimit, privacy: .public) returned=\(loaded.count, privacy: .public)")
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("drop stale loadMessages result requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }

            hasMoreHistoryBySessionID[sessionID] = loaded.count >= fetchLimit

            let loadedMessageIDs = Set(loaded.map { $0.info.id })
            let keepPending = isBusySession(currentSessionStatus)
            let pendingMessages: [MessageWithParts] = {
                guard keepPending else { return [] }
                let pending = messages.filter({ $0.info.id.hasPrefix("temp-user-") })
                guard let lastLoadedUser = loaded.last(where: { $0.info.isUser }) else { return pending }

                func normalizeEpochMs(_ raw: Int) -> Int {
                    // Server timestamps may be seconds or milliseconds.
                    if raw > 0 && raw < 10_000_000_000 { return raw * 1000 }
                    return raw
                }

                func normalizeComparableText(_ raw: String) -> String {
                    raw
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }

                let lastLoadedText = normalizeComparableText(
                    lastLoadedUser.parts.first(where: { $0.isText })?.text ?? ""
                )
                let lastLoadedCreated = normalizeEpochMs(lastLoadedUser.info.time.created)

                return pending.filter { m in
                    guard m.info.isUser else { return true }
                    let text = normalizeComparableText(
                        m.parts.first(where: { $0.isText })?.text ?? ""
                    )
                    guard !text.isEmpty else { return true }
                    let textMatches = text == lastLoadedText || lastLoadedText.hasSuffix(text)

                    let created = normalizeEpochMs(m.info.time.created)
                    let timestampClose: Bool = {
                        if created == 0 || lastLoadedCreated == 0 { return true }
                        return abs(lastLoadedCreated - created) <= 60 * 1000
                    }()

                    if textMatches || timestampClose { return false }
                    return true
                }
            }()

            let draftMessages = messages.filter {
                messageStore.isStreamingDraftMessage($0.info.id) && !loadedMessageIDs.contains($0.info.id)
            }

            var merged: [MessageWithParts] = loaded
            for message in pendingMessages where !loadedMessageIDs.contains(message.info.id) {
                merged.append(message)
            }
            for message in draftMessages where !merged.contains(where: { $0.info.id == message.info.id }) {
                merged.append(message)
            }

            // Defensively dedupe by message id. Keep the latest occurrence.
            var dedupedMessages: [MessageWithParts] = []
            var dedupedIndexByMessageID: [String: Int] = [:]
            for message in merged {
                if let existingIndex = dedupedIndexByMessageID[message.info.id] {
                    dedupedMessages[existingIndex] = message
                } else {
                    dedupedIndexByMessageID[message.info.id] = dedupedMessages.count
                    dedupedMessages.append(message)
                }
            }

            messages = dedupedMessages

            var partsByMessageID: [String: [Part]] = [:]
            for message in messages {
                partsByMessageID[message.info.id] = message.parts
            }
            partsByMessage = partsByMessageID
            messageStore.removeStreamingDraftMessages(loadedMessageIDs)

            if isBusySession(currentSessionStatus) {
                refreshSessionActivityText(sessionID: sessionID)
            }
        } catch let error as DecodingError {
            Self.logger.error("loadMessages decode failed: session=\(sessionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("ignore stale loadMessages error requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }
            connectionError = error.localizedDescription
            Self.logger.error("loadMessages failed: session=\(sessionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func loadOlderMessagesForCurrentSession() async -> Bool {
        guard let sessionID = currentSessionID else { return false }
        guard hasMoreHistoryBySessionID[sessionID] ?? true else {
            Self.logger.debug("loadOlderMessages skipped: no more history session=\(sessionID, privacy: .public)")
            return false
        }
        guard !loadingOlderMessagesSessionIDs.contains(sessionID) else {
            Self.logger.debug("loadOlderMessages skipped: already loading session=\(sessionID, privacy: .public)")
            return false
        }

        loadingOlderMessagesSessionIDs.insert(sessionID)
        defer { loadingOlderMessagesSessionIDs.remove(sessionID) }
        let previousCount = messages.count
        loadedMessageLimitBySessionID[sessionID] = Self.nextMessageFetchLimit(current: loadedMessageLimitBySessionID[sessionID])
        let requestedLimit = loadedMessageLimitBySessionID[sessionID] ?? Self.normalizedMessageFetchLimit(current: nil)
        Self.logger.debug("loadOlderMessages begin: session=\(sessionID, privacy: .public) previousCount=\(previousCount, privacy: .public) requestedLimit=\(requestedLimit, privacy: .public)")
        await Task { @MainActor in
            await self.loadMessages()
        }.value
        let newCount = messages.count
        let didLoadMore = newCount > previousCount
        Self.logger.debug("loadOlderMessages end: session=\(sessionID, privacy: .public) newCount=\(newCount, privacy: .public) didLoadMore=\(didLoadMore, privacy: .public) hasMore=\(self.hasMoreHistoryBySessionID[sessionID] ?? false, privacy: .public)")
        return didLoadMore
    }

    func loadSessionDiff() async {
        guard let sessionID = currentSessionID else { sessionDiffs = []; return }
        do {
            let loaded = try await apiClient.sessionDiff(sessionID: sessionID)
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("drop stale loadSessionDiff result requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }
            sessionDiffs = loaded
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else { return }
            sessionDiffs = []
        }
    }

    func sendMessage(_ text: String, attachments: [ComposerImageAttachment] = []) async -> Bool {
        sendError = nil
        guard let sessionID = currentSessionID else {
            sendError = L10n.t(.chatSelectSessionFirst)
            return false
        }
        do {
            if sessions.first(where: { $0.id == sessionID })?.isArchived == true {
                try await restoreSession(sessionID: sessionID)
            }
        } catch {
            sendError = error.localizedDescription
            return false
        }

        let tempMessageID = appendOptimisticUserMessage(text, attachments: attachments)
        let model = selectedModel.map { Message.ModelInfo(providerID: $0.providerID, modelID: $0.modelID) }
        let agentName = selectedAgent?.name ?? "build"
        do {
            try await apiClient.promptAsync(sessionID: sessionID, text: text, attachments: attachments, agent: agentName, model: model)
            return true
        } catch {
            let recovered = await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID)
            sendError = recovered ? L10n.t(.errorSessionNotFound) : error.localizedDescription
            removeMessage(id: tempMessageID)
            return false
        }
    }

    func editFromMessage(messageID: String) async -> String? {
        guard isConnected else { return nil }
        guard let sessionID = currentSessionID else { return nil }
        guard let message = messages.first(where: { $0.info.id == messageID && $0.info.isUser }) else { return nil }

        let draft = Self.editDraftText(for: message)
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        do {
            let updatedSession = try await apiClient.revertSession(sessionID: sessionID, messageID: messageID, partID: nil)
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else { return nil }
            upsertSession(updatedSession)
            setDraftText(draft, for: sessionID)
            await loadMessages()
            await loadSessionDiff()
            await loadFileStatus()
            return draft
        } catch {
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else { return nil }
            sendError = error.localizedDescription
            return nil
        }
    }

    nonisolated static func editDraftText(for message: MessageWithParts) -> String {
        message.parts
            .filter { $0.isText }
            .compactMap { $0.text }
            .joined(separator: "\n\n")
    }

    @discardableResult
    func appendOptimisticUserMessage(_ text: String, attachments: [ComposerImageAttachment] = []) -> String {
        guard let sessionID = currentSessionID else { return "" }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let messageID = "temp-user-\(UUID().uuidString)"
        let message = Message(
            id: messageID,
            sessionID: sessionID,
            role: "user",
            parentID: messages.last?.info.id,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: Message.TimeInfo(created: now, completed: now),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        var parts: [Part] = []
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(Part(
                id: "temp-part-\(messageID)",
                messageID: messageID,
                sessionID: sessionID,
                type: "text",
                text: text,
                tool: nil,
                callID: nil,
                state: nil,
                metadata: nil,
                files: nil
            ))
        }
        for attachment in attachments {
            parts.append(Part(
                id: "temp-file-\(attachment.id.uuidString)",
                messageID: messageID,
                sessionID: sessionID,
                type: "file",
                text: nil,
                tool: nil,
                callID: nil,
                state: nil,
                metadata: nil,
                files: nil,
                mime: attachment.mime,
                filename: attachment.filename,
                url: attachment.dataURL
            ))
        }
        let row = MessageWithParts(info: message, parts: parts)
        messages.append(row)
        partsByMessage[messageID] = parts
        return messageID
    }

    func removeMessage(id: String) {
        messages.removeAll { $0.info.id == id }
        partsByMessage[id] = nil
    }
}
