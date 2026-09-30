import Foundation
import os

/// Server-sent events: connection lifecycle with backoff reconnect,
/// per-event dispatch, polled status reconciliation, per-session
/// activity text debouncing, and the recovery paths triggered when an
/// event implies the current session was deleted server-side.
extension AppState {
    func connectSSE() {
        sseTask?.cancel()
        sseWatchdogTask?.cancel()
        sseWatchdogTask = nil
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
                    sseLastFrameAt = Date()
                    launchSSEWatchdog()
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

                // The stream is gone (clean end or error); the watchdog only
                // covers "connected but silent", so stop it while the client
                // is between connections (backoff). It relaunches after the
                // next successful connect + bootstrap.
                sseWatchdogTask?.cancel()
                sseWatchdogTask = nil
            }
        }
    }

    /// Starts the heartbeat watchdog once per connected stream. Not a poller:
    /// it checks every `sseWatchdogCheckInterval` whether any frame (a
    /// heartbeat counts) arrived, and only after `sseSilenceThreshold` of
    /// silence runs one reconciliation. On a host without heartbeats this
    /// degrades to a low-frequency reconcile every ~20-25s of silence.
    private func launchSSEWatchdog() {
        guard sseWatchdogTask == nil else { return }
        sseWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.sseWatchdogCheckInterval))
                guard !Task.isCancelled else { return }
                await self?.checkSSEWatchdog()
            }
        }
    }

    /// One watchdog check. When the stream has been silent past the threshold,
    /// resets the timestamp (so one silence triggers one reconcile, not one
    /// per check interval) and runs the reconciliation set: message window +
    /// diff + polled statuses.
    func checkSSEWatchdog() async {
        guard let last = sseLastFrameAt, currentSessionID != nil else { return }
        guard Date().timeIntervalSince(last) > Self.sseSilenceThreshold else { return }
        sseLastFrameAt = Date()
        await loadMessages()
        await loadSessionDiff()
        await syncSessionStatusesFromPoll()
    }

    func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
        sseWatchdogTask?.cancel()
        sseWatchdogTask = nil
    }

    // Note: AppState is typically held for the app's lifetime (as @State in root view),
    // so deinit-based cleanup is not critical. The disconnectSSE() method above
    // should be called explicitly when needed (e.g., on background/terminate).

    func handleSSEEvent(_ event: SSEEvent) async {
        // Any frame of any type — including heartbeats — proves the stream is
        // alive; the watchdog only fires after this has gone stale.
        sseLastFrameAt = Date()
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

                    // idle fires once per turn (at turn end; step gaps do not
                    // alternate), so busy -> idle is a turn-end signal. One
                    // reconciliation per turn closes the loop: it picks up
                    // time.completed/tokens the live frames omit. Only the
                    // current session reconciles — sessionStatuses itself is a
                    // global map that intentionally tracks every session.
                    if decoded.type == "idle", sessionID == currentSessionID {
                        await loadMessages()
                        await loadSessionDiff()
                    }
                }
            }
        case "session.updated":
            let infoVal = props["info"]?.value ?? props["session"]?.value
            if let infoObj = infoVal,
               JSONSerialization.isValidJSONObject(infoObj),
               let data = try? JSONSerialization.data(withJSONObject: infoObj),
               let session = try? JSONDecoder().decode(Session.self, from: data) {
                let dir = effectiveProjectDirectory ?? serverCurrentProjectWorktree
                let isCurrent = (session.id == currentSessionID)
                let isKnown = sessions.contains(where: { $0.id == session.id })
                // REST treats a missing directory as the server's current project,
                // while /global/event carries updates from every project.
                let matchesProject = dir.map { session.directory == $0 } ?? isKnown
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
                if let infoObj = props["info"]?.value as? [String: Any],
                    let role = infoObj["role"] as? String,
                    let id = infoObj["id"] as? String,
                    let sessionID = eventSessionID {
                    if role == "assistant" {
                        messageStore.recordStepStart(id, sessionID: sessionID)
                    } else if role == "user" {
                        statsStore.observeUserMessage(id: id, sessionID: sessionID)
                    }
                }
                if let infoObj = props["info"]?.value as? [String: Any],
                    let data = try? JSONSerialization.data(withJSONObject: infoObj),
                    let info = try? JSONDecoder().decode(Message.self, from: data),
                    info.sessionID == currentSessionID {
                    messageStore.upsertMessageInfo(info)
                } else {
                    // info missing or undecodable: the payload cannot carry
                    // the message state locally, so fall back to the REST
                    // reconciliation path (pre-SSE-data-path behavior).
                    await loadMessages()
                    await loadSessionDiff()
                }
            }
        case "message.part.delta":
            // `field` is "text" for both reasoning and text parts, so it cannot
            // discriminate; the part's `type` (tracked by partID from the
            // `message.part.updated` that precedes each part's deltas) can.
            if let sessionID = props["sessionID"]?.value as? String,
               sessionID == currentSessionID,
               props["field"]?.value as? String == "text",
               let delta = props["delta"]?.value as? String, !delta.isEmpty,
                let messageID = props["messageID"]?.value as? String,
                let partID = props["partID"]?.value as? String,
                messageStore.partType(for: partID, inSession: sessionID) == "text" {
                messageStore.recordVisibleToken(messageID, sessionID: sessionID)
                // Streaming text: append in place. Only text parts reach this
                // point (the partType guard above); reasoning text lands
                // locally via its end frame. A part that is not loaded yet
                // (reconnect missed the start frame) is a no-op — the end
                // frame or the next reconciliation converges it.
                messageStore.appendDelta(messageID: messageID, partID: partID, delta: delta)
            }
        case "message.part.updated":
            let eventSessionID = props["sessionID"]?.value as? String
            if let sessionID = eventSessionID,
               sessionID == currentSessionID,
               let partObj = props["part"]?.value as? [String: Any],
               let messageID = partObj["messageID"] as? String,
               let partID = partObj["id"] as? String {
                // First-write-wins part-type index: the delta guard below
                // (and throughput stamping) rely on the start frame's type.
                messageStore.recordPartType(
                    sessionID: sessionID,
                    partID: partID,
                    type: (partObj["type"] as? String) ?? "text"
                )
                // Tool-call input streams as deltas on the tool part, so it also
                // counts as visible output; a step whose only output is a tool
                // call would otherwise have no decoding window at all.
                if let partType = partObj["type"] as? String, partType == "tool" || partType == "text",
                   let delta = props["delta"]?.value as? String, !delta.isEmpty {
                    messageStore.recordVisibleToken(messageID, sessionID: sessionID)
                }
                if partObj["type"] as? String == "step-finish" {
                    let tokensObj = partObj["tokens"] as? [String: Any]
                    messageStore.recordStepFinish(messageID, sessionID: sessionID, outputTokens: tokensObj?["output"] as? Int)
                }
                // First sighting of a new tool part id (any status, pending
                // first) counts one tool call; replayed statuses dedupe.
                if partObj["type"] as? String == "tool" {
                    statsStore.observeToolPart(id: partID, sessionID: sessionID)
                }
            }
            if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
                if let partObj = props["part"]?.value as? [String: Any],
                   let data = try? JSONSerialization.data(withJSONObject: partObj),
                   let part = try? JSONDecoder().decode(Part.self, from: data),
                   part.sessionID == currentSessionID {
                    switch messageStore.upsertPart(part) {
                    case .applied, .ignored:
                        break
                    case .needsReconcile:
                        // Thin payload (e.g. dsh shim shape): fall back to the
                        // REST reconciliation path so multi-host behavior
                        // matches the pre-SSE-data-path client.
                        await loadMessages()
                        await loadSessionDiff()
                    }
                } else {
                    await loadMessages()
                    await loadSessionDiff()
                }
            }
        case "message.part.removed":
            // The payload carries only ids (no part object): revert cleanup
            // and the DELETE endpoints emit this. Apply locally so the UI no
            // longer waits on a REST round-trip for deletions.
            if let sessionID = props["sessionID"]?.value as? String,
               sessionID == currentSessionID,
               let messageID = props["messageID"]?.value as? String,
               let partID = props["partID"]?.value as? String {
                messageStore.removePart(messageID: messageID, partID: partID)
            }
        case "message.removed":
            if let sessionID = props["sessionID"]?.value as? String,
               sessionID == currentSessionID,
               let messageID = props["messageID"]?.value as? String {
                messageStore.removeMessageRow(messageID: messageID)
            }
        case "server.heartbeat":
            // Explicit no-op: the liveness timestamp is stamped at the
            // handleSSEEvent entry for every frame. Listed here so a
            // heartbeat never silently falls through to `default`.
            break
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
        case "session.error":
            let eventSessionID = props["sessionID"]?.value as? String
            if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
                // prompt_async acknowledges with 204 before the turn runs, so
                // an async failure only surfaces through this event. Mark the
                // still-pending optimistic row as failed (inline banner, no
                // alert) and reconcile; turns that already persisted an
                // assistant row surface their error through that row instead.
                let reason = Self.sessionErrorDisplayReason(properties: props)
                if let pendingID = messageStore.pendingOptimisticMessageIDs.min() {
                    messageStore.markSendFailed(messageID: pendingID, reason: reason)
                    messageStore.untrackPendingOptimisticMessages([pendingID])
                }
                await loadMessages()
            }
        default:
            break
        }
    }

    /// Builds a short inline-banner reason from a session.error payload
    /// (`error: {name, data}`). Server causes can be long multi-line dumps;
    /// keep the first meaningful line, bounded.
    nonisolated static func sessionErrorDisplayReason(properties: [String: AnyCodable]) -> String {
        let fallback = L10n.t(.errorOperationFailed)
        guard let errorObject = properties["error"]?.value as? [String: Any],
              JSONSerialization.isValidJSONObject(errorObject),
              let jsonData = try? JSONSerialization.data(withJSONObject: errorObject),
              let decoded = try? JSONDecoder().decode(Message.MessageError.self, from: jsonData) else {
            return fallback
        }
        let raw = decoded.message ?? decoded.name
        let firstLine = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? raw
        let prefix = decoded.name.isEmpty ? "" : "\(decoded.name): "
        let text = prefix + firstLine
        return String(text.prefix(300))
    }

    func updateSessionActivity(sessionID: String, previous: SessionStatus?, current: SessionStatus) {
        sessionActivities[sessionID] = ActivityTracker.updateSessionActivity(
            sessionID: sessionID,
            previous: previous,
            current: current,
            existing: sessionActivities[sessionID],
            messages: messages,
            currentSessionID: currentSessionID
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
            messages: messages
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
                messages: self.messages
            )
            self.setSessionActivityText(sessionID: sessionID, best)
        }
    }

    func clearCurrentSessionViewState() {
        sessionLoadingID = UUID()
        messageStore.stepTimings = [:]
        messageStore.clearPartTypes()
        messages = []
        partsByMessage = [:]
        sessionDiffs = []
    }

    func clearSessionScopedCaches(sessionID: String) {
        sessionStatuses[sessionID] = nil
        sessionTodos[sessionID] = nil
        sessionScope.remove(sessionID: sessionID)
        messageStore.removeTimings(forSession: sessionID)
        messageStore.removePartTypes(forSession: sessionID)

        persistDraftInputs()
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
