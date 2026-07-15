import Foundation
import Testing
@testable import OpenCodeClient

struct OpenCodeDeepLinkParserTests {
    @Test func parsesSessionLink() throws {
        let url = try #require(URL(string: "opencode://session/ses_example-123"))
        #expect(OpenCodeDeepLinkParser.parse(url) == .success(.session(id: "ses_example-123")))
    }

    @Test func normalizesSchemeAndHostCase() throws {
        let url = try #require(URL(string: "OPENCODE://SESSION/ses_ABC"))
        #expect(OpenCodeDeepLinkParser.parse(url) == .success(.session(id: "ses_ABC")))
    }

    @Test func acceptsSinglePercentDecoding() throws {
        let url = try #require(URL(string: "opencode://session/ses_%65xample"))
        #expect(OpenCodeDeepLinkParser.parse(url) == .success(.session(id: "ses_example")))
    }

    @Test func rejectsUnsupportedOrMalformedLinks() throws {
        let values = [
            "https://session/ses_example",
            "opencode://other/ses_example",
            "opencode://session",
            "opencode://session/ses_example/",
            "opencode://session/ses_one/extra",
            "opencode://user@session/ses_example",
            "opencode://session:4096/ses_example",
            "opencode://session/ses_",
            "opencode://session/not_a_session",
            "opencode://session/ses_example?message=msg_1",
            "opencode://session/ses_example#fragment",
            "opencode://session/ses_%252e%252e",
        ]

        for value in values {
            let url = try #require(URL(string: value))
            guard case .failure = OpenCodeDeepLinkParser.parse(url) else {
                Issue.record("Expected malformed link to fail: \(value)")
                continue
            }
        }
    }

    @Test func rejectsOverlongSessionID() throws {
        let url = try #require(URL(string: "opencode://session/ses_\(String(repeating: "a", count: 300))"))
        guard case .failure = OpenCodeDeepLinkParser.parse(url) else {
            Issue.record("Expected overlong session ID to fail")
            return
        }
    }
}

struct OpenCodeDeepLinkRoutingTests {
    @Test @MainActor func opensVerifiedSessionAndSwitchesProject() async throws {
        let api = MockAPIClient()
        let target = makeSession(id: "ses_target", directory: "/tmp/target")
        await api.setSessionResult(target)
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.currentSessionID = "ses_source"
        state.pendingDeepLink = .session(id: target.id)
        state.deepLinkRouteState = .pending(.session(id: target.id))

        await state.processPendingDeepLinkIfPossible()

        #expect(state.currentSessionID == target.id)
        #expect(state.selectedTab == RootTab.chat.rawValue)
        #expect(state.selectedProjectWorktree == AppState.customProjectSentinel)
        #expect(state.customProjectPath == target.directory)
        #expect(state.sessions.contains(where: { $0.id == target.id }))
        #expect(await api.sessionRequests == [target.id])
        #expect(state.pendingDeepLink == nil)
        #expect(state.deepLinkError == nil)
    }

    @Test @MainActor func serverDefaultDirectoryClearsProjectSelection() async {
        let api = MockAPIClient()
        let target = makeSession(id: "ses_default", directory: "/tmp/default")
        await api.setSessionResult(target)
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.serverCurrentProjectWorktree = target.directory
        state.selectedProjectWorktree = "/tmp/old"
        state.pendingDeepLink = .session(id: target.id)

        await state.processPendingDeepLinkIfPossible()

        #expect(state.selectedProjectWorktree == nil)
        #expect(state.currentSessionID == target.id)
    }

    @Test @MainActor func disconnectedRouteStaysPending() async {
        let api = MockAPIClient()
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = false
        state.pendingDeepLink = .session(id: "ses_later")

        await state.processPendingDeepLinkIfPossible()

        #expect(state.pendingDeepLink == .session(id: "ses_later"))
        #expect(await api.sessionRequests.isEmpty)
    }

    @Test @MainActor func notFoundPreservesCurrentSession() async {
        let api = MockAPIClient()
        await api.setSessionError(APIError.httpError(statusCode: 404, data: Data()))
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.currentSessionID = "ses_source"
        state.pendingDeepLink = .session(id: "ses_missing")

        await state.processPendingDeepLinkIfPossible()

        #expect(state.currentSessionID == "ses_source")
        #expect(state.pendingDeepLink == nil)
        #expect(state.deepLinkError == L10n.t(.deepLinkSessionUnavailable))
    }

    @Test @MainActor func invalidLinkDoesNotChangeSession() throws {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "ses_source"
        let url = try #require(URL(string: "opencode://session/not-valid"))

        state.receiveDeepLink(url)

        #expect(state.currentSessionID == "ses_source")
        #expect(state.pendingDeepLink == nil)
        #expect(state.deepLinkError == L10n.t(.deepLinkInvalid))
    }

    @Test @MainActor func invalidLinkCancelsOlderPendingRoute() throws {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.pendingDeepLink = .session(id: "ses_older")
        state.deepLinkRouteState = .pending(.session(id: "ses_older"))
        let previousRouteID = state.deepLinkRouteID
        let url = try #require(URL(string: "opencode://session/not-valid"))

        state.receiveDeepLink(url)

        #expect(state.pendingDeepLink == nil)
        #expect(state.deepLinkRouteState == .idle)
        #expect(state.deepLinkRouteID != previousRouteID)
    }

    @Test @MainActor func invalidatingInFlightRouteKeepsPendingForNewHost() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        let link = OpenCodeDeepLink.session(id: "ses_target")
        state.pendingDeepLink = link
        state.deepLinkRouteState = .resolving(link)
        let previousRouteID = state.deepLinkRouteID

        state.invalidateDeepLinkRoute(keepPending: true)

        #expect(state.pendingDeepLink == link)
        #expect(state.deepLinkRouteState == .pending(link))
        #expect(state.deepLinkRouteID != previousRouteID)
    }

    @Test @MainActor func sessionRefreshPreservesSelectedResolvedSessionOutsideWindow() async {
        let api = MockAPIClient()
        let target = makeSession(id: "ses_old_target", directory: "/tmp/target")
        let recent = makeSession(id: "ses_recent", directory: "/tmp/target")
        await api.setSessionsResult([recent])
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [target]
        state.currentSessionID = target.id

        await state.loadSessions()

        #expect(state.currentSessionID == target.id)
        #expect(state.currentSession?.id == target.id)
        #expect(Set(state.sessions.map(\.id)) == Set([target.id, recent.id]))
    }

    private func makeSession(id: String, directory: String) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: directory,
            parentID: nil,
            title: "Target Session",
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
    }
}
