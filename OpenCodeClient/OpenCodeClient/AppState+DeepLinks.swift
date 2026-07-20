import Foundation

enum DeepLinkRouteState: Equatable {
    case idle
    case pending(OpenCodeDeepLink)
    case resolving(OpenCodeDeepLink)
}

extension AppState {
    func receiveDeepLink(_ url: URL) {
        switch OpenCodeDeepLinkParser.parse(url) {
        case .success(.clientActionReturn(let callback)):
            deepLinkError = nil
            Task { await receiveClientActionCallback(callback) }
        case .success(let deepLink):
            deepLinkError = nil
            pendingDeepLink = deepLink
            deepLinkRouteState = .pending(deepLink)
            Task { await processPendingDeepLinkIfPossible() }
        case .failure:
            deepLinkRouteID = UUID()
            pendingDeepLink = nil
            deepLinkRouteState = .idle
            deepLinkError = L10n.t(.deepLinkInvalid)
        }
    }

    func invalidateDeepLinkRoute(keepPending: Bool) {
        deepLinkRouteID = UUID()
        if keepPending, let pendingDeepLink {
            deepLinkRouteState = .pending(pendingDeepLink)
        } else {
            pendingDeepLink = nil
            deepLinkRouteState = .idle
        }
    }

    func processPendingDeepLinkIfPossible() async {
        guard isConnected, let deepLink = pendingDeepLink else { return }

        let routeID = UUID()
        deepLinkRouteID = routeID
        deepLinkRouteState = .resolving(deepLink)

        do {
            switch deepLink {
            case .session(let sessionID):
                let session: Session
                if let deepLinkSessionResolver {
                    session = try await deepLinkSessionResolver(sessionID)
                } else {
                    session = try await apiClient.session(sessionID: sessionID)
                }
                guard deepLinkRouteID == routeID, pendingDeepLink == deepLink else { return }

                pendingDeepLink = nil
                applyProjectDirectory(for: session)
                upsertSession(session)
                selectedTab = RootTab.chat.rawValue

                if currentSessionID == session.id {
                    deepLinkRouteState = .idle
                    return
                }

                if deepLinkHydratesSelection {
                    selectSession(session)
                    Task { await loadFileTree() }
                } else {
                    currentSessionID = session.id
                }
                deepLinkRouteState = .idle
            case .clientActionReturn:
                pendingDeepLink = nil
                deepLinkRouteState = .idle
            }
        } catch {
            guard deepLinkRouteID == routeID, pendingDeepLink == deepLink else { return }
            pendingDeepLink = nil
            deepLinkRouteState = .idle
            if case APIError.httpError(let statusCode, _) = error, statusCode == 404 {
                deepLinkError = L10n.t(.deepLinkSessionUnavailable)
            } else {
                deepLinkError = L10n.t(.deepLinkOpenFailed)
            }
        }
    }

    private func applyProjectDirectory(for session: Session) {
        if session.directory == serverCurrentProjectWorktree {
            selectedProjectWorktree = nil
            return
        }

        if projects.contains(where: { $0.worktree == session.directory }) {
            selectedProjectWorktree = session.directory
            return
        }

        customProjectPath = session.directory
        selectedProjectWorktree = Self.customProjectSentinel
    }
}
