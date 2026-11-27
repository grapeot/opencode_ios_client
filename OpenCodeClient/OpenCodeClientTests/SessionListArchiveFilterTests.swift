//
//  SessionListArchiveFilterTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

/// The session list asks the server for unarchived rows only and pages
/// archived subtrees on demand, falling back to the legacy window on hosts
/// without `/experimental/session`.
struct SessionListArchiveFilterTests {
    private static let worktree = "/work"

    private static func session(_ id: String, parent: String? = nil, updated: Int, archived: Int? = nil) -> Session {
        Session(id: id, slug: id, projectID: "p1", directory: worktree, parentID: parent, title: id,
                version: "1", time: .init(created: 1, updated: updated, archived: archived), share: nil, summary: nil)
    }

    @MainActor private static func makeState(_ api: MockAPIClient, worktree: String = worktree) async -> AppState {
        await api.setProjectCurrentResult(Project(id: "p1", worktree: worktree, vcs: nil, icon: nil, time: nil, sandboxes: nil))
        let state = makeIsolatedAppState(apiClient: api, sseClient: MockSSEClient())
        state.isConnected = true
        return state
    }

    /// Active rows plus archived pages keyed by cursor, on a filtering host.
    @MainActor private static func filteredState(
        active: [Session] = [],
        archived: [Int?: SessionPage] = [:],
        children: [Session] = []
    ) async -> (MockAPIClient, AppState) {
        let api = MockAPIClient()
        await api.setActiveSessionPages([nil: SessionPage(rows: active, nextCursor: nil)])
        await api.setArchivedSessionPages(archived)
        await api.setArchiveChildren(children)
        let state = await makeState(api)
        await state.loadSessions()
        return (api, state)
    }

    // MARK: Active list

    @Test @MainActor func activeListLoadsOnePageAndPagesIncrementally() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([
            nil: SessionPage(rows: [Self.session("a1", updated: 30), Self.session("a1-child", parent: "a1", updated: 29)], nextCursor: 29),
            29: SessionPage(rows: [Self.session("a2", updated: 20)], nextCursor: nil),
        ])
        await api.setSessionsResult([Self.session("legacy-archived", updated: 99, archived: 5)])
        let state = await Self.makeState(api)

        await state.loadSessions()

        #expect(Set(state.sessions.map(\.id)) == ["a1", "a1-child"])
        #expect(await api.sessionLimitRequests.isEmpty)
        #expect(state.usesServerArchiveFilter)
        #expect(state.canLoadMoreSessions)
        #expect(state.mayHaveUnloadedArchivedSessions)

        await state.loadMoreSessions()

        #expect(Set(state.sessions.map(\.id)) == ["a1", "a1-child", "a2"])
        #expect(state.canLoadMoreSessions == false)
        let requests = await api.sessionPageRequests
        // Load more follows the cursor; it does not re-download the first page.
        #expect(requests.map(\.cursor) == [nil, 29])
        #expect(requests.allSatisfy { $0.directory == Self.worktree && !$0.includeArchived && !$0.rootsOnly })
    }

    @Test @MainActor func activePagingStopsWhenTheCursorDoesNotAdvance() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([
            nil: SessionPage(rows: [Self.session("a1", updated: 30)], nextCursor: 30),
            30: SessionPage(rows: [Self.session("a1", updated: 30)], nextCursor: 30),
        ])
        let state = await Self.makeState(api)

        await state.loadSessions()
        await state.loadMoreSessions()

        #expect(state.sessions.map(\.id) == ["a1"])
        #expect(state.canLoadMoreSessions == false)
        #expect(await api.sessionPageRequests.map(\.cursor) == [nil, 30])
    }

    /// Two loaded pages: a(50) b(40) | c(30) d(20).
    @MainActor private static func twoPageState() async -> (MockAPIClient, AppState) {
        let api = MockAPIClient()
        await api.setActiveSessionPages([
            nil: SessionPage(rows: [session("a", updated: 50), session("b", updated: 40)], nextCursor: 40),
            40: SessionPage(rows: [session("c", updated: 30), session("d", updated: 20)], nextCursor: nil),
        ])
        let state = await makeState(api)
        await state.loadSessions()
        await state.loadMoreSessions()
        return (api, state)
    }

    @Test @MainActor func incrementalRefreshKeepsDeeperPagesAndDropsVanishedRows() async {
        let (api, state) = await Self.twoPageState()
        #expect(state.sessions.map(\.id) == ["a", "b", "c", "d"])
        // The first load selected "a"; a selected row is always kept, so select a deep one.
        state.currentSessionID = "d"

        // "a" was archived elsewhere; "e" is new. Only the first page is fetched again.
        await api.setActiveSessionPages([
            nil: SessionPage(rows: [Self.session("e", updated: 60), Self.session("b", updated: 40)], nextCursor: 40),
        ])
        await state.loadSessions()

        #expect(Set(state.sessions.map(\.id)) == ["e", "b", "c", "d"])
        #expect(await api.sessionPageRequests.map(\.cursor) == [nil, 40, nil])
        // The deeper page was the last one, so there is still nothing more to load.
        #expect(state.canLoadMoreSessions == false)
    }

    @Test @MainActor func incrementalRefreshKeepsTheDeepestCursor() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([
            nil: SessionPage(rows: [Self.session("a", updated: 50)], nextCursor: 50),
            50: SessionPage(rows: [Self.session("b", updated: 40)], nextCursor: 40),
            40: SessionPage(rows: [Self.session("c", updated: 30)], nextCursor: nil),
        ])
        let state = await Self.makeState(api)
        await state.loadSessions()
        await state.loadMoreSessions()

        await state.loadSessions()
        await state.loadMoreSessions()

        #expect(state.sessions.map(\.id) == ["a", "b", "c"])
        #expect(await api.sessionPageRequests.map(\.cursor) == [nil, 50, nil, 40])
    }

    @Test @MainActor func pullToRefreshDropsDeeperPages() async {
        let (api, state) = await Self.twoPageState()

        await state.refreshSessions(resetPaging: true)

        #expect(state.sessions.map(\.id) == ["a", "b"])
        #expect(state.canLoadMoreSessions)
        await state.loadMoreSessions()
        #expect(await api.sessionPageRequests.map(\.cursor) == [nil, 40, nil, 40])
    }

    @Test @MainActor func completeFirstPageDropsEveryAbsentActiveRow() async {
        let (api, state) = await Self.twoPageState()

        await api.setActiveSessionPages([nil: SessionPage(rows: [Self.session("a", updated: 50)], nextCursor: nil)])
        await state.loadSessions()

        #expect(state.sessions.map(\.id) == ["a"])
        #expect(state.canLoadMoreSessions == false)
    }

    @Test @MainActor func selectedDeepRowSurvivesPullToRefresh() async {
        let (_, state) = await Self.twoPageState()
        state.currentSessionID = "d"

        await state.loadSessions(resetPaging: true)

        #expect(state.sessions.contains { $0.id == "d" })
    }

    @Test @MainActor func defaultDirectoryPrefersServerInstanceDirectory() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([nil: SessionPage(rows: [], nextCursor: nil)])
        await api.setInstanceDirectoryResult("/work/sub")
        let state = await Self.makeState(api)

        await state.loadSessions()
        await state.loadSessions()

        #expect(await api.sessionPageRequests.map(\.directory) == ["/work/sub", "/work/sub"])
        #expect(state.defaultSessionListDirectory == "/work/sub")
    }

    @Test @MainActor func rootWorktreeKeepsLegacyWindow() async {
        // A server started outside git reports worktree "/", which no session records.
        let api = MockAPIClient()
        await api.setActiveSessionPages([nil: SessionPage(rows: [], nextCursor: nil)])
        await api.setSessionsResult([Self.session("s1", updated: 10)])
        let state = await Self.makeState(api, worktree: "/")

        await state.loadSessions()
        await state.loadSessions()

        #expect(state.sessions.map(\.id) == ["s1"])
        #expect(await api.sessionPageRequests.isEmpty)
        #expect(await api.sessionLimitRequests == [400, 400])
        // Cached as unusable, not as an unsupported host, so a chosen project can still filter.
        #expect(state.defaultSessionListDirectory == "")
        #expect(state.serverFiltersArchivedSessions == nil)
    }

    @Test @MainActor func reconnectReprobesDirectoryAndFilterSupport() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api, sseClient: MockSSEClient())
        state.configure(serverURL: "127.0.0.1:4096")
        state.defaultSessionListDirectory = "/stale"
        state.serverFiltersArchivedSessions = false

        await state.testConnection()

        #expect(state.isConnected)
        #expect(state.defaultSessionListDirectory == nil)
        #expect(state.serverFiltersArchivedSessions == nil)
    }

    @Test @MainActor func unsupportedHostKeepsLegacyWindowWithoutReprobing() async {
        let api = MockAPIClient()
        await api.setSessionsResult([Self.session("s1", updated: 10), Self.session("old", updated: 5, archived: 3)])
        let state = await Self.makeState(api)

        await state.loadSessions()
        await state.loadSessions()

        #expect(state.serverFiltersArchivedSessions == false)
        #expect(Set(state.sessions.map(\.id)) == ["s1", "old"])
        #expect(await api.sessionPageRequests.count == 1)
        #expect(await api.sessionLimitRequests == [400, 400])
        #expect(state.mayHaveUnloadedArchivedSessions == false)
    }

    @Test @MainActor func unconfirmedHostFallsBackOnProbeError() async {
        // Pre-1.2.11 servers proxy unknown paths upstream; that proxy can 5xx or time out.
        let api = MockAPIClient()
        await api.setActiveSessionPages([:])
        await api.setSessionPageError(APIError.httpError(statusCode: 502, data: Data()))
        await api.setSessionsResult([Self.session("s1", updated: 10)])
        let state = await Self.makeState(api)

        await state.loadSessions()

        #expect(state.sessions.map(\.id) == ["s1"])
        #expect(state.connectionError == nil)
        // Not recorded as unsupported, so a later load probes again.
        #expect(state.serverFiltersArchivedSessions == nil)
        await state.loadSessions()
        #expect(await api.sessionPageRequests.count == 2)
    }

    @Test @MainActor func confirmedHostSurfacesServerError() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([nil: SessionPage(rows: [Self.session("a1", updated: 50)], nextCursor: nil)])
        let state = await Self.makeState(api)
        await state.loadSessions()
        #expect(state.usesServerArchiveFilter)

        await api.setSessionPageError(APIError.httpError(statusCode: 500, data: Data()))
        await state.loadSessions()

        #expect(state.connectionError != nil)
        #expect(state.serverFiltersArchivedSessions == true)
        #expect(await api.sessionLimitRequests.isEmpty)
        #expect(state.sessions.map(\.id) == ["a1"])
    }

    @Test @MainActor func serversBefore1211SkipTheProbe() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([nil: SessionPage(rows: [], nextCursor: nil)])
        await api.setSessionsResult([Self.session("s1", updated: 10)])
        let state = await Self.makeState(api)
        state.serverVersion = "1.2.10"

        await state.loadSessions()

        #expect(await api.sessionPageRequests.isEmpty)
        #expect(await api.sessionLimitRequests == [400])
        #expect(state.serverFiltersArchivedSessions == false)
    }

    @Test func versionGateParsesReleaseStrings() {
        let probes = ["1.2.11", "v1.2.11", "1.2.12", "1.3.0", "1.19.6", "2.4.2", "local", "0.0.0-private-sync-202611271845", "0.0.0", "", nil]
        for version in probes {
            #expect(AppState.serverMayFilterArchivedSessions(version: version), "\(version ?? "nil")")
        }
        for version in ["1.2.10", "1.2.0", "1.1.9", "1.0.0", "0.15.3", "1.2", "1.2.10-beta.1"] {
            #expect(!AppState.serverMayFilterArchivedSessions(version: version), "\(version)")
        }
    }

    @Test @MainActor func knownReleaseSurfacesProbeError() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([:])
        await api.setSessionPageError(APIError.httpError(statusCode: 500, data: Data()))
        let state = await Self.makeState(api)
        state.serverVersion = "1.19.6"

        await state.loadSessions()

        #expect(state.connectionError != nil)
        #expect(await api.sessionLimitRequests.isEmpty)
    }

    @Test @MainActor func cancelledProbeDoesNotFallBack() async {
        let api = MockAPIClient()
        await api.setActiveSessionPages([:])
        await api.setSessionPageError(URLError(.cancelled))
        let state = await Self.makeState(api)

        await state.loadSessions()

        #expect(await api.sessionLimitRequests.isEmpty)
    }

    @Test func knownReleaseParsing() {
        for version in ["1.2.11", "v1.19.6", "1.2.10-beta.1", "2.4.2", "0.15.3"] {
            #expect(AppState.isKnownServerRelease(version: version), "\(version)")
        }
        for version in ["local", "0.0.0-private-sync-1", "0.0.0", "", nil] {
            #expect(!AppState.isKnownServerRelease(version: version), "\(version ?? "nil")")
        }
    }

    @Test @MainActor func legacyWindowClearsFilteredPaging() async {
        // A server at "/" lists the default directory through the legacy window
        // while a chosen project still filters.
        let api = MockAPIClient()
        await api.setActiveSessionPages([
            nil: SessionPage(rows: [Self.session("p1", updated: 20)], nextCursor: 20),
            20: SessionPage(rows: [Self.session("p2", updated: 10)], nextCursor: nil),
        ])
        await api.setSessionsResult([Self.session("legacy-1", updated: 5)])
        let state = await Self.makeState(api, worktree: "/")
        // A full legacy window, so its load more is live and must stay on the legacy path.
        state.loadedSessionLimit = 1
        state.customProjectPath = "/proj"
        state.selectedProjectWorktree = AppState.customProjectSentinel
        await state.loadSessions()
        #expect(state.usesFilteredSessionList)
        #expect(state.canLoadMoreSessions)

        state.selectedProjectWorktree = nil
        await state.loadSessions()

        // "p1" stays only because the first load selected it.
        #expect(Set(state.sessions.map(\.id)) == ["p1", "legacy-1"])
        #expect(state.usesFilteredSessionList == false)
        #expect(state.activeSessionCursor == nil)
        #expect(state.canLoadMoreSessions)
        await state.loadMoreSessions()
        #expect(await api.sessionPageRequests.map(\.cursor) == [nil])
        #expect(await api.sessionLimitRequests.count == 2)

        state.selectedProjectWorktree = AppState.customProjectSentinel
        await state.loadSessions()
        // Back on the filtered list, legacy rows are not kept as deeper pages.
        #expect(state.sessions.map(\.id) == ["p1"])
    }

    @Test @MainActor func projectSwitchResetsDeeperActivePages() async {
        let (api, state) = await Self.twoPageState()
        #expect(state.hasLoadedDeeperActivePages)

        state.customProjectPath = "/other"
        state.selectedProjectWorktree = AppState.customProjectSentinel
        await state.loadSessions()

        #expect(state.hasLoadedDeeperActivePages == false)
        #expect(state.sessions.map(\.id) == ["a", "b"])
        #expect(state.activeSessionCursor == 40)
        #expect(await api.sessionPageRequests.last?.directory == "/other")
    }

    // MARK: Archived pages

    @Test @MainActor func archivedPagesSurviveRefresh() async {
        let (api, state) = await Self.filteredState(
            active: [Self.session("a1", updated: 50)],
            archived: [
                // archived=true also returns unarchived rows; the active fetch owns those.
                nil: SessionPage(rows: [Self.session("a1", updated: 50), Self.session("r1", updated: 40, archived: 9)], nextCursor: 40),
                40: SessionPage(rows: [Self.session("r2", updated: 30, archived: 9)], nextCursor: nil),
            ]
        )

        await state.loadArchivedSessions()

        #expect(state.sessions.map(\.id) == ["a1", "r1", "r2"])
        #expect(state.canLoadMoreArchivedSessions == false)
        #expect(state.mayHaveUnloadedArchivedSessions == false)
        let archivedRequests = await api.sessionPageRequests.filter(\.includeArchived)
        // One load keeps reading until it has a page of archived tops or the cursor runs out.
        #expect(archivedRequests.map(\.cursor) == [nil, 40])
        #expect(archivedRequests.allSatisfy { !$0.rootsOnly })

        await state.loadSessions()
        #expect(Set(state.sessions.map(\.id)) == ["a1", "r1", "r2"])
        #expect(state.sessionTree(archived: true).map(\.id) == ["r1", "r2"])
    }

    @Test @MainActor func archivedChildUnderActiveParentIsReachable() async {
        let (_, state) = await Self.filteredState(
            active: [Self.session("a1", updated: 50)],
            archived: [nil: SessionPage(rows: [
                Self.session("a1", updated: 50),
                Self.session("a1-archived", parent: "a1", updated: 45, archived: 9),
                Self.session("r1", updated: 40, archived: 9),
                Self.session("r1-child", parent: "r1", updated: 39, archived: 9),
            ], nextCursor: nil)]
        )

        await state.loadArchivedSessions()

        #expect(Set(state.sessionTree(archived: true).map(\.id)) == ["a1-archived", "r1"])
        // A child under an archived parent waits for that parent to expand.
        #expect(state.sessions.contains { $0.id == "r1-child" } == false)
    }

    @Test @MainActor func rowsArchivedInPlaceLeaveMemoryOnRefresh() async {
        let (_, state) = await Self.filteredState(active: [Self.session("a1", updated: 50)])

        // A batch archive leaves its rows in memory as archived.
        state.upsertSession(Self.session("bulk-1", updated: 10, archived: 7))
        state.upsertSession(Self.session("bulk-2", parent: "bulk-1", updated: 9, archived: 7))
        await state.loadSessions()

        #expect(state.sessions.map(\.id) == ["a1"])
    }

    @Test @MainActor func archivingKeepsRowsInsideTheLoadedArchivedWindow() async {
        // Four one-row server pages leave more to load, so the window ends at updated 37.
        let (api, state) = await Self.filteredState(
            active: [Self.session("recent", updated: 50), Self.session("stale", updated: 10)],
            archived: [
                nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: 40),
                40: SessionPage(rows: [Self.session("r2", updated: 39, archived: 9)], nextCursor: 39),
                39: SessionPage(rows: [Self.session("r3", updated: 38, archived: 9)], nextCursor: 38),
                38: SessionPage(rows: [Self.session("r4", updated: 37, archived: 9)], nextCursor: 37),
            ]
        )
        await state.loadArchivedSessions()
        #expect(state.canLoadMoreArchivedSessions)
        state.upsertSession(Self.session("recent", updated: 50, archived: 9))
        state.upsertSession(Self.session("stale", updated: 10, archived: 9))

        state.noteArchivedInPlace(["recent", "stale"])
        await api.setActiveSessionPages([nil: SessionPage(rows: [], nextCursor: nil)])
        await state.loadSessions()

        #expect(state.sessions.contains { $0.id == "recent" && $0.isArchived })
        // Older than the loaded window: it returns once the user pages that far.
        #expect(state.sessions.contains { $0.id == "stale" } == false)
        #expect(await api.sessionPageRequests.filter(\.includeArchived).count == 4)
    }

    @Test @MainActor func archivingDoesNotWaitOnArchivedReload() async {
        let (api, state) = await Self.filteredState(
            active: [Self.session("a1", updated: 50)],
            archived: [nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: nil)]
        )
        await state.loadArchivedSessions()

        try? await state.archiveSession(sessionID: "a1")
        await api.setActiveSessionPages([nil: SessionPage(rows: [], nextCursor: nil)])
        await state.loadSessions()

        #expect(state.sessions.contains { $0.id == "a1" && $0.isArchived })
        #expect(await api.sessionPageRequests.filter(\.includeArchived).count == 1)
    }

    @Test @MainActor func droppedArchivedRowDoesNotReturnOnRecovery() async {
        let (_, state) = await Self.filteredState(
            archived: [nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: nil)]
        )
        await state.loadArchivedSessions()
        #expect(state.sessions.map(\.id) == ["r1"])

        let fetched = AppState.SessionListFetch(rows: [], hasMore: false, filteredDirectory: Self.worktree)
        state.applySessionListFetch(fetched, capturedSelection: nil, droppedSessionID: "r1")

        #expect(state.sessions.isEmpty)
    }

    @Test @MainActor func archivedLoadingIsScopedToItsDirectory() async {
        let state = makeIsolatedAppState(apiClient: MockAPIClient(), sseClient: MockSSEClient())
        state.archivedSessionDirectory = "/a"
        state.archivedLoadingDirectory = "/a"
        #expect(state.isLoadingArchivedSessions)

        state.archivedSessionDirectory = "/b"
        #expect(state.isLoadingArchivedSessions == false)
    }

    // MARK: Children and restore

    @Test @MainActor func archivedChildrenLoadOnceWhenExpanded() async throws {
        let (_, state) = await Self.filteredState(
            archived: [nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: nil)],
            children: [Self.session("r1-child", parent: "r1", updated: 39, archived: 9)]
        )
        await state.loadArchivedSessions()

        let root = try #require(state.sessions.first { $0.id == "r1" })
        #expect(state.mayHaveUnloadedChildren(root))
        await state.loadArchivedChildren(of: "r1")
        await state.loadArchivedChildren(of: "r1")

        #expect(state.mayHaveUnloadedChildren(root) == false)
        #expect(state.sessions.filter { $0.id == "r1-child" }.count == 1)
        #expect(state.sessionTree(archived: true).first?.children.map(\.id) == ["r1-child"])

        // Paged-in children are archived rows the user loaded, so they survive a refresh.
        await state.loadSessions()
        #expect(Set(state.sessions.map(\.id)) == ["r1", "r1-child"])
    }

    @Test @MainActor func resetReloadsChildrenOfExpandedRows() async {
        let (_, state) = await Self.filteredState(
            archived: [nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: nil)],
            children: [Self.session("r1-child", parent: "r1", updated: 39, archived: 9)]
        )
        await state.loadArchivedSessions()
        await state.loadArchivedChildren(of: "r1")
        state.expandedSessionIDs.insert("r1")

        await state.loadArchivedSessions(reset: true)

        #expect(Set(state.sessions.map(\.id)) == ["r1", "r1-child"])
    }

    @Test @MainActor func restoreFetchesArchivedDescendantsFirst() async throws {
        let (api, state) = await Self.filteredState(
            archived: [nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: nil)],
            children: [
                Self.session("r1-child", parent: "r1", updated: 39, archived: 9),
                Self.session("r1-grandchild", parent: "r1-child", updated: 38, archived: 9),
            ]
        )
        await state.loadArchivedSessions()
        // A stale expand cache must not stop the walk at the root.
        state.archivedChildrenLoadedIDs.insert("r1")

        try await state.restoreSession(sessionID: "r1")

        #expect(await api.updateSessionArchivedCalls.map(\.0) == ["r1", "r1-child", "r1-grandchild"])
    }

    @Test @MainActor func restoreFailsWhenDescendantsCannotBeRead() async {
        let (api, state) = await Self.filteredState(
            archived: [nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: nil)]
        )
        await state.loadArchivedSessions()
        await api.setSessionChildrenError(URLError(.networkConnectionLost))

        await #expect(throws: (any Error).self) { try await state.restoreSession(sessionID: "r1") }
        #expect(await api.updateSessionArchivedCalls.isEmpty)
    }

    @Test @MainActor func projectSwitchResetsArchivedPages() async {
        let (api, state) = await Self.filteredState(
            archived: [nil: SessionPage(rows: [Self.session("r1", updated: 40, archived: 9)], nextCursor: nil)]
        )
        await state.loadArchivedSessions()
        #expect(state.sessions.map(\.id) == ["r1"])

        state.customProjectPath = "/other"
        state.selectedProjectWorktree = AppState.customProjectSentinel
        await state.loadSessions()

        #expect(state.sessions.isEmpty)
        #expect(state.archivedSessionDirectory == "/other")
        #expect(state.hasLoadedArchivedSessions == false)
        #expect(await api.sessionPageRequests.last?.directory == "/other")
    }
}
