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
            if let session = sessions.first(where: { $0.id == sessionID }), mayHaveUnloadedChildren(session) {
                Task { await loadArchivedChildren(of: sessionID) }
            }
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
        let snapshot = captureHostRequestSnapshot()
        connectionError = nil
        pendingSSHHostKeyMismatch = nil
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
            guard isCurrentHostRequest(snapshot) else { return }
            if case .error(let message) = sshTunnelManager.status {
                isConnected = false
                connectionError = L10n.t(.hostDiagnosticSSHTunnelFailed, message)
                pendingSSHHostKeyMismatch = sshTunnelManager.pendingHostKeyMismatch
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
        guard isCurrentHostRequest(snapshot) else { return }
        do {
            updateConnectionDiagnostic(phase: .health, message: L10n.t(.hostDiagnosticCheckingHealthURL, baseURL))
            let health = try await apiClient.health()
            guard isCurrentHostRequest(snapshot) else { return }
            isConnected = health.healthy
            serverVersion = health.version
            if isConnected {
                // A restart under the same profile may change the server's
                // directory or protocol; probe both again on the next list.
                defaultSessionListDirectory = nil
                serverFiltersArchivedSessions = nil
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
            guard isCurrentHostRequest(snapshot) else { return }
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
        let snapshot = captureHostRequestSnapshot()
        isLoadingProjects = true
        do {
            let loaded = try await apiClient.projects()
            guard isCurrentHostRequest(snapshot) else { return }
            projects = loaded
            let current = try? await apiClient.projectCurrent()
            guard isCurrentHostRequest(snapshot) else { return }
            serverCurrentProjectWorktree = current?.worktree
        } catch {
            guard isCurrentHostRequest(snapshot) else { return }
            Self.logger.warning("loadProjects failed: \(error.localizedDescription)")
            projects = []
        }
        guard isCurrentHostRequest(snapshot) else { return }
        isLoadingProjects = false
    }

    struct SessionListFetch {
        var rows: [Session]
        var hasMore: Bool
        /// Set when the server filtered out archived rows for this directory.
        var filteredDirectory: String?
        /// Filtered path only: the cursor after this first page, nil when it held every active row.
        var nextCursor: Int? = nil
    }

    /// V1 `/session` without a directory lists the server's current project,
    /// while `/experimental/session` without one lists every project and with
    /// one matches `session.directory` exactly. Sessions record the server's
    /// instance directory (`GET /path`), which can differ from the project
    /// worktree (a non-git server reports "/"), so prefer it; cached per host.
    func sessionListDirectory() async -> String? {
        if let directory = effectiveProjectDirectory, !directory.isEmpty { return directory }
        if let cached = defaultSessionListDirectory { return cached.isEmpty ? nil : cached }
        let snapshot = captureHostRequestSnapshot()
        var resolved = try? await apiClient.instanceDirectory()
        guard isCurrentHostRequest(snapshot) else { return nil }
        if resolved?.isEmpty != false {
            resolved = try? await apiClient.projectCurrent()?.worktree
            guard isCurrentHostRequest(snapshot) else { return nil }
        }
        guard let resolved, !resolved.isEmpty else { return nil }
        guard resolved != "/" else {
            // Sessions started at "/" are not a project; the default list keeps
            // the legacy window, cached as "" so it is not reprobed.
            defaultSessionListDirectory = ""
            return nil
        }
        defaultSessionListDirectory = resolved
        return resolved
    }

    /// `/experimental/session` with archive filtering and cursors shipped in
    /// OpenCode 1.2.11. Older 1.x servers proxy unknown paths to
    /// app.opencode.ai, which can answer 5xx or time out when the host is
    /// offline, so they are not probed. Unparseable versions ("local") and
    /// locally compiled binaries ("0.0.0-…") are probed.
    nonisolated static func serverMayFilterArchivedSessions(version: String?) -> Bool {
        guard let version else { return true }
        let core = version.trimmingCharacters(in: .whitespaces).drop { $0 == "v" }
            .split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let parts = core.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, parts.allSatisfy({ $0 != nil }) else { return true }
        let numbers = parts.compactMap { $0 } + [0]
        if numbers.prefix(3).allSatisfy({ $0 == 0 }) { return true }
        return (numbers[0], numbers[1], numbers[2]) >= (1, 2, 11)
    }

    /// A parseable non-zero version; "local", nil and "0.0.0-…" builds are unknown.
    nonisolated static func isKnownServerRelease(version: String?) -> Bool {
        guard let version else { return false }
        let core = version.trimmingCharacters(in: .whitespaces).drop { $0 == "v" }
            .split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let parts = core.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, parts.allSatisfy({ $0 != nil }) else { return false }
        return parts.contains { $0 != 0 }
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    nonisolated static func isUnsupportedSessionPage(_ error: Error) -> Bool {
        if error is DecodingError { return true } // e.g. an HTML 200 from a packaged server
        if let error = error as? URLError { return error.code == .unsupportedURL }
        if case APIError.httpError(let status, _) = error { return [404, 405, 501].contains(status) }
        return false
    }

    /// One page of unarchived rows (roots and children) in `directory`, newest
    /// first. A next cursor that does not strictly decrease is treated as the end.
    func fetchActiveSessionPage(directory: String, cursor: Int?) async throws -> SessionPage {
        var page = try await apiClient.sessionPage(
            directory: directory, includeArchived: false, rootsOnly: false,
            limit: Self.activeSessionPageSize, cursor: cursor
        )
        if let next = page.nextCursor, let cursor, next >= cursor { page.nextCursor = nil }
        Self.logger.debug("loadSessions(filtered): directory=\(directory, privacy: .public) cursor=\(cursor.map(String.init) ?? "nil", privacy: .public) count=\(page.rows.count, privacy: .public)")
        return page
    }

    /// Unarchived rows when the host filters on the server, else the legacy
    /// recent-N window, which mixes in archived rows.
    func fetchSessionList() async throws -> SessionListFetch {
        let snapshot = captureHostRequestSnapshot()
        if serverFiltersArchivedSessions == nil, !Self.serverMayFilterArchivedSessions(version: serverVersion) {
            serverFiltersArchivedSessions = false
        }
        if serverFiltersArchivedSessions != false {
            guard let directory = await sessionListDirectory() else {
                // An unresolved default directory on a filtering host keeps the
                // current list rather than mixing the legacy window into it.
                if serverFiltersArchivedSessions == true, defaultSessionListDirectory == nil { throw CancellationError() }
                return try await fetchLegacySessionList()
            }
            do {
                let page = try await fetchActiveSessionPage(directory: directory, cursor: nil)
                if isCurrentHostRequest(snapshot) { serverFiltersArchivedSessions = true }
                return SessionListFetch(rows: page.rows, hasMore: page.nextCursor != nil,
                                        filteredDirectory: directory, nextCursor: page.nextCursor)
            } catch where Self.isUnsupportedSessionPage(error) {
                if isCurrentHostRequest(snapshot) { serverFiltersArchivedSessions = false }
            } catch where serverFiltersArchivedSessions == nil
                        && !Self.isKnownServerRelease(version: serverVersion)
                        && !Self.isCancellation(error) {
                // Unconfirmed host of unknown version: it may be a pre-1.2.11
                // server whose upstream proxy 5xxs or times out offline. Load
                // the legacy window this time and probe again later. A known
                // release has the route, so its errors surface instead.
                Self.logger.warning("session page probe failed; using legacy list: \(error.localizedDescription)")
            }
        }
        return try await fetchLegacySessionList()
    }

    private func fetchLegacySessionList() async throws -> SessionListFetch {
        let rows = try await fetchSessions(limit: loadedSessionLimit)
        return SessionListFetch(rows: rows, hasMore: rows.count >= loadedSessionLimit, filteredDirectory: nil)
    }

    /// Applies a first-page fetch, keeping archived rows the user paged in for
    /// the same directory. With `keepDeeperPages`, active rows older than the
    /// first page's last row stay as they were (they may be stale until a full
    /// refresh); rows inside the first page's range that it no longer lists
    /// were archived or deleted and leave. `droppedSessionID` is a row the
    /// server just reported gone.
    func applySessionListFetch(
        _ fetched: SessionListFetch,
        capturedSelection: Session?,
        droppedSessionID: String? = nil,
        keepDeeperPages: Bool = true
    ) {
        guard let directory = fetched.filteredDirectory else {
            // A legacy window replaces the list wholesale; filtered paging
            // state from an earlier list must not carry into it or out of it.
            resetArchivedSessionPages()
            archivedSessionDirectory = nil
            activeSessionCursor = nil
            hasLoadedDeeperActivePages = false
            applyFetchedSessionPage(fetched.rows, capturedSelection: capturedSelection)
            hasMoreSessions = fetched.hasMore
            return
        }
        var keepDeeper = keepDeeperPages
        if archivedSessionDirectory != directory {
            resetArchivedSessionPages()
            archivedSessionDirectory = directory
            keepDeeper = false
        }
        if let droppedSessionID { loadedArchivedSessionIDs.remove(droppedSessionID) }
        let activeIDs = Set(fetched.rows.map(\.id))
        // The first page covers every active row with time.updated >= its next
        // cursor (the server pages on `< cursor`); with no cursor it covers all.
        let boundary = fetched.nextCursor
        let deeper = !keepDeeper ? [] : sessions.filter { row in
            !row.isArchived && !activeIDs.contains(row.id) && row.id != droppedSessionID
                && boundary.map { row.time.updated < $0 } == true
        }
        let retained = sessions.filter {
            $0.isArchived && loadedArchivedSessionIDs.contains($0.id) && !activeIDs.contains($0.id)
        }
        applyFetchedSessionPage(fetched.rows + deeper + retained, capturedSelection: capturedSelection)
        if keepDeeper && hasLoadedDeeperActivePages, let next = fetched.nextCursor {
            // Keep paging from the deepest page already loaded (nil when it was the last).
            activeSessionCursor = activeSessionCursor.map { min($0, next) }
        } else {
            activeSessionCursor = fetched.nextCursor
            hasLoadedDeeperActivePages = false
        }
        hasMoreSessions = activeSessionCursor != nil
    }

    func resetArchivedSessionPages() {
        loadedArchivedSessionIDs = []
        archivedChildrenLoadedIDs = []
        archivedSessionCursor = nil
        hasLoadedArchivedSessions = false
        hasMoreArchivedSessions = false
    }

    /// Adds rows not already present. A local row is never replaced by a page
    /// row, which may predate a restore made from this device.
    func addMissingSessions(_ rows: [Session]) {
        var known = Set(sessions.map(\.id))
        let missing = sessionScope.confirmedMissingSessionIDs
        let added = rows.filter { !missing.contains($0.id) && known.insert($0.id).inserted }
        guard !added.isEmpty else { return }
        sessions.append(contentsOf: added)
    }

    /// Archived rows that head an archived subtree: roots, and rows whose
    /// parent is not known to be archived (a child archived on its own under an
    /// active parent, or an orphan). Rows under an archived parent arrive when
    /// that parent expands.
    nonisolated static func archivedSubtreeTops(_ rows: [Session], known: [Session]) -> [Session] {
        let archivedIDs = Set((rows + known).filter(\.isArchived).map(\.id))
        return rows.filter { row in
            row.isArchived && !(row.parentID.map(archivedIDs.contains) ?? false)
        }
    }

    /// Archived subtree tops, newest first. `archived=true` returns every row,
    /// so one load reads server pages until it has a page of tops.
    func loadArchivedSessions(reset: Bool = false) async {
        guard isConnected, let directory = archivedSessionDirectory,
              archivedLoadingDirectory != directory else { return }
        guard reset || !hasLoadedArchivedSessions || hasMoreArchivedSessions else { return }
        let snapshot = captureHostRequestSnapshot()
        archivedLoadingDirectory = directory
        defer { if archivedLoadingDirectory == directory { archivedLoadingDirectory = nil } }
        var cursor = reset ? nil : archivedSessionCursor
        var collected: [Session] = []
        var exhausted = false
        do {
            for _ in 0..<Self.maxArchivedRequestsPerLoad {
                let page = try await apiClient.sessionPage(
                    directory: directory, includeArchived: true, rootsOnly: false,
                    limit: Self.archivedSessionRequestSize, cursor: cursor
                )
                guard isCurrentHostRequest(snapshot), archivedSessionDirectory == directory else { return }
                collected.append(contentsOf: page.rows)
                guard let next = page.nextCursor, cursor.map({ next < $0 }) ?? true else {
                    exhausted = true
                    break
                }
                cursor = next
                if Self.archivedSubtreeTops(collected, known: sessions).count >= Self.archivedSessionPageSize { break }
            }
        } catch {
            guard isCurrentHostRequest(snapshot) else { return }
            Self.logger.warning("loadArchivedSessions failed: \(error.localizedDescription)")
            return
        }
        if reset {
            let dropped = loadedArchivedSessionIDs
            sessions.removeAll { dropped.contains($0.id) && $0.isArchived && $0.id != currentSessionID }
            resetArchivedSessionPages()
        }
        let tops = Self.archivedSubtreeTops(collected, known: sessions)
        addMissingSessions(tops)
        loadedArchivedSessionIDs.formUnion(tops.map(\.id))
        archivedSessionCursor = exhausted ? nil : cursor
        hasMoreArchivedSessions = !exhausted
        hasLoadedArchivedSessions = true
        // A reset drops children, so rows the user left expanded reload theirs.
        for id in expandedSessionIDs {
            if let session = sessions.first(where: { $0.id == id }), mayHaveUnloadedChildren(session) {
                await loadArchivedChildren(of: id)
            }
        }
    }

    /// Keeps rows this device just archived in a loaded archived section when
    /// they fall inside the window already paged in; older rows wait for the
    /// user to page that far, as they would after any refresh. No request.
    func noteArchivedInPlace(_ ids: Set<String>) {
        guard usesFilteredSessionList, hasLoadedArchivedSessions, !ids.isEmpty else { return }
        let loadedTops = sessions.filter { loadedArchivedSessionIDs.contains($0.id) && $0.isArchived }
        let oldest = hasMoreArchivedSessions ? loadedTops.map(\.time.updated).min() : nil
        let archived = sessions.filter { ids.contains($0.id) && $0.isArchived }
        let tops = Self.archivedSubtreeTops(archived, known: sessions)
        loadedArchivedSessionIDs.formUnion(tops.filter { row in oldest.map { row.time.updated >= $0 } ?? true }.map(\.id))
    }

    /// Archived rows are paged in as subtree tops; children arrive when a row expands.
    func mayHaveUnloadedChildren(_ session: Session) -> Bool {
        usesFilteredSessionList && session.isArchived && !archivedChildrenLoadedIDs.contains(session.id)
    }

    func loadArchivedChildren(of sessionID: String) async {
        guard usesFilteredSessionList, archivedChildrenLoadedIDs.insert(sessionID).inserted else { return }
        let snapshot = captureHostRequestSnapshot()
        let directory = archivedSessionDirectory
        do {
            let children = try await apiClient.sessionChildren(sessionID: sessionID)
            guard isCurrentHostRequest(snapshot), archivedSessionDirectory == directory else { return }
            addArchivedChildren(children, of: sessionID)
        } catch {
            guard isCurrentHostRequest(snapshot), archivedSessionDirectory == directory else { return }
            archivedChildrenLoadedIDs.remove(sessionID)
            Self.logger.warning("loadArchivedChildren failed: \(error.localizedDescription)")
        }
    }

    private func addArchivedChildren(_ children: [Session], of sessionID: String) {
        let rows = children.filter { $0.parentID == sessionID }
        addMissingSessions(rows)
        loadedArchivedSessionIDs.formUnion(rows.filter(\.isArchived).map(\.id))
        archivedChildrenLoadedIDs.insert(sessionID)
    }

    /// Restore walks the loaded subtree, so it first fetches every descendant
    /// afresh (the expand cache can predate later archives), level by level
    /// with bounded concurrency. Throws when any level cannot be read, so a
    /// restore never silently stops at the root.
    func fetchArchivedDescendants(of rootID: String) async throws {
        guard usesFilteredSessionList else { return }
        let snapshot = captureHostRequestSnapshot()
        let api = apiClient
        var frontier = [rootID]
        var seen: Set<String> = [rootID]
        while !frontier.isEmpty {
            // Restoring part of a subtree would leave the rest unreachable.
            guard seen.count <= Self.descendantRestoreCap else { throw URLError(.dataLengthExceedsMaximum) }
            var fetched: [(String, [Session])] = []
            for chunk in stride(from: 0, to: frontier.count, by: Self.descendantFetchConcurrency) {
                let ids = frontier[chunk..<min(chunk + Self.descendantFetchConcurrency, frontier.count)]
                try await withThrowingTaskGroup(of: (String, [Session]).self) { group in
                    for id in ids { group.addTask { (id, try await api.sessionChildren(sessionID: id)) } }
                    for try await result in group { fetched.append(result) }
                }
            }
            guard isCurrentHostRequest(snapshot) else { throw CancellationError() }
            var next: [String] = []
            for (id, children) in fetched {
                addArchivedChildren(children, of: id)
                for child in children where child.parentID == id && seen.insert(child.id).inserted {
                    next.append(child.id)
                }
            }
            frontier = next
        }
    }

    /// Reloads the first page. `resetPaging` (pull to refresh) also drops
    /// deeper active pages, so everything shown is fresh from the server.
    func loadSessions(resetPaging: Bool = false) async {
        guard isConnected else { return }
        let snapshot = captureHostRequestSnapshot()
        let directoryKey = effectiveProjectDirectory
        do {
            let selectedSession = currentSession
            let fetched = try await fetchSessionList()
            // A later project switch owns the list; a slower earlier fetch must not overwrite it.
            guard isCurrentHostRequest(snapshot), effectiveProjectDirectory == directoryKey else { return }
            applySessionListFetch(fetched, capturedSelection: selectedSession, keepDeeperPages: !resetPaging)
            selectFirstAvailableSessionIfNeeded()

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
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentHostRequest(snapshot) else { return }
            connectionError = error.localizedDescription
        }
    }

    func loadMoreSessions() async {
        guard isConnected else { return }
        guard hasMoreSessions else { return }
        guard !isLoadingMoreSessions else { return }
        if usesFilteredSessionList {
            await loadMoreActiveSessions()
            return
        }

        isLoadingMoreSessions = true
        let snapshot = captureHostRequestSnapshot()
        let directoryKey = effectiveProjectDirectory
        let nextLimit = Self.nextSessionFetchLimit(current: loadedSessionLimit)
        defer {
            if isCurrentHostRequest(snapshot) {
                isLoadingMoreSessions = false
            }
        }

        do {
            let selectedSession = currentSession
            let loaded = try await fetchSessions(limit: nextLimit)
            // A project switch may have moved the list to the filtered path meanwhile.
            guard isCurrentHostRequest(snapshot), !usesFilteredSessionList,
                  effectiveProjectDirectory == directoryKey else { return }
            loadedSessionLimit = nextLimit
            applyFetchedSessionPage(loaded, capturedSelection: selectedSession)
            hasMoreSessions = loaded.count >= loadedSessionLimit
            selectFirstAvailableSessionIfNeeded()
        } catch {
            guard isCurrentHostRequest(snapshot) else { return }
            connectionError = error.localizedDescription
        }
    }

    /// Appends the next active page without re-downloading earlier ones.
    private func loadMoreActiveSessions() async {
        guard let directory = archivedSessionDirectory, let cursor = activeSessionCursor else { return }
        isLoadingMoreSessions = true
        let snapshot = captureHostRequestSnapshot()
        defer { if isCurrentHostRequest(snapshot) { isLoadingMoreSessions = false } }
        do {
            let page = try await fetchActiveSessionPage(directory: directory, cursor: cursor)
            guard isCurrentHostRequest(snapshot), archivedSessionDirectory == directory,
                  activeSessionCursor == cursor else { return }
            addMissingSessions(page.rows.filter { !$0.isArchived })
            activeSessionCursor = page.nextCursor
            hasLoadedDeeperActivePages = true
            hasMoreSessions = page.nextCursor != nil
        } catch {
            guard isCurrentHostRequest(snapshot) else { return }
            connectionError = error.localizedDescription
        }
    }

    func applyFetchedSessionPage(_ loaded: [Session], capturedSelection: Session?) {
        let missing = sessionScope.confirmedMissingSessionIDs
        var next = loaded.filter { !missing.contains($0.id) }
        if let selectedSession = capturedSelection,
           currentSessionID == selectedSession.id,
           !missing.contains(selectedSession.id),
           !next.contains(where: { $0.id == selectedSession.id }) {
            next.insert(selectedSession, at: 0)
        }
        sessions = next
    }

    func selectFirstAvailableSessionIfNeeded() {
        guard currentSessionID == nil else { return }
        let missing = sessionScope.confirmedMissingSessionIDs
        guard let first = sessions.first(where: { !missing.contains($0.id) }) else { return }
        currentSessionID = first.id
        applySavedModelForCurrentSession()
    }

    func loadAgents() async {
        guard isConnected else { return }
        let snapshot = captureHostRequestSnapshot()
        isLoadingAgents = true
        do {
            let loaded = try await apiClient.agents()
            guard isCurrentHostRequest(snapshot) else { return }
            let previous = selectedAgentName
            agents = loaded
            hasServerAgentCatalog = true
            reconcileSelectedAgent(preferredName: previous)
        } catch {
            guard isCurrentHostRequest(snapshot) else { return }
            Self.logger.warning("loadAgents failed: \(error.localizedDescription)")
        }
        guard isCurrentHostRequest(snapshot) else { return }
        isLoadingAgents = false
    }

    func refreshSessions(resetPaging: Bool = false) async {
        guard isConnected else { return }
        await loadSessions(resetPaging: resetPaging)
        await syncSessionStatusesFromPoll()
    }

    func openReferencedSession(sessionID: String) async {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sendError = L10n.t(.errorSessionNotFound)
            return
        }
        do {
            let session: Session
            if let existing = sessions.first(where: { $0.id == trimmed }) {
                session = existing
            } else {
                session = try await apiClient.session(sessionID: trimmed)
            }
            sessionScope.confirmedMissingSessionIDs.remove(session.id)
            let previousDirectory = effectiveProjectDirectory
            applyProjectDirectory(for: session)
            upsertSession(session)
            selectedTab = RootTab.chat.rawValue
            if currentSessionID != session.id {
                selectSession(session)
            }
            if effectiveProjectDirectory != previousDirectory {
                await loadFileTree()
            }
        } catch {
            if case APIError.httpError(let statusCode, _) = error, statusCode == 404 {
                sendError = L10n.t(.errorSessionNotFound)
            } else {
                sendError = error.localizedDescription
            }
        }
    }

    func selectSession(_ session: Session) {
        // Capture and commit synchronously on the main actor, before markViewed/current/load
        // can change the displayed reminder. No later response or exit expands this snapshot.
        let presentation = sessionIndicatorPresentations[session.id]
        if presentation?.indicator == .unread, presentation?.needsSync == false {
            let sources = sessionBlueReminderSources[session.id] ?? [:]
            readStateStore.acknowledgeBlue(sessionID: session.id, sources: sources)
        }
        readStateStore.markViewed(sessionID: session.id, at: Date())
        guard currentSessionID != session.id else { return }

        // Generate new loading ID to invalidate any in-flight tasks from previous session
        let loadingID = UUID()
        sessionLoadingID = loadingID

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

    func loadSessionTodos(allowMissingSessionRecovery: Bool = true) async {
        guard let sessionID = currentSessionID else { return }
        do {
            let todos = try await apiClient.sessionTodos(sessionID: sessionID)
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                return
            }
            sessionTodos[sessionID] = todos
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(
                error: error,
                requestedSessionID: sessionID,
                allowMissingSessionRecovery: allowMissingSessionRecovery
            ) {
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
            let session = try await apiClient.createSession(title: nil, directory: effectiveProjectDirectory)
            guard sessionLoadingID == loadingID else { return }

            Self.logger.debug("createSession: created id=\(session.id, privacy: .public) directory=\(session.directory, privacy: .public) effectiveProjectDir=\(self.effectiveProjectDirectory ?? "nil", privacy: .public)")

            upsertSession(session)
            currentSessionID = session.id
            readStateStore.markViewed(sessionID: session.id, at: Date())
            if let m = selectedModel {
                selectedModelIDBySessionID[session.id] = m.id
                persistSelectedModelMap()
            }
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
            readStateStore.markViewed(sessionID: forked.id, at: Date())
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
        let selectionAtStart = currentSessionID
        let sourceHost = captureHostRequestSnapshot()
        try await apiClient.deleteSession(sessionID: sessionID)
        guard isCurrentHostRequest(sourceHost) else {
            messageStore.removeOutboundSends(hostProfileID: sourceHost.hostProfileID, sessionID: sessionID)
            return
        }

        let selectionIsDeletedTarget = currentSessionID == sessionID
        let mayNavigateToReplacement = selectionAtStart == sessionID && selectionIsDeletedTarget
        // Drop the chat-bound preview before selection moves. The session-change
        // callback clears previewSessionID while leaving a regular column in place.
        if selectionIsDeletedTarget, previewSessionID == sessionID {
            closeFilePreview()
        }
        noteConfirmedMissingSession(sessionID, hostProfileID: sourceHost.hostProfileID, clearSelection: selectionIsDeletedTarget)
        guard mayNavigateToReplacement else { return }

        guard let nextSessionID = Self.nextSessionIDAfterDeleting(
            deletedSessionID: sessionID,
            currentSessionID: sessionID,
            remainingSessions: sessions
        ) else {
            return
        }

        currentSessionID = nextSessionID
        readStateStore.markViewed(sessionID: nextSessionID, at: Date())
        applySavedModelForCurrentSession()
        await loadMessages()
        guard currentSessionID == nextSessionID else { return }
        await refreshPendingPermissions()
        guard currentSessionID == nextSessionID else { return }
        await loadSessionDiff()
        guard currentSessionID == nextSessionID else { return }
        await loadSessionTodos()
        guard currentSessionID == nextSessionID else { return }
        syncModelFromMessageHistory()
    }

    func archiveSession(sessionID: String) async throws {
        // A single-row archive already covers its subtree. Unlike a counted
        // batch, it may include descendants discovered during execution.
        let scope = sessionArchiveScope
        let selected: Set<String> = [sessionID]
        var plan = SessionArchivePlan(sessions: sessions, selected: selected)
        while !plan.ids.isEmpty {
            let result = await archiveSessions(plan, in: scope)
            guard sessionArchiveScope == scope, !Task.isCancelled else { return }
            if result.remaining == 0 { return }
            if let error = result.firstError { throw error }
            let revisedPlan = SessionArchivePlan(sessions: sessions, selected: selected)
            guard result.foundMoreChildren, !revisedPlan.ids.isEmpty,
                  Set(revisedPlan.ids) != Set(plan.ids) else {
                throw SessionArchiveError.unconfirmed
            }
            plan = revisedPlan
        }
    }

    /// `fetchDescendants` loads archived descendants first, so the whole
    /// subtree comes back; the send path skips it and restores what is loaded.
    func restoreSession(sessionID: String, fetchDescendants: Bool = true) async throws {
        let host = captureHostRequestSnapshot()
        if fetchDescendants {
            do { try await fetchArchivedDescendants(of: sessionID) } catch is CancellationError { return }
        }
        guard isCurrentHostRequest(host) else { return }
        for id in sessionSubtreeIDs(rootedAt: sessionID, parentFirst: true) {
            guard isCurrentHostRequest(host) else { return }
            let updated = try await apiClient.updateSessionArchived(sessionID: id, archived: -1)
            guard isCurrentHostRequest(host) else { return }
            guard !sessionScope.confirmedMissingSessionIDs.contains(id) else { return }
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
        let host = captureHostRequestSnapshot()
        let epoch = pendingRequestEpoch
        await refreshPendingPermissions()
        guard isCurrentHostRequest(host), pendingRequestEpoch == epoch else { return }
        await refreshPendingQuestions()
        guard isCurrentHostRequest(host), pendingRequestEpoch == epoch else { return }
        await syncSessionStatusesFromPoll()
        guard isCurrentHostRequest(host) else { return }
        guard currentSessionID != nil else { return }
        let start = Date()

        await validateAndRecoverCurrentSession()
        guard isCurrentHostRequest(host) else { return }

        await loadMessages()
        guard isCurrentHostRequest(host) else { return }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        Self.logger.debug("bootstrapSync reason=\(reason, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) messages=\(self.messages.count, privacy: .public) permissions=\(self.pendingPermissions.count, privacy: .public)")
    }

    func validateAndRecoverCurrentSession() async {
        guard let sid = currentSessionID else { return }
        do {
            _ = try await apiClient.messages(sessionID: sid, limit: 1)
        } catch {
            guard isSessionNotFoundError(error) else { return }
            guard currentSessionID == sid else { return }
            Self.logger.debug("bootstrapSync: current session \(sid, privacy: .public) not found on server, resetting")
            await recoverMissingCurrentSession(sid)
        }
    }

    func syncSessionStatusesFromPoll(markMissingBusyAsIdle: Bool = true) async {
        guard isConnected, statusPollID == nil else { return }
        let id = UUID()
        statusPollID = id
        let host = captureHostRequestSnapshot()
        let directory = effectiveProjectDirectory ?? serverCurrentProjectWorktree
        let revisions = statusRevisions
        let knowledgeRevision = statusKnowledgeRevision
        statusLastAttemptAt = Date()
        statusLastAttemptDirectory = directory
        defer {
            if statusPollID == id { statusPollID = nil; statusEvaluationDate = Date() }
        }
        guard let statuses = try? await apiClient.sessionStatus(directory: directory),
              isCurrentHostRequest(host), statusPollID == id,
              knowledgeRevision == statusKnowledgeRevision,
              directory == (effectiveProjectDirectory ?? serverCurrentProjectWorktree) else { return }
        applyStatusSnapshot(statuses, revisionsAtStart: revisions, directory: directory,
                            markMissingAsIdle: markMissingBusyAsIdle)
    }

    func refreshVisibleSessionStatus() async {
        statusEvaluationDate = Date()
        if statusLastAttemptDirectory != (effectiveProjectDirectory ?? serverCurrentProjectWorktree) {
            statusLastAttemptAt = nil
        }
        guard statusLastAttemptAt.map({ Date().timeIntervalSince($0) >= 29 }) ?? true else { return }
        let host = captureHostRequestSnapshot()
        await syncSessionStatusesFromPoll()
        guard isCurrentHostRequest(host) else { return }
        await refreshPendingPermissions()
        guard isCurrentHostRequest(host) else { return }
        await refreshPendingQuestions()
    }

    /// A lightweight visible/foreground clock, independent of all network awaits.
    /// Injection keeps the production scheduling path testable without waiting a minute.
    func runSessionStatusExpiryTicks(
        now: () -> Date = { Date() },
        sleep: () async throws -> Void = { try await Task.sleep(for: .seconds(5)) }
    ) async {
        while !Task.isCancelled {
            statusEvaluationDate = now()
            do { try await sleep() } catch { return }
        }
    }

    func abortSession() async {
        guard let sessionID = currentSessionID else { return }
        let host = captureHostRequestSnapshot()
        abortingSessionIDs.insert(sessionID)
        do {
            try await apiClient.abort(sessionID: sessionID)
        } catch {
            guard isCurrentHostRequest(host) else { return }
            abortingSessionIDs.remove(sessionID)
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            connectionError = error.localizedDescription
        }

        guard isCurrentHostRequest(host) else { return }

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
