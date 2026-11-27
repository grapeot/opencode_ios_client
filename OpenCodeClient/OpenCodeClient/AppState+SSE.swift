import Foundation
import os

/// Server-sent events: connection lifecycle with backoff reconnect,
/// per-event dispatch, polled status reconciliation, per-session
/// activity text debouncing, and the recovery paths triggered when an
/// event implies the current session was deleted server-side.
extension AppState {
    func connectSSE() {
        statusStreamConnected = false
        invalidateSessionStatusKnowledge()
        invalidatePendingRequestEpoch()
        sseTask?.cancel()
        sseWatchdogTask?.cancel()
        sseWatchdogTask = nil
        sseConnectionToken &+= 1
        let token = sseConnectionToken
        let host = captureHostRequestSnapshot()
        sseTask = Task { [weak self] in
            await self?.runSSEConnection(token: token, host: host)
        }
    }

    func captureSSEConnectionToken() -> UInt64 {
        sseConnectionToken
    }

    func isCurrentSSEConnection(_ token: UInt64) -> Bool {
        sseConnectionToken == token
    }

    private func isOwnedSSEConnection(_ token: UInt64, _ host: HostRequestSnapshot) -> Bool {
        isCurrentSSEConnection(token) && isCurrentHostRequest(host)
    }

    private func runSSEConnection(token: UInt64, host: HostRequestSnapshot) async {
        var attempt = 0
        while !Task.isCancelled && isOwnedSSEConnection(token, host) {
            let info = Self.serverURLInfo(serverURL)
            guard info.isAllowed, let baseURL = info.normalized else { break }
            let credentialUser = username.isEmpty ? nil : username
            let credentialPassword = password.isEmpty ? nil : password
            let lease: SSEStreamLease
            if let client = sseClient as? SSEClient {
                lease = await client.connectLease(
                    baseURL: baseURL,
                    username: credentialUser,
                    password: credentialPassword
                )
            } else {
                lease = SSEStreamLease(
                    events: await sseClient.connect(
                        baseURL: baseURL,
                        username: credentialUser,
                        password: credentialPassword
                    ),
                    cancel: {}
                )
            }
            let cancelLease = lease.cancel
            let shouldContinue = await withTaskCancellationHandler {
                guard !Task.isCancelled, isOwnedSSEConnection(token, host) else { return false }
                do {
                    statusStreamConnected = true
                    await bootstrapSyncCurrentSession(reason: "sse.reconnect")
                    guard !Task.isCancelled, isOwnedSSEConnection(token, host) else { return false }
                    carLiveReplies.noteConnected()
                    sseLastFrameAt = Date()
                    launchSSEWatchdog(token: token)
                    for try await event in lease.events {
                        guard !Task.isCancelled, isOwnedSSEConnection(token, host) else { return false }
                        attempt = 0
                        await handleSSEEvent(event)
                        guard !Task.isCancelled, isOwnedSSEConnection(token, host) else { return false }
                    }
                    guard !Task.isCancelled, isOwnedSSEConnection(token, host) else { return false }
                    stopOwnedSSEWatchdog(token: token)
                    statusStreamConnected = false
                    invalidateSessionStatusKnowledge()
                    invalidatePendingRequestEpoch()
                    attempt += 1
                    await sseReconnectSleep(sseBackoffDelay(attempt))
                    return true
                } catch {
                    guard !Task.isCancelled, isOwnedSSEConnection(token, host) else { return false }
                    stopOwnedSSEWatchdog(token: token)
                    statusStreamConnected = false
                    invalidateSessionStatusKnowledge()
                    invalidatePendingRequestEpoch()
                    if let failure = error as? SSEStreamFailure, failure.pausesAutomaticRetry {
                        pauseSSEAfterAuthenticationFailure(failure)
                        return false
                    }
                    attempt += 1
                    await sseReconnectSleep(sseBackoffDelay(attempt))
                    return true
                }
            } onCancel: {
                cancelLease()
            }
            cancelLease()
            if !shouldContinue { break }
        }
        if sseConnectionToken == token {
            statusStreamConnected = false
            stopOwnedSSEWatchdog(token: token)
            sseTask = nil
        }
    }

    private func sseBackoffDelay(_ attempt: Int) -> TimeInterval {
        min(30, pow(2.0, Double(attempt)))
    }

    private func pauseSSEAfterAuthenticationFailure(_ failure: SSEStreamFailure) {
        guard case .httpStatus(let code) = failure else { return }
        let message = friendlyConnectionError(APIError.httpError(statusCode: code, data: Data()))
        connectionError = message
        isConnected = false
        updateConnectionDiagnostic(
            phase: .failed,
            message: message,
            recoveryHint: L10n.t(.hostDiagnosticHintVerifyHostConfig)
        )
    }

    /// Starts the heartbeat watchdog once per connected stream. Not a poller:
    /// it checks every `sseWatchdogCheckInterval` whether any frame (a
    /// heartbeat counts) arrived, and only after `sseSilenceThreshold` of
    /// silence runs one reconciliation. On a host without heartbeats this
    /// degrades to a low-frequency reconcile every ~20-25s of silence.
    private func launchSSEWatchdog(token: UInt64) {
        guard sseConnectionToken == token else { return }
        guard sseWatchdogTask == nil else { return }
        sseWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.sseWatchdogCheckInterval))
                guard !Task.isCancelled else { return }
                guard let self, self.sseConnectionToken == token else { return }
                await self.checkSSEWatchdog()
            }
        }
    }

    private func stopOwnedSSEWatchdog(token: UInt64) {
        guard sseConnectionToken == token else { return }
        sseWatchdogTask?.cancel()
        sseWatchdogTask = nil
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
        statusStreamConnected = false
        invalidateSessionStatusKnowledge()
        invalidatePendingRequestEpoch()
        sseConnectionToken &+= 1
        sseTask?.cancel()
        sseTask = nil
        sseWatchdogTask?.cancel()
        sseWatchdogTask = nil
    }

    func invalidateSessionStatusKnowledge() {
        statusConfirmedAt = [:]
        statusKnowledgeRevision &+= 1
        statusLastAttemptAt = nil
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
            let host = captureHostRequestSnapshot()
            invalidatePendingRequestEpoch()
            let epoch = pendingRequestEpoch
            statusStreamConnected = true
            await refreshPendingPermissions()
            guard isCurrentHostRequest(host), pendingRequestEpoch == epoch else { return }
            await refreshPendingQuestions()
            guard isCurrentHostRequest(host), pendingRequestEpoch == epoch else { return }
            await syncSessionStatusesFromPoll(markMissingBusyAsIdle: true)
            guard isCurrentHostRequest(host), pendingRequestEpoch == epoch else { return }
            carLiveReplies.noteConnected()
        case "session.status":
            if let sessionID = props["sessionID"]?.value as? String,
                let statusObj = props["status"]?.value as? [String: Any] {
                if let status = try? JSONSerialization.data(withJSONObject: statusObj),
                    let decoded = try? JSONDecoder().decode(SessionStatus.self, from: status) {
                    let prev = sessionStatuses[sessionID]
                    statusDirectories[sessionID] = event.directory
                        ?? sessions.first(where: { $0.id == sessionID })?.directory
                        ?? statusDirectories[sessionID]
                    statusRevision &+= 1
                    statusRevisions[sessionID] = statusRevision
                    statusConfirmedAt[sessionID] = Date()
                    sessionStatusUpdatedAt[sessionID] = Date()
                    reconcileSessionFailure(sessionID: sessionID, previous: prev, current: decoded)
                    routeCarLiveReplyStatus(sessionID: sessionID, type: decoded.type)
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
                if sessionScope.confirmedMissingSessionIDs.contains(session.id) {
                    return
                }
                let dir = effectiveProjectDirectory ?? resolvedDefaultSessionListDirectory ?? serverCurrentProjectWorktree
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
            routeCarLiveReplyMessageUpdated(props)
            let eventSessionID = props["sessionID"]?.value as? String
            if let eventSessionID, eventSessionID != currentSessionID {
                acknowledgeOffscreenOutboundUser(properties: props, sessionID: eventSessionID)
            } else if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
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
               let messageID = props["messageID"]?.value as? String {
                if sessionID == currentSessionID {
                    messageStore.removeMessageRow(messageID: messageID)
                } else {
                    messageStore.removeOutboundSendIfMatches(
                        messageID: messageID,
                        hostProfileID: currentHostProfileID,
                        sessionID: sessionID
                    )
                }
            }
        case "server.heartbeat":
            // Explicit no-op: the liveness timestamp is stamped at the
            // handleSSEEvent entry for every frame. Listed here so a
            // heartbeat never silently falls through to `default`.
            break
        case "permission.asked":
            permissionRevision &+= 1
            if let perm = PermissionController.parseAskedEvent(properties: props),
               !pendingPermissions.contains(where: { $0.id == perm.id }) {
                pendingPermissions.append(perm)
            }
        case "permission.replied":
            permissionRevision &+= 1
            PermissionController.applyRepliedEvent(properties: props, to: &pendingPermissions)
        case "question.asked":
            questionRevision &+= 1
            if let question = QuestionController.parseAskedEvent(properties: props),
               !pendingQuestions.contains(where: { $0.id == question.id }) {
                pendingQuestions.append(question)
            }
        case "question.replied", "question.rejected":
            questionRevision &+= 1
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
            let reason = Self.sessionErrorDisplayReason(properties: props)
            if let eventSessionID {
                statusRevision &+= 1
                statusRevisions[eventSessionID] = statusRevision
                let error = props["error"]?.value as? [String: Any]
                if error?["name"] as? String != "AbortError" {
                    pendingSessionErrorAt[eventSessionID] = Date()
                } else {
                    abortingSessionIDs.insert(eventSessionID)
                }
                if let pendingID = messageStore.oldestPendingOutboundID(
                    hostProfileID: currentHostProfileID,
                    sessionID: eventSessionID
                ) {
                    messageStore.markSendFailed(messageID: pendingID, reason: reason)
                    messageStore.untrackPendingOptimisticMessages([pendingID])
                }
                if eventSessionID == currentSessionID {
                    await loadMessages()
                }
            } else if Self.shouldProcessMessageEvent(eventSessionID: nil, currentSessionID: currentSessionID) {
                if let failedSessionID = currentSessionID,
                   let pendingID = messageStore.oldestPendingOutboundID(
                    hostProfileID: currentHostProfileID,
                    sessionID: failedSessionID
                   ) {
                    messageStore.markSendFailed(messageID: pendingID, reason: reason)
                    messageStore.untrackPendingOptimisticMessages([pendingID])
                }
                await loadMessages()
            }
        default:
            break
        }
    }

    func acknowledgeOffscreenOutboundUser(properties: [String: AnyCodable], sessionID: String) {
        guard let infoObj = properties["info"]?.value as? [String: Any],
              JSONSerialization.isValidJSONObject(infoObj),
              let data = try? JSONSerialization.data(withJSONObject: infoObj),
              let info = try? JSONDecoder().decode(Message.self, from: data),
              info.isUser,
              info.sessionID == sessionID else { return }
        messageStore.acknowledgeOutboundSend(
            messageID: info.id,
            hostProfileID: currentHostProfileID,
            sessionID: sessionID
        )
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

    func recomputeSessionActivityAfterMessageSnapshot(sessionID: String) {
        sessionActivities[sessionID] = ActivityTracker.reconcileRunningActivity(
            sessionID: sessionID,
            status: sessionStatuses[sessionID],
            existing: sessionActivities[sessionID],
            messages: messages,
            currentSessionID: currentSessionID
        )
    }

    func reconcileSessionFailure(sessionID: String, previous: SessionStatus?, current: SessionStatus) {
        if isBusySession(current) {
            pendingSessionErrorAt[sessionID] = nil
        } else if current.type == "idle" {
            if let failedAt = pendingSessionErrorAt[sessionID] {
                readStateStore.markFailed(sessionID: sessionID, at: failedAt)
            }
            abortingSessionIDs.remove(sessionID)
            pendingSessionErrorAt[sessionID] = nil
        }
    }

    /// Only a successful snapshot of this project may interpret missing IDs as idle.
    /// An SSE confirmation (even identical) after request start always wins.
    func applyStatusSnapshot(_ statuses: [String: SessionStatus], revisionsAtStart: [String: UInt64],
                             directory: String?, markMissingAsIdle: Bool = true) {
        guard let directory else { return }
        let now = Date()
        let scoped = sessions.filter { $0.directory == directory }
        let recorded = statusDirectories.compactMap { $0.value == directory ? $0.key : nil }
        let ids = Set(scoped.map(\.id)).union(recorded).union(statuses.keys)
        for sid in ids {
            guard statusRevisions[sid, default: 0] == revisionsAtStart[sid, default: 0] else { continue }
            guard let next = statuses[sid] ?? (markMissingAsIdle ? SessionStatus(type: "idle", attempt: nil, message: nil, next: nil) : nil) else { continue }
            let previous = sessionStatuses[sid]
            // A snapshot proves inactivity, not successful completion. It must not
            // erase a prior failure after a missed error or a local abort.
            if isBusySession(next) {
                pendingSessionErrorAt[sid] = nil
            } else if next.type == "idle", let failed = pendingSessionErrorAt.removeValue(forKey: sid) {
                readStateStore.markFailed(sessionID: sid, at: failed)
            }
            sessionStatuses[sid] = next
            statusDirectories[sid] = directory
            statusConfirmedAt[sid] = now
            updateSessionActivity(sessionID: sid, previous: previous, current: next)
            if next.type == "idle" { abortingSessionIDs.remove(sid) }
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
        messages = []
        partsByMessage = [:]
        sessionDiffs = []
    }

    func clearSessionScopedCaches(sessionID: String) {
        sessionStatuses[sessionID] = nil
        statusDirectories[sessionID] = nil
        sessionTodos[sessionID] = nil
        sessionScope.remove(sessionID: sessionID)
        messageStore.removeTimings(forSession: sessionID)
        messageStore.removePartTypes(forSession: sessionID)
        statsStore.remove(sessionID: sessionID)
        readStateStore.remove(sessionID: sessionID)
        pendingSessionErrorAt[sessionID] = nil
        revertResetPendingSessionIDs.remove(sessionID)
        removeHostPreference(sessionID: sessionID)
    }

    func noteConfirmedMissingSession(_ sessionID: String, hostProfileID: UUID, clearSelection: Bool) {
        sessionScope.confirmedMissingSessionIDs.insert(sessionID)
        sessions.removeAll { $0.id == sessionID }
        clearSessionScopedCaches(sessionID: sessionID)
        messageStore.removeOutboundSends(hostProfileID: hostProfileID, sessionID: sessionID)
        guard clearSelection, currentSessionID == sessionID else { return }
        clearCurrentSessionViewState()
        currentSessionID = nil
    }

    func clearSelectionIfCurrent(_ sessionID: String) {
        guard currentSessionID == sessionID else { return }
        clearCurrentSessionViewState()
        currentSessionID = nil
    }

    func isSessionNotFoundError(_ error: Error) -> Bool {
        guard case APIError.httpError(let statusCode, _) = error else { return false }
        return statusCode == 404
    }

    func recoverFromMissingCurrentSessionIfNeeded(
        error: Error,
        requestedSessionID: String,
        allowMissingSessionRecovery: Bool = true
    ) async -> Bool {
        guard isSessionNotFoundError(error) else { return false }
        guard requestedSessionID == currentSessionID else { return true }
        if allowMissingSessionRecovery {
            await recoverMissingCurrentSession(requestedSessionID)
        } else {
            clearSelectionIfCurrent(requestedSessionID)
        }
        return true
    }

    func recoverMissingCurrentSession(_ sessionID: String) async {
        guard currentSessionID == sessionID else { return }
        clearSelectionIfCurrent(sessionID)
        guard isConnected else { return }
        var fetched: SessionListFetch
        do {
            fetched = try await fetchSessionList()
        } catch {
            connectionError = error.localizedDescription
            return
        }
        fetched.rows.removeAll { $0.id == sessionID }
        applySessionListFetch(fetched, capturedSelection: nil, droppedSessionID: sessionID)
        selectFirstAvailableSessionIfNeeded()
        guard let nextID = currentSessionID, nextID != sessionID else { return }
        await loadMessages(allowMissingSessionRecovery: false)
        guard currentSessionID == nextID else { return }
        await refreshPendingPermissions()
        guard currentSessionID == nextID else { return }
        await loadSessionDiff(allowMissingSessionRecovery: false)
        guard currentSessionID == nextID else { return }
        await loadSessionTodos(allowMissingSessionRecovery: false)
        guard currentSessionID == nextID else { return }
        syncModelFromMessageHistory()
    }

    func handleRemoteSessionDeleted(sessionID: String) async {
        let sourceHostID = currentHostProfileID
        let deletedCurrentSession = (sessionID == currentSessionID)
        noteConfirmedMissingSession(sessionID, hostProfileID: sourceHostID, clearSelection: deletedCurrentSession)
        await loadSessions()

        if currentSessionID == nil || currentSessionID == sessionID {
            currentSessionID = nil
            return
        }
        if deletedCurrentSession {
            await refreshPendingPermissions()
            await loadSessionDiff()
            await loadSessionTodos()
            syncModelFromMessageHistory()
        }
    }

    func applySSEEventForTesting(_ event: SSEEvent) async {
        await handleSSEEvent(event)
    }

    private func routeCarLiveReplyStatus(sessionID: String, type: String) {
        if type == "idle" {
            carLiveReplies.noteExplicitIdle(sessionID: sessionID)
        } else if type == "busy" || type == "retry" {
            carLiveReplies.noteBusy(sessionID: sessionID)
        }
    }

    private func routeCarLiveReplyMessageUpdated(_ props: [String: AnyCodable]) {
        let info = props["info"]?.value as? [String: Any]
        guard let sessionID = CarLiveReplyEvent.sessionID(
            topLevel: props["sessionID"]?.value as? String,
            infoSessionID: info?["sessionID"] as? String
        ), CarLiveReplyEvent.isCompletion(info) else { return }
        carLiveReplies.noteMessageUpdated(sessionID: sessionID)
    }
}
