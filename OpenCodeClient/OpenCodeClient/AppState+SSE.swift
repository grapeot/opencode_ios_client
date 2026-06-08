import Foundation
import os

/// Server-sent events: connection lifecycle with backoff reconnect,
/// per-event dispatch, polled status reconciliation, per-session
/// activity text debouncing, and the recovery paths triggered when an
/// event implies the current session was deleted server-side.
extension AppState {
    func connectSSE() {
        sseTask?.cancel()
        sseTask = Task {
            var attempt = 0
            while !Task.isCancelled {
                let info = Self.serverURLInfo(serverURL)
                guard info.isAllowed, let baseURL = info.normalized else {
                    return
                }

                let stream = await sseClient.connect(
                    baseURL: baseURL,
                    username: username.isEmpty ? nil : username,
                    password: password.isEmpty ? nil : password
                )

                do {
                    await bootstrapSyncCurrentSession(reason: "sse.reconnect")
                    for try await event in stream {
                        attempt = 0
                        await handleSSEEvent(event)
                    }
                } catch {
                    // Reconnect with exponential backoff
                    attempt += 1
                    let base = min(30.0, pow(2.0, Double(attempt)))
                    try? await Task.sleep(for: .seconds(base))
                }
            }
        }
    }

    func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }

    // Note: AppState is typically held for the app's lifetime (as @State in root view),
    // so deinit-based cleanup is not critical. The disconnectSSE() method above
    // should be called explicitly when needed (e.g., on background/terminate).

    func handleSSEEvent(_ event: SSEEvent) async {
        let type = event.payload.type
        let props = event.payload.properties ?? [:]

        switch type {
        case "server.connected":
            await syncSessionStatusesFromPoll(markMissingBusyAsIdle: true)
        case "session.status":
            if let sessionID = props["sessionID"]?.value as? String,
                let statusObj = props["status"]?.value as? [String: Any] {
                if let status = try? JSONSerialization.data(withJSONObject: statusObj),
                    let decoded = try? JSONDecoder().decode(SessionStatus.self, from: status) {
                    let prev = sessionStatuses[sessionID]
                    guard prev != decoded else { return }

                    sessionStatuses[sessionID] = decoded
                    sessionStatusUpdatedAt[sessionID] = Date()

                    if prev?.type != decoded.type || prev?.message != decoded.message {
                        Self.logger.debug(
                            "session.status(sse) session=\(sessionID, privacy: .public) prev=\(prev?.type ?? "nil", privacy: .public) next=\(decoded.type, privacy: .public)"
                        )
                    }

                    updateSessionActivity(sessionID: sessionID, previous: prev, current: decoded)

                    if sessionID == currentSessionID, !isBusySession(decoded) {
                        messageStore.resetStreaming()
                    }
                }
            }
        case "session.updated":
            let infoVal = props["info"]?.value ?? props["session"]?.value
            if let infoObj = infoVal,
               JSONSerialization.isValidJSONObject(infoObj),
               let data = try? JSONSerialization.data(withJSONObject: infoObj),
               let session = try? JSONDecoder().decode(Session.self, from: data) {
                let dir = effectiveProjectDirectory
                let isCurrent = (session.id == currentSessionID)
                let matchesProject = dir == nil || session.directory == dir
                let shouldApply = matchesProject || isCurrent
                if shouldApply {
                    if sessions.first(where: { $0.id == session.id }) == session { return }

                    let wasUpdate = sessions.contains(where: { $0.id == session.id })
                    Self.logger.debug("session.updated id=\(session.id, privacy: .public) archived=\(session.time.archived.map { String($0) } ?? "nil", privacy: .public) dir=\(session.directory, privacy: .public) op=\(wasUpdate ? "replace" : "insert", privacy: .public)")
                    upsertSession(session)
                } else {
                    Self.logger.debug("session.updated skip id=\(session.id, privacy: .public) dir=\(session.directory, privacy: .public) effectiveDir=\(dir ?? "nil", privacy: .public)")
                }
            }
        case "session.deleted":
            if let sessionID = (props["sessionID"]?.value as? String) ?? (props["id"]?.value as? String) {
                Self.logger.debug("session.deleted id=\(sessionID, privacy: .public)")
                await handleRemoteSessionDeleted(sessionID: sessionID)
            } else {
                await loadSessions()
            }
        case "message.updated":
            let eventSessionID = props["sessionID"]?.value as? String
            if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
                messageStore.resetStreaming()
                await loadMessages()
                await loadSessionDiff()
            }
        case "message.part.updated":
            switch messageStore.applyMessagePartUpdate(properties: props, currentSessionID: currentSessionID) {
            case .ignored:
                break
            case .appended(let sessionID):
                refreshSessionActivityText(sessionID: sessionID)
            case .finalized:
                await loadMessages()
                await loadSessionDiff()
            }
        case "permission.asked":
            if let perm = PermissionController.parseAskedEvent(properties: props),
               !pendingPermissions.contains(where: { $0.id == perm.id }) {
                pendingPermissions.append(perm)
            }
        case "permission.replied":
            PermissionController.applyRepliedEvent(properties: props, to: &pendingPermissions)
        case "question.asked":
            if let question = QuestionController.parseAskedEvent(properties: props),
               !pendingQuestions.contains(where: { $0.id == question.id }) {
                pendingQuestions.append(question)
            }
        case "question.replied", "question.rejected":
            QuestionController.applyResolvedEvent(properties: props, to: &pendingQuestions)
        case "todo.updated":
            if let sessionID = props["sessionID"]?.value as? String,
               let todosObj = props["todos"]?.value,
               JSONSerialization.isValidJSONObject(todosObj),
               let todosData = try? JSONSerialization.data(withJSONObject: todosObj),
               let decoded = try? JSONDecoder().decode([TodoItem].self, from: todosData) {
                sessionTodos[sessionID] = decoded
            }
        default:
            break
        }
    }

    func updateSessionActivity(sessionID: String, previous: SessionStatus?, current: SessionStatus) {
        sessionActivities[sessionID] = ActivityTracker.updateSessionActivity(
            sessionID: sessionID,
            previous: previous,
            current: current,
            existing: sessionActivities[sessionID],
            messages: messages,
            currentSessionID: currentSessionID,
            hasActiveStreaming: streamingReasoningPart?.sessionID == sessionID || messageStore.hasActiveStreaming
        )
    }

    func mergePolledSessionStatuses(_ statuses: [String: SessionStatus]) {
        mergePolledSessionStatuses(statuses, markMissingBusyAsIdle: true)
    }

    func mergePolledSessionStatuses(
        _ statuses: [String: SessionStatus],
        markMissingBusyAsIdle: Bool
    ) {
        let now = Date()
        for (sid, st) in statuses {
            if let updatedAt = sessionStatusUpdatedAt[sid], now.timeIntervalSince(updatedAt) < 5 {
                continue
            }
            let prev = sessionStatuses[sid]
            guard prev != st else { continue }

            sessionStatuses[sid] = st
            updateSessionActivity(sessionID: sid, previous: prev, current: st)
            if sid == currentSessionID, !isBusySession(st) {
                messageStore.resetStreaming()
            }
            if prev?.type != st.type {
                Self.logger.debug(
                    "session.status(poll) session=\(sid, privacy: .public) prev=\(prev?.type ?? "nil", privacy: .public) next=\(st.type, privacy: .public)"
                )
            }
        }

        guard markMissingBusyAsIdle else { return }

        let existingSnapshot = sessionStatuses
        for (sid, prev) in existingSnapshot {
            guard statuses[sid] == nil else { continue }
            guard prev.type == "busy" || prev.type == "retry" else { continue }
            if let updatedAt = sessionStatusUpdatedAt[sid], now.timeIntervalSince(updatedAt) < 5 {
                continue
            }

            let idle = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)
            sessionStatuses[sid] = idle
            updateSessionActivity(sessionID: sid, previous: prev, current: idle)
            if sid == currentSessionID {
                messageStore.resetStreaming()
            }

            Self.logger.debug(
                "session.status(poll) session=\(sid, privacy: .public) prev=\(prev.type, privacy: .public) next=idle (missing from poll)"
            )
        }
    }

    func refreshSessionActivityText(sessionID: String) {
        guard isBusySession(sessionStatuses[sessionID]) else { return }
        guard sessionActivities[sessionID]?.state == .running else { return }
        let next = ActivityTracker.bestSessionActivityText(
            sessionID: sessionID,
            currentSessionID: currentSessionID,
            sessionStatuses: sessionStatuses,
            messages: messages,
            streamingReasoningPart: streamingReasoningPart,
            streamingPartTexts: streamingPartTexts
        )
        setSessionActivityText(sessionID: sessionID, next)
    }

    func setSessionActivityText(sessionID: String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var a = sessionActivities[sessionID], a.state == .running else { return }
        if a.text == trimmed { return }

        let now = Date()
        let delay = ActivityTracker.debounceDelay(lastChangeAt: activityTextLastChangeAt[sessionID], now: now)
        if delay == 0 {
            a.text = trimmed
            sessionActivities[sessionID] = a
            activityTextLastChangeAt[sessionID] = now
            activityTextPendingTask[sessionID]?.cancel()
            activityTextPendingTask[sessionID] = nil
            return
        }

        activityTextPendingTask[sessionID]?.cancel()
        activityTextPendingTask[sessionID] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard self.isBusySession(self.sessionStatuses[sessionID]) else { return }
            let best = ActivityTracker.bestSessionActivityText(
                sessionID: sessionID,
                currentSessionID: self.currentSessionID,
                sessionStatuses: self.sessionStatuses,
                messages: self.messages,
                streamingReasoningPart: self.streamingReasoningPart,
                streamingPartTexts: self.streamingPartTexts
            )
            self.setSessionActivityText(sessionID: sessionID, best)
        }
    }

    func clearCurrentSessionViewState() {
        sessionLoadingID = UUID()
        messageStore.resetStreaming()
        messages = []
        partsByMessage = [:]
        sessionDiffs = []
    }

    func clearSessionScopedCaches(sessionID: String) {
        sessionStatuses[sessionID] = nil
        sessionTodos[sessionID] = nil
        sessionActivities[sessionID] = nil
        sessionStatusUpdatedAt[sessionID] = nil
        activityTextLastChangeAt[sessionID] = nil
        activityTextPendingTask[sessionID]?.cancel()
        activityTextPendingTask[sessionID] = nil
        loadedMessageLimitBySessionID[sessionID] = nil
        hasMoreHistoryBySessionID[sessionID] = nil
        loadingOlderMessagesSessionIDs.remove(sessionID)
        pendingPermissions.removeAll { $0.sessionID == sessionID }

        if streamingReasoningPart?.sessionID == sessionID {
            messageStore.streamingReasoningPart = nil
        }

        draftInputsBySessionID[sessionID] = nil
        if draftInputsBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.draftInputsBySessionKey)
        } else if let data = try? JSONEncoder().encode(draftInputsBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.draftInputsBySessionKey)
        }

        selectedModelIDBySessionID[sessionID] = nil
        persistSelectedModelMap()
    }

    func isSessionNotFoundError(_ error: Error) -> Bool {
        guard case APIError.httpError(let statusCode, _) = error else { return false }
        return statusCode == 404
    }

    func recoverFromMissingCurrentSessionIfNeeded(
        error: Error,
        requestedSessionID: String
    ) async -> Bool {
        guard requestedSessionID == currentSessionID else { return false }
        guard isSessionNotFoundError(error) else { return false }

        await loadSessions()

        guard currentSessionID != nil else {
            pendingPermissions = []
            return true
        }

        await loadMessages()
        await refreshPendingPermissions()
        await loadSessionDiff()
        await loadSessionTodos()
        syncModelFromMessageHistory()
        return true
    }

    func handleRemoteSessionDeleted(sessionID: String) async {
        let deletedCurrentSession = (sessionID == currentSessionID)

        sessions.removeAll { $0.id == sessionID }
        clearSessionScopedCaches(sessionID: sessionID)

        if deletedCurrentSession {
            clearCurrentSessionViewState()
        }

        await loadSessions()

        if deletedCurrentSession, currentSessionID != nil {
            await loadMessages()
            await refreshPendingPermissions()
            await loadSessionDiff()
            await loadSessionTodos()
            syncModelFromMessageHistory()
        } else if currentSessionID == nil {
            pendingPermissions = []
        } else {
            let validSessionIDs = Set(sessions.map(\.id))
            pendingPermissions.removeAll { !validSessionIDs.contains($0.sessionID) }
        }
    }

    func applySSEEventForTesting(_ event: SSEEvent) async {
        await handleSSEEvent(event)
    }
}
