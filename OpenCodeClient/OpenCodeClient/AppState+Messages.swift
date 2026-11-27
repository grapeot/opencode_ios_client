import Foundation
import os

/// Message + diff loading and outbound send (optimistic user message
/// row + async `prompt` request to the server). Older-message pagination
/// (`loadOlderMessagesForCurrentSession`) and the per-session diff load
/// live here too — both are message-tab concerns.
///
/// State lives on `MessageStore`; this extension only orchestrates.
extension AppState {
    nonisolated static func visibleMessages(
        _ messages: [MessageWithParts],
        revertMessageID: String?,
        pendingIDs: Set<String> = []
    ) -> [MessageWithParts] {
        guard let revertMessageID else { return messages }
        if let boundary = messages.firstIndex(where: { $0.info.id == revertMessageID }) {
            return messages.enumerated().compactMap { index, message in
                if pendingIDs.contains(message.info.id) || message.info.id.hasPrefix("temp-") || index < boundary {
                    return message
                }
                return nil
            }
        }
        guard OrderedServerID.isOrdered(revertMessageID, prefix: "msg") else { return messages }
        return messages.filter { message in
            pendingIDs.contains(message.info.id) || message.info.id.hasPrefix("temp-") || message.info.id < revertMessageID
        }
    }

    func loadMessages(allowMissingSessionRecovery: Bool = true) async {
        guard let sessionID = currentSessionID else { return }
        let host = captureHostRequestSnapshot()
        let selection = sessionLoadingID
        let revisionAtStart = messageStore.liveRevision
        messageSnapshotRequestSequence &+= 1
        let requestSequence = messageSnapshotRequestSequence
        do {
            let fetchLimit = Self.normalizedMessageFetchLimit(current: loadedMessageLimitBySessionID[sessionID])
            loadedMessageLimitBySessionID[sessionID] = fetchLimit
            let loaded = try await apiClient.messages(sessionID: sessionID, limit: fetchLimit)
            Self.logger.debug("loadMessages: session=\(sessionID, privacy: .public) limit=\(fetchLimit, privacy: .public) returned=\(loaded.count, privacy: .public)")
            guard acceptsMessageSnapshot(
                host: host,
                selection: selection,
                sessionID: sessionID,
                revisionAtStart: revisionAtStart,
                requestSequence: requestSequence
            ) else {
                Self.logger.debug("drop stale loadMessages result requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }

            hasMoreHistoryBySessionID[sessionID] = loaded.count >= fetchLimit

            // Status-line stats reconcile: server-loaded window only (pending
            // optimistic rows are not counted until the server confirms them).
            let windowUserMessageIDs = Set(loaded.filter { $0.info.isUser }.map { $0.info.id })
            let windowToolPartIDs = Set(loaded.flatMap { $0.parts.filter { $0.isTool }.map { $0.id } })
            statsStore.reconcile(
                sessionID: sessionID,
                userMessageIDs: windowUserMessageIDs,
                toolPartIDs: windowToolPartIDs,
                isComplete: loaded.count < fetchLimit
            )
            if revertResetPendingSessionIDs.remove(sessionID) != nil {
                statsStore.resetForRevert(
                    sessionID: sessionID,
                    userMessageIDs: windowUserMessageIDs,
                    toolPartIDs: windowToolPartIDs
                )
            }

            let loadedMessageIDs = Set(loaded.map { $0.info.id })
            messageStore.untrackPendingOptimisticMessages(loadedMessageIDs)
            messageStore.pruneSendFailures(loadedMessageIDs: loadedMessageIDs)

            var dedupedMessages: [MessageWithParts] = []
            var indexByMessageID: [String: Int] = [:]
            for message in loaded {
                if let existingIndex = indexByMessageID[message.info.id] {
                    dedupedMessages[existingIndex] = message
                } else {
                    indexByMessageID[message.info.id] = dedupedMessages.count
                    dedupedMessages.append(message)
                }
            }
            for message in messages where message.info.sessionID == sessionID
                && indexByMessageID[message.info.id] == nil
                && (messageStore.isPendingOptimisticMessage(message.info.id)
                    || messageStore.failedSendReasonsByID[message.info.id] != nil) {
                indexByMessageID[message.info.id] = dedupedMessages.count
                dedupedMessages.append(message)
            }
            for message in messageStore.outboundRows(hostProfileID: host.hostProfileID, sessionID: sessionID)
            where indexByMessageID[message.info.id] == nil {
                indexByMessageID[message.info.id] = dedupedMessages.count
                dedupedMessages.append(message)
            }
            acceptedMessageSnapshotSequence = requestSequence
            messages = dedupedMessages

            var partsByMessageID: [String: [Part]] = [:]
            for message in messages {
                partsByMessageID[message.info.id] = message.parts
            }
            partsByMessage = partsByMessageID
            reconcileSelectedAgent()

            if isBusySession(currentSessionStatus) {
                refreshSessionActivityText(sessionID: sessionID)
            }
            recomputeSessionActivityAfterMessageSnapshot(sessionID: sessionID)
        } catch let error as DecodingError {
            Self.logger.error("loadMessages decode failed: session=\(sessionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        } catch {
            guard isCurrentHostRequest(host),
                  sessionLoadingID == selection,
                  requestSequence == messageSnapshotRequestSequence,
                  Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("ignore stale loadMessages error requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }
            if await recoverFromMissingCurrentSessionIfNeeded(
                error: error,
                requestedSessionID: sessionID,
                allowMissingSessionRecovery: allowMissingSessionRecovery
            ) {
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

    func loadSessionDiff(allowMissingSessionRecovery: Bool = true) async {
        guard let sessionID = currentSessionID else { sessionDiffs = []; return }
        do {
            let loaded = try await apiClient.sessionDiff(sessionID: sessionID)
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("drop stale loadSessionDiff result requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }
            sessionDiffs = loaded
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(
                error: error,
                requestedSessionID: sessionID,
                allowMissingSessionRecovery: allowMissingSessionRecovery
            ) {
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
        let host = captureHostRequestSnapshot()
        let selection = sessionLoadingID
        let model = selectedModel.map { Message.ModelInfo(providerID: $0.providerID, modelID: $0.modelID) }
        let agentName = agentNameForPrompt()
        let directory = currentSession?.directory ?? effectiveProjectDirectory
        let messageID = Self.makeServerID(prefix: "msg")
        if sessions.first(where: { $0.id == sessionID })?.isArchived == true {
            registerOutboundUserMessage(
                text,
                attachments: attachments,
                messageID: messageID,
                sessionID: sessionID,
                hostProfileID: host.hostProfileID
            )
            do {
                try await restoreSession(sessionID: sessionID, fetchDescendants: false)
            } catch {
                guard ownsSend(host: host, selection: selection, sessionID: sessionID) else {
                    keepExistingUnsent(messageID)
                    return false
                }
                messageStore.removeOutboundSendIfMatches(
                    messageID: messageID,
                    hostProfileID: host.hostProfileID,
                    sessionID: sessionID
                )
                sendError = error.localizedDescription
                return false
            }
            guard ownsSend(host: host, selection: selection, sessionID: sessionID),
                  !sessionScope.confirmedMissingSessionIDs.contains(sessionID) else {
                keepExistingUnsent(messageID)
                return false
            }
            insertTrackedOutboundRow(messageID: messageID, sessionID: sessionID, hostProfileID: host.hostProfileID)
        } else {
            guard ownsSend(host: host, selection: selection, sessionID: sessionID) else {
                keepUnsent(text, attachments: attachments, sessionID: sessionID, hostProfileID: host.hostProfileID)
                return false
            }
            _ = appendOptimisticUserMessage(
                text,
                attachments: attachments,
                messageID: messageID,
                sessionID: sessionID,
                hostProfileID: host.hostProfileID
            )
        }
        let tempMessageID = messageID
        do {
            try await apiClient.promptAsync(
                sessionID: sessionID,
                messageID: messageID,
                text: text,
                attachments: attachments,
                agent: agentName,
                model: model,
                directory: directory
            )
            return true
        } catch {
            let reason: String
            if ownsSend(host: host, selection: selection, sessionID: sessionID) {
                let recovered = await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID)
                reason = recovered ? L10n.t(.errorSessionNotFound) : error.localizedDescription
            } else {
                reason = error.localizedDescription
            }
            messageStore.markSendFailed(messageID: tempMessageID, reason: reason)
            messageStore.untrackPendingOptimisticMessages([tempMessageID])
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
            // Revert truncates history; the reloaded window is the new ground
            // truth for the status-line counters (see SessionStatsStore).
            revertResetPendingSessionIDs.insert(sessionID)
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

    nonisolated static func makeServerID(prefix: String, timestamp: Int = Int(Date().timeIntervalSince1970 * 1000)) -> String {
        OrderedServerID.make(prefix: prefix, timestamp: timestamp)
    }

    nonisolated static func makeServerIDs(prefix: String, count: Int, timestamp: Int) -> [String] {
        OrderedServerID.makeBatch(prefix: prefix, count: count, timestamp: timestamp)
    }

    private func ownsSend(host: HostRequestSnapshot, selection: UUID, sessionID: String) -> Bool {
        isCurrentHostRequest(host) && sessionLoadingID == selection && currentSessionID == sessionID
    }

    private func acceptsMessageSnapshot(
        host: HostRequestSnapshot,
        selection: UUID,
        sessionID: String,
        revisionAtStart: UInt64,
        requestSequence: UInt64
    ) -> Bool {
        isCurrentHostRequest(host)
            && sessionLoadingID == selection
            && Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID)
            && requestSequence >= acceptedMessageSnapshotSequence
            && messageStore.liveRevision == revisionAtStart
    }

    private func keepUnsent(_ text: String, attachments: [ComposerImageAttachment], sessionID: String, hostProfileID: UUID) {
        let messageID = appendOptimisticUserMessage(
            text,
            attachments: attachments,
            sessionID: sessionID,
            hostProfileID: hostProfileID
        )
        guard !messageID.isEmpty else { return }
        keepExistingUnsent(messageID)
    }

    private func keepExistingUnsent(_ messageID: String) {
        messageStore.markSendFailed(messageID: messageID, reason: L10n.t(.chatSendFailed))
        messageStore.untrackPendingOptimisticMessages([messageID])
    }

    private func registerOutboundUserMessage(
        _ text: String,
        attachments: [ComposerImageAttachment],
        messageID: String,
        sessionID: String,
        hostProfileID: UUID
    ) {
        let row = optimisticUserRow(text, attachments: attachments, messageID: messageID, sessionID: sessionID)
        messageStore.rememberOutboundSend(hostProfileID: hostProfileID, sessionID: sessionID, row: row)
    }

    private func insertTrackedOutboundRow(messageID: String, sessionID: String, hostProfileID: UUID) {
        guard currentSessionID == sessionID, currentHostProfileID == hostProfileID else { return }
        guard let row = messageStore.outboundRows(hostProfileID: hostProfileID, sessionID: sessionID).first(where: { $0.info.id == messageID }) else { return }
        guard !messages.contains(where: { $0.info.id == messageID }) else { return }
        messages.append(row)
        partsByMessage[messageID] = row.parts
    }

    @discardableResult
    func appendOptimisticUserMessage(
        _ text: String,
        attachments: [ComposerImageAttachment] = [],
        messageID: String? = nil,
        sessionID explicitSessionID: String? = nil,
        hostProfileID: UUID? = nil
    ) -> String {
        let sessionID = explicitSessionID ?? currentSessionID
        guard let sessionID, !sessionID.isEmpty else { return "" }
        let hostProfileID = hostProfileID ?? currentHostProfileID
        let messageID = messageID ?? "temp-user-\(UUID().uuidString)"
        let row = optimisticUserRow(text, attachments: attachments, messageID: messageID, sessionID: sessionID)
        if currentSessionID == sessionID && currentHostProfileID == hostProfileID {
            messages.append(row)
            partsByMessage[messageID] = row.parts
        }
        messageStore.rememberOutboundSend(hostProfileID: hostProfileID, sessionID: sessionID, row: row)
        return messageID
    }

    private func optimisticUserRow(
        _ text: String,
        attachments: [ComposerImageAttachment],
        messageID: String,
        sessionID: String
    ) -> MessageWithParts {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let message = Message(
            id: messageID,
            sessionID: sessionID,
            role: "user",
            parentID: currentSessionID == sessionID ? messages.last?.info.id : nil,
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
        return MessageWithParts(info: message, parts: parts)
    }

    func removeMessage(id: String) {
        messages.removeAll { $0.info.id == id }
        partsByMessage[id] = nil
        messageStore.untrackPendingOptimisticMessages([id])
        messageStore.clearSendFailure(messageID: id)
    }
}
