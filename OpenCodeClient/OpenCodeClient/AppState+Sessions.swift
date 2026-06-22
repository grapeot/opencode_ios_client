import Foundation
import os

/// Session-list CRUD + connection bootstrap.
///
/// - Connection lifecycle: `configure` saves credentials, `testConnection`
///   probes `/health` and kicks off SSE on success.
/// - Session list: `loadSessions` / `loadMoreSessions` / `refreshSessions`
///   pull a window of sessions; `upsertSession` / `selectSession` /
///   `createSession` / `forkSession` / `archiveSession` / `restoreSession` /
///   `deleteSession` are user actions.
/// - Bootstrap: `bootstrapSyncCurrentSession` runs after SSE
///   reconnect to make sure the currently selected session is still valid
///   and its derived state (messages, permissions, status) is fresh.
extension AppState {
    func fetchSessions(limit: Int) async throws -> [Session] {
        let directory = effectiveProjectDirectory
        let loaded = try await apiClient.sessions(directory: directory, limit: limit)
        let archivedCount = loaded.filter(\.isArchived).count
        Self.logger.debug("loadSessions: directory=\(directory ?? "nil", privacy: .public) limit=\(limit, privacy: .public) count=\(loaded.count, privacy: .public) archived=\(archivedCount, privacy: .public) ids=\(loaded.prefix(5).map(\.id).joined(separator: ","), privacy: .public)")
        return loaded
    }

    func toggleSessionExpanded(_ sessionID: String) {
        if expandedSessionIDs.contains(sessionID) {
            expandedSessionIDs.remove(sessionID)
        } else {
            expandedSessionIDs.insert(sessionID)
        }
    }

    func upsertSession(_ session: Session) {
        let existingIndex = sessions.firstIndex(where: { $0.id == session.id })
        if let existingIndex, sessions[existingIndex] == session { return }

        sessions.removeAll { $0.id == session.id }

        let targetIndex: Int
        if let existingIndex {
            targetIndex = min(existingIndex, sessions.count)
        } else {
            targetIndex = 0
        }

        sessions.insert(session, at: targetIndex)
    }

    func configure(serverURL: String, username: String? = nil, password: String? = nil) {
        // Keep raw user input; security normalization happens at request time.
        self.serverURL = serverURL
        self.username = username ?? ""
        self.password = password ?? ""
    }

    func testConnection() async {
        connectionError = nil
        updateConnectionDiagnostic(phase: .health, message: L10n.t(.hostDiagnosticCheckingHealth))

        #if !os(visionOS)
        if currentHostProfile?.transport == .sshTunnel || sshTunnelManager.config.isEnabled {
            updateConnectionDiagnostic(
                phase: .sshGateway,
                message: L10n.t(.hostDiagnosticConnectingSSHGateway),
                recoveryHint: L10n.t(.hostDiagnosticHintConfirmGateway)
            )
            if sshTunnelManager.status != .connected {
                await sshTunnelManager.connect()
            }
            if case .error(let message) = sshTunnelManager.status {
                isConnected = false
                connectionError = L10n.t(.hostDiagnosticSSHTunnelFailed, message)
                updateConnectionDiagnostic(
                    phase: .failed,
                    message: connectionError ?? message,
                    recoveryHint: L10n.t(.hostDiagnosticHintCopyDeviceKeyAgain)
                )
                return
            }
            updateConnectionDiagnostic(
                phase: .localTunnel,
                message: L10n.t(.hostDiagnosticTunnelReadyCheckingHealth)
            )
        }
        #endif

        let info = Self.serverURLInfo(serverURL)
        guard info.isAllowed, let baseURL = info.normalized else {
            isConnected = false
            connectionError = info.warning ?? L10n.t(.errorInvalidBaseURL)
            updateConnectionDiagnostic(
                phase: .failed,
                message: connectionError ?? L10n.t(.errorInvalidBaseURL),
                recoveryHint: L10n.t(.hostDiagnosticHintURLFormat)
            )
            return
        }

        await apiClient.configure(baseURL: baseURL, username: username.isEmpty ? nil : username, password: password.isEmpty ? nil : password)
        do {
            updateConnectionDiagnostic(phase: .health, message: L10n.t(.hostDiagnosticCheckingHealthURL, baseURL))
            let health = try await apiClient.health()
            isConnected = health.healthy
            serverVersion = health.version
            if isConnected {
                updateConnectionDiagnostic(
                    phase: .connected,
                    message: L10n.t(.hostDiagnosticConnectedToOpenCode, health.version.map { " \($0)" } ?? "")
                )
                connectSSE()
            } else {
                connectionError = L10n.t(.hostDiagnosticHealthUnhealthy)
                updateConnectionDiagnostic(
                    phase: .failed,
                    message: connectionError ?? L10n.t(.hostDiagnosticHealthUnhealthy),
                    recoveryHint: L10n.t(.hostDiagnosticHintCheckServerLogs)
                )
            }
        } catch {
            isConnected = false
            let message = friendlyConnectionError(error, phase: .health)
            connectionError = message
            updateConnectionDiagnostic(
                phase: .failed,
                message: message,
                recoveryHint: L10n.t(.hostDiagnosticHintVerifyHostConfig)
            )
        }
    }

    func loadProjects() async {
        guard isConnected else { return }
        isLoadingProjects = true
        do {
            projects = try await apiClient.projects()
            serverCurrentProjectWorktree = (try? await apiClient.projectCurrent())?.worktree
        } catch {
            Self.logger.warning("loadProjects failed: \(error.localizedDescription)")
            projects = []
        }
        isLoadingProjects = false
    }

    func loadSessions() async {
        guard isConnected else { return }
        do {
            let loaded = try await fetchSessions(limit: loadedSessionLimit)
            sessions = loaded
            hasMoreSessions = loaded.count >= loadedSessionLimit

            // Only auto-select first session if there's no persisted selection at all
            // This handles the case of fresh install or after all sessions are deleted
            if currentSessionID == nil, let first = sessions.first {
                currentSessionID = first.id
                applySavedModelForCurrentSession()
            }

            // A persisted session was restored on launch but its messages were
            // never fetched (selectSession is the only path that loads them, and
            // it short-circuits when the id already matches). Without this, a
            // relaunch lands on the last session showing an empty transcript
            // until the user manually switches away and back. Hydrate it once.
            if let restoredID = currentSessionID,
               messages.isEmpty,
               sessions.contains(where: { $0.id == restoredID }) {
                applySavedModelForCurrentSession()
                await loadMessages()
                await refreshPendingPermissions()
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadMoreSessions() async {
        guard isConnected else { return }
        guard hasMoreSessions else { return }
        guard !isLoadingMoreSessions else { return }

        isLoadingMoreSessions = true
        let nextLimit = Self.nextSessionFetchLimit(current: loadedSessionLimit)
        defer { isLoadingMoreSessions = false }

        do {
            let loaded = try await fetchSessions(limit: nextLimit)
            loadedSessionLimit = nextLimit
            sessions = loaded
            hasMoreSessions = loaded.count >= loadedSessionLimit

            if currentSessionID == nil, let first = sessions.first {
                currentSessionID = first.id
                applySavedModelForCurrentSession()
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadAgents() async {
        guard isConnected else { return }
        isLoadingAgents = true
        do {
            let loaded = try await apiClient.agents()
            agents = loaded
            if selectedAgentIndex >= visibleAgents.count && !visibleAgents.isEmpty {
                selectedAgentIndex = 0
            }
        } catch {
            Self.logger.warning("loadAgents failed: \(error.localizedDescription)")
        }
        isLoadingAgents = false
    }

    func refreshSessions() async {
        guard isConnected else { return }
        await loadSessions()
        await syncSessionStatusesFromPoll()
    }

    func selectSession(_ session: Session) {
        guard currentSessionID != session.id else { return }

        // Generate new loading ID to invalidate any in-flight tasks from previous session
        let loadingID = UUID()
        sessionLoadingID = loadingID

        messageStore.resetStreaming()
        messages = []
        partsByMessage = [:]
        currentSessionID = session.id
        applySavedModelForCurrentSession()

        Task { [weak self] in
            guard let self else { return }
            // Check if this task is still current before proceeding
            guard self.sessionLoadingID == loadingID else { return }

            await self.refreshSessions()
            guard self.sessionLoadingID == loadingID else { return }

            await self.loadMessages()
            guard self.sessionLoadingID == loadingID else { return }

            await self.refreshPendingPermissions()
            guard self.sessionLoadingID == loadingID else { return }

            await self.refreshPendingQuestions()
            guard self.sessionLoadingID == loadingID else { return }

            self.syncModelFromMessageHistory()
            await self.loadSessionDiff()
            guard self.sessionLoadingID == loadingID else { return }

            await self.loadSessionTodos()
            guard self.sessionLoadingID == loadingID else { return }
        }
    }

    func isBusySession(_ status: SessionStatus?) -> Bool {
        guard let type = status?.type else { return false }
        return type == "busy" || type == "retry"
    }

    func loadSessionTodos() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let todos = try await apiClient.sessionTodos(sessionID: sessionID)
            sessionTodos[sessionID] = todos
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            // keep previous value if any
        }
    }

    func createSession() async {
        guard isConnected else { return }

        let loadingID = UUID()
        sessionLoadingID = loadingID

        do {
            let session = try await apiClient.createSession(title: nil)
            guard sessionLoadingID == loadingID else { return }

            Self.logger.debug("createSession: created id=\(session.id, privacy: .public) directory=\(session.directory, privacy: .public) effectiveProjectDir=\(self.effectiveProjectDirectory ?? "nil", privacy: .public)")

            upsertSession(session)
            currentSessionID = session.id
            if let m = selectedModel {
                selectedModelIDBySessionID[session.id] = m.id
                persistSelectedModelMap()
            }
            messageStore.resetStreaming()
            messages = []
            partsByMessage = [:]
        } catch {
            guard sessionLoadingID == loadingID else { return }
            connectionError = error.localizedDescription
        }
    }

    func forkSession(messageID: String?) async {
        guard isConnected else { return }
        guard let sessionID = currentSessionID else { return }

        let loadingID = UUID()
        sessionLoadingID = loadingID

        do {
            let forked = try await apiClient.forkSession(sessionID: sessionID, messageID: messageID)
            guard sessionLoadingID == loadingID else { return }

            Self.logger.debug("forkSession: created id=\(forked.id, privacy: .public) from=\(sessionID, privacy: .public) messageID=\(messageID ?? "nil", privacy: .public)")

            upsertSession(forked)
            currentSessionID = forked.id
            messageStore.resetStreaming()
            messages = []
            partsByMessage = [:]
            await loadMessages()
            guard sessionLoadingID == loadingID else { return }
            syncModelFromMessageHistory()
        } catch {
            guard sessionLoadingID == loadingID else { return }
            connectionError = error.localizedDescription
        }
    }

    func deleteSession(sessionID: String) async throws {
        let previousCurrentSessionID = currentSessionID
        try await apiClient.deleteSession(sessionID: sessionID)

        sessions.removeAll { $0.id == sessionID }
        clearSessionScopedCaches(sessionID: sessionID)

        let nextSessionID = Self.nextSessionIDAfterDeleting(
            deletedSessionID: sessionID,
            currentSessionID: previousCurrentSessionID,
            remainingSessions: sessions
        )

        guard previousCurrentSessionID == sessionID else {
            currentSessionID = nextSessionID
            return
        }

        clearCurrentSessionViewState()
        if let nextSessionID {
            currentSessionID = nextSessionID
            applySavedModelForCurrentSession()
            await loadMessages()
            await refreshPendingPermissions()
            await loadSessionDiff()
            await loadSessionTodos()
            syncModelFromMessageHistory()
        } else {
            currentSessionID = nil
            pendingPermissions = []
        }
    }

    func archiveSession(sessionID: String) async throws {
        let archived = Int(Date().timeIntervalSince1970 * 1000)
        for id in sessionSubtreeIDs(rootedAt: sessionID, parentFirst: false) {
            let updated = try await apiClient.updateSessionArchived(sessionID: id, archived: archived)
            upsertSession(updated)
        }
    }

    func restoreSession(sessionID: String) async throws {
        for id in sessionSubtreeIDs(rootedAt: sessionID, parentFirst: true) {
            let updated = try await apiClient.updateSessionArchived(sessionID: id, archived: -1)
            upsertSession(updated)
        }
    }

    private func sessionSubtreeIDs(rootedAt rootID: String, parentFirst: Bool) -> [String] {
        var childrenByParent: [String: [String]] = [:]
        for session in sessions {
            guard let parentID = session.parentID else { continue }
            childrenByParent[parentID, default: []].append(session.id)
        }

        func collect(_ id: String) -> [String] {
            let children = (childrenByParent[id] ?? []).flatMap(collect)
            return parentFirst ? [id] + children : children + [id]
        }
        return collect(rootID)
    }

    func bootstrapSyncCurrentSession(reason: String) async {
        guard currentSessionID != nil else { return }
        let start = Date()

        await validateAndRecoverCurrentSession()

        await loadMessages()
        await refreshPendingPermissions()
        await refreshPendingQuestions()
        await syncSessionStatusesFromPoll()
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        Self.logger.debug("bootstrapSync reason=\(reason, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) messages=\(self.messages.count, privacy: .public) permissions=\(self.pendingPermissions.count, privacy: .public)")
    }

    /// Check whether the current session still exists on the server.
    /// If the session was deleted (e.g. server restarted), reset currentSessionID
    /// so the next loadSessions call auto-selects a valid session.
    func validateAndRecoverCurrentSession() async {
        guard let sid = currentSessionID else { return }
        do {
            _ = try await apiClient.messages(sessionID: sid, limit: 1)
        } catch {
            guard case APIError.httpError(let statusCode, _) = error, statusCode == 404 else { return }
            Self.logger.debug("bootstrapSync: current session \(sid) not found on server, resetting")
            currentSessionID = nil
            await loadSessions()
        }
    }

    func syncSessionStatusesFromPoll(markMissingBusyAsIdle: Bool = true) async {
        guard isConnected else { return }
        guard let statuses = try? await apiClient.sessionStatus() else { return }
        mergePolledSessionStatuses(statuses, markMissingBusyAsIdle: markMissingBusyAsIdle)
    }

    func abortSession() async {
        guard let sessionID = currentSessionID else { return }
        do {
            try await apiClient.abort(sessionID: sessionID)
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            connectionError = error.localizedDescription
        }

        await syncSessionStatusesFromPoll(markMissingBusyAsIdle: true)
        await loadMessages()
        await loadSessionDiff()
    }

    func updateSessionTitle(sessionID: String, title: String) async {
        do {
            _ = try await apiClient.updateSession(sessionID: sessionID, title: title)
            await refreshSessions()
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            connectionError = error.localizedDescription
        }
    }
}
