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
    var remaining = 0
}

extension AppState {
    var sessionArchiveScope: SessionArchiveScope {
        .init(host: captureHostRequestSnapshot(), directory: effectiveProjectDirectory)
    }

    func archiveSessions(_ plan: SessionArchivePlan, in scope: SessionArchiveScope) async -> SessionArchiveOutcome {
        var result = SessionArchiveOutcome()
        var blockedAncestors = Set<String>()
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)

        for id in plan.ids {
            guard sessionArchiveScope == scope, isConnected, !Task.isCancelled else { break }
            guard !blockedAncestors.contains(id) else { continue }
            do {
                if !sessions.contains(where: { $0.id == id && $0.isArchived }) {
                    let updated = try await apiClient.updateSessionArchived(sessionID: id, archived: timestamp)
                    guard sessionArchiveScope == scope else { break }
                    guard updated.id == id, updated.isArchived,
                          !sessionScope.confirmedMissingSessionIDs.contains(id) else {
                        throw SessionArchiveError.unconfirmed
                    }
                    upsertSession(updated)
                }
                result.archived.insert(id)
            } catch {
                // Keep the parent visible if a descendant failed. Unrelated branches can continue.
                var ancestor = plan.parentByID[id]
                while let parent = ancestor, blockedAncestors.insert(parent).inserted {
                    ancestor = plan.parentByID[parent]
                }
            }
        }
        result.remaining = plan.ids.count - result.archived.count
        return result
    }
}

private enum SessionArchiveError: Error { case unconfirmed }
