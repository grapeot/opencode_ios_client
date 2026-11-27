import Foundation

struct SessionArchivePlan {
    let ids: [String]
    let additionalCount: Int
    let parentByID: [String: String]

    init(sessions: [Session], selected: Set<String>) {
        let children = Dictionary(grouping: sessions, by: \.parentID)
        var parents: [String: String] = [:]
        for session in sessions { parents[session.id] = session.parentID }
        var visited = Set<String>()
        var ordered: [String] = []
        func visit(_ session: Session) {
            guard visited.insert(session.id).inserted else { return }
            for child in children[session.id] ?? [] { visit(child) }
            if !session.isArchived { ordered.append(session.id) }
        }
        for session in sessions where selected.contains(session.id) && !session.isArchived {
            visit(session)
        }
        ids = ordered
        additionalCount = ordered.count { !selected.contains($0) }
        parentByID = parents
    }
}

struct SessionArchiveScope: Equatable {
    let host: HostRequestSnapshot
    let directory: String?
}

struct SessionArchiveOutcome {
    var archived = Set<String>()
    var missing = Set<String>()
    var remaining = 0
    var foundMoreChildren = false
    var firstError: Error?
}

extension AppState {
    var sessionArchiveScope: SessionArchiveScope {
        .init(host: captureHostRequestSnapshot(), directory: effectiveProjectDirectory)
    }

    func archiveSessions(_ plan: SessionArchivePlan, in scope: SessionArchiveScope) async -> SessionArchiveOutcome {
        var result = SessionArchiveOutcome()
        var blockedAncestors = Set<String>()
        let approvedIDs = Set(plan.ids)
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)

        func blockAncestors(of id: String) {
            var ancestor = plan.parentByID[id]
            while let parent = ancestor, blockedAncestors.insert(parent).inserted {
                ancestor = plan.parentByID[parent]
            }
        }

        for id in plan.ids {
            guard sessionArchiveScope == scope, isConnected, !Task.isCancelled else { break }
            if sessionScope.confirmedMissingSessionIDs.contains(id) {
                result.missing.insert(id)
                continue
            }
            guard !blockedAncestors.contains(id) else { continue }
            do {
                if !sessions.contains(where: { $0.id == id && $0.isArchived }) {
                    let children: [Session]
                    do {
                        children = try await apiClient.sessionChildren(sessionID: id)
                    } catch where isSessionNotFoundError(error) {
                        // Some compatible servers don't implement /children. Only
                        // treat the row as gone if the session endpoint agrees.
                        guard sessionArchiveScope == scope, !Task.isCancelled else { break }
                        do {
                            _ = try await apiClient.session(sessionID: id)
                        } catch where isSessionNotFoundError(error) {
                            guard sessionArchiveScope == scope, !Task.isCancelled else { break }
                            noteConfirmedMissingSession(id, hostProfileID: scope.host.hostProfileID,
                                                        clearSelection: currentSessionID == id)
                            result.missing.insert(id)
                            continue
                        }
                        throw error
                    }
                    guard sessionArchiveScope == scope, isConnected, !Task.isCancelled else { break }
                    // An archived intermediary can still have a reactivated child.
                    var frontier = children.filter { $0.parentID == id }
                    var seen: Set<String> = [id]
                    var discovered: [Session] = []
                    var hasActiveDescendants = false
                    while let child = frontier.popLast() {
                        guard seen.insert(child.id).inserted,
                              !sessionScope.confirmedMissingSessionIDs.contains(child.id) else { continue }
                        discovered.append(child)
                        if child.isArchived, !result.archived.contains(child.id) {
                            let nested = try await apiClient.sessionChildren(sessionID: child.id)
                            guard sessionArchiveScope == scope, isConnected, !Task.isCancelled else { break }
                            frontier.append(contentsOf: nested.filter { $0.parentID == child.id })
                        } else if !child.isArchived {
                            hasActiveDescendants = true
                        }
                    }
                    guard sessionArchiveScope == scope, isConnected, !Task.isCancelled else { break }
                    let newlyVisibleChild = sessions.contains {
                        ($0.parentID == id || $0.parentID.map(seen.contains) == true)
                            && !$0.isArchived && !approvedIDs.contains($0.id)
                    }
                    if hasActiveDescendants || newlyVisibleChild {
                        for child in discovered where !child.isArchived || !sessions.contains(where: { $0.id == child.id }) {
                            upsertSession(child)
                        }
                        result.foundMoreChildren = true
                        blockAncestors(of: id)
                        continue
                    }
                    let updated: Session
                    do {
                        updated = try await apiClient.updateSessionArchived(sessionID: id, archived: timestamp)
                    } catch {
                        guard sessionArchiveScope == scope, !Task.isCancelled else { break }
                        if isSessionNotFoundError(error) {
                            noteConfirmedMissingSession(id, hostProfileID: scope.host.hostProfileID,
                                                        clearSelection: currentSessionID == id)
                            result.missing.insert(id)
                            continue
                        }
                        throw error
                    }
                    guard sessionArchiveScope == scope, !Task.isCancelled else { break }
                    guard updated.id == id, updated.isArchived,
                          !sessionScope.confirmedMissingSessionIDs.contains(id) else {
                        throw SessionArchiveError.unconfirmed
                    }
                    upsertSession(updated)
                }
                result.archived.insert(id)
            } catch {
                // Keep the parent visible if a descendant failed. Unrelated branches can continue.
                if result.firstError == nil { result.firstError = error }
                blockAncestors(of: id)
            }
        }
        result.remaining = plan.ids.count - result.archived.count - result.missing.count
        if sessionArchiveScope == scope { noteArchivedInPlace(result.archived) }
        return result
    }
}

enum SessionArchiveError: LocalizedError {
    case unconfirmed

    var errorDescription: String? { L10n.t(.sessionsBatchUnconfirmed) }
}
