//
//  SessionFlowTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

// MARK: - Session Filtering (Code Review 1.3)

struct SessionFilteringTests {

    @Test func shouldProcessWhenSessionMatches() {
        #expect(AppState.shouldProcessMessageEvent(eventSessionID: "s1", currentSessionID: "s1") == true)
    }

    @Test func shouldNotProcessWhenSessionMismatch() {
        #expect(AppState.shouldProcessMessageEvent(eventSessionID: "s2", currentSessionID: "s1") == false)
    }

    @Test func shouldNotProcessWhenNoCurrentSession() {
        #expect(AppState.shouldProcessMessageEvent(eventSessionID: "s1", currentSessionID: nil) == false)
    }

    @Test func shouldProcessWhenNoEventSessionIDForBackwardCompat() {
        #expect(AppState.shouldProcessMessageEvent(eventSessionID: nil, currentSessionID: "s1") == true)
    }

    @Test func shouldApplySessionScopedResultWhenRequestedStillCurrent() {
        #expect(AppState.shouldApplySessionScopedResult(requestedSessionID: "s1", currentSessionID: "s1") == true)
    }

    @Test func shouldDropSessionScopedResultWhenSessionChanged() {
        #expect(AppState.shouldApplySessionScopedResult(requestedSessionID: "s2", currentSessionID: "s1") == false)
    }
}

// MARK: - Message Pagination

struct MessagePaginationTests {

    @Test func normalizedMessageFetchLimitDefaultsToPageSize() {
        #expect(AppState.normalizedMessageFetchLimit(current: nil) == 20)
    }

    @Test func normalizedMessageFetchLimitUsesAtLeastPageSize() {
        #expect(AppState.normalizedMessageFetchLimit(current: 2) == 20)
        #expect(AppState.normalizedMessageFetchLimit(current: 24) == 24)
    }

    @Test func nextMessageFetchLimitAddsOnePage() {
        #expect(AppState.nextMessageFetchLimit(current: nil) == 40)
        #expect(AppState.nextMessageFetchLimit(current: 20) == 40)
        #expect(AppState.nextMessageFetchLimit(current: 40) == 60)
    }
}

// MARK: - Session Deletion Selection

struct SessionDeletionSelectionTests {

    @Test func keepCurrentWhenDeletingDifferentSession() {
        let sessions = [
            makeSession(id: "s1", updated: 3),
            makeSession(id: "s2", updated: 2),
            makeSession(id: "s3", updated: 1),
        ]

        let next = AppState.nextSessionIDAfterDeleting(
            deletedSessionID: "s2",
            currentSessionID: "s1",
            remainingSessions: sessions.filter { $0.id != "s2" }
        )

        #expect(next == "s1")
    }

    @Test func pickMostRecentlyUpdatedWhenDeletingCurrentSession() {
        let sessions = [
            makeSession(id: "older", updated: 10),
            makeSession(id: "newer", updated: 30),
            makeSession(id: "middle", updated: 20),
        ]

        let next = AppState.nextSessionIDAfterDeleting(
            deletedSessionID: "older",
            currentSessionID: "older",
            remainingSessions: sessions.filter { $0.id != "older" }
        )

        #expect(next == "newer")
    }

    @Test func clearCurrentWhenDeletingLastSession() {
        let next = AppState.nextSessionIDAfterDeleting(
            deletedSessionID: "only",
            currentSessionID: "only",
            remainingSessions: []
        )

        #expect(next == nil)
    }

    private func makeSession(id: String, updated: Int) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: id,
            version: "1",
            time: .init(created: 0, updated: updated, archived: nil),
            share: nil,
            summary: nil
        )
    }
}

struct PermissionControllerTests {

    @Test func mapPendingRequests() {
        let req = APIClient.PermissionRequest(
            id: "p1",
            sessionID: "s1",
            permission: "run_terminal_cmd",
            patterns: ["src/**"],
            metadata: nil,
            always: ["always"],
            tool: nil
        )

        let mapped = PermissionController.fromPendingRequests([req])
        #expect(mapped.count == 1)
        #expect(mapped[0].id == "s1/p1")
        #expect(mapped[0].allowAlways == true)
        #expect(mapped[0].patterns == ["src/**"])
    }

    @Test func parseAskedEventWithNestedRequest() {
        let props: [String: AnyCodable] = [
            "request": AnyCodable([
                "sessionID": "s1",
                "permissionID": "perm1",
                "permission": "run_terminal_cmd",
                "tool": "bash",
                "patterns": ["src/**"],
                "always": true,
                "description": "Run command",
            ]),
        ]

        let parsed = PermissionController.parseAskedEvent(properties: props)
        #expect(parsed?.sessionID == "s1")
        #expect(parsed?.permissionID == "perm1")
        #expect(parsed?.tool == "bash")
        #expect(parsed?.allowAlways == true)
        #expect(parsed?.description == "Run command")
    }

    @Test func parseAskedEventWithFallbackFields() {
        let props: [String: AnyCodable] = [
            "sessionID": AnyCodable("s2"),
            "id": AnyCodable("perm2"),
            "permission": AnyCodable("edit_file"),
            "tool": AnyCodable(["name": "edit"]),
        ]

        let parsed = PermissionController.parseAskedEvent(properties: props)
        #expect(parsed?.id == "s2/perm2")
        #expect(parsed?.tool == "edit")
        #expect(parsed?.description == "edit")
    }

    @Test func applyRepliedEventRemovesOnlyTargetPermission() {
        var list: [PendingPermission] = [
            .init(sessionID: "s1", permissionID: "p1", permission: nil, patterns: [], allowAlways: false, tool: nil, description: "a"),
            .init(sessionID: "s1", permissionID: "p2", permission: nil, patterns: [], allowAlways: false, tool: nil, description: "b"),
        ]
        PermissionController.applyRepliedEvent(
            properties: [
                "sessionID": AnyCodable("s1"),
                "permissionID": AnyCodable("p1"),
            ],
            to: &list
        )
        #expect(list.count == 1)
        #expect(list[0].permissionID == "p2")
    }
}

struct ActivityTrackerTests {

    @Test func thinkingTopicFromLeadingBoldText() {
        let text = "**Refactor Session Runtime**\nThen continue details"
        #expect(ActivityTracker.formatThinkingFromReasoningText(text) == "\(L10n.t(.activityThinking)) - Refactor Session Runtime")
    }

    @Test func toolStatusMappingWithReason() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"edit","callID":"c1","state":{"status":"running","title":"Update AppState"},"metadata":null,"files":null}
        """
        let part = try JSONDecoder().decode(Part.self, from: Data(json.utf8))
        #expect(ActivityTracker.formatStatusFromPart(part) == "\(L10n.t(.activityMakingEdits)) - Update AppState")
    }

    @Test func debounceDelayWithinWindow() {
        let now = Date(timeIntervalSince1970: 200)
        let last = Date(timeIntervalSince1970: 198)
        let delay = ActivityTracker.debounceDelay(lastChangeAt: last, now: now)
        #expect(delay == 0.5)
    }

    @Test func debounceDelayOutsideWindow() {
        let now = Date(timeIntervalSince1970: 200)
        let last = Date(timeIntervalSince1970: 190)
        let delay = ActivityTracker.debounceDelay(lastChangeAt: last, now: now)
        #expect(delay == 0)
    }

    @Test func updateSessionActivityBusyToCompletedUsesCompletedTimestamp() {
        let user = makeMessage(id: "u1", sessionID: "s1", role: "user", created: 100_000, completed: nil)
        let assistant = makeMessage(id: "a1", sessionID: "s1", role: "assistant", created: 110_000, completed: 130_000)
        let rows = [
            MessageWithParts(info: user, parts: []),
            MessageWithParts(info: assistant, parts: []),
        ]

        let running = SessionActivity(
            sessionID: "s1",
            state: .running,
            text: "Thinking",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            anchorMessageID: nil
        )

        let previous = SessionStatus(type: "busy", attempt: 1, message: "Thinking", next: nil)
        let current = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)
        let updated = ActivityTracker.updateSessionActivity(
            sessionID: "s1",
            previous: previous,
            current: current,
            existing: running,
            messages: rows,
            currentSessionID: "s1",
            now: Date(timeIntervalSince1970: 999)
        )

        #expect(updated?.state == .completed)
        #expect(updated?.endedAt?.timeIntervalSince1970 == 130)
        #expect(updated?.anchorMessageID == "a1")
    }

    @Test func bestActivityTextPrefersStatusMessage() {
        let statuses = ["s1": SessionStatus(type: "busy", attempt: 1, message: "Running formatter", next: nil)]
        let text = ActivityTracker.bestSessionActivityText(
            sessionID: "s1",
            currentSessionID: "s1",
            sessionStatuses: statuses,
            messages: [],
            streamingReasoningPart: nil,
            streamingPartTexts: [:]
        )
        #expect(text == "Running formatter")
    }

    @Test func updateSessionActivityKeepsRunningWhenStatusIdleButToolStillRunning() throws {
        let user = makeMessage(id: "u1", sessionID: "s1", role: "user", created: 100_000, completed: nil)
        let assistant = makeMessage(id: "a1", sessionID: "s1", role: "assistant", created: 110_000, completed: nil)
        let partJson = """
        {"id":"p1","messageID":"a1","sessionID":"s1","type":"tool","text":null,"tool":"bash","callID":"c1","state":{"status":"running"},"metadata":null,"files":null}
        """
        let runningPart = try JSONDecoder().decode(Part.self, from: Data(partJson.utf8))
        let rows = [
            MessageWithParts(info: user, parts: []),
            MessageWithParts(info: assistant, parts: [runningPart]),
        ]

        let running = SessionActivity(
            sessionID: "s1",
            state: .running,
            text: "Running commands",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            anchorMessageID: nil
        )

        let previous = SessionStatus(type: "busy", attempt: 1, message: "Running commands", next: nil)
        let current = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)
        let updated = ActivityTracker.updateSessionActivity(
            sessionID: "s1",
            previous: previous,
            current: current,
            existing: running,
            messages: rows,
            currentSessionID: "s1"
        )

        #expect(updated?.state == .running)
        #expect(updated?.endedAt == nil)
    }

    private func makeMessage(id: String, sessionID: String, role: String, created: Int, completed: Int?) -> Message {
        Message(
            id: id,
            sessionID: sessionID,
            role: role,
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: created, completed: completed),
            finish: nil,
            tokens: nil,
            cost: nil
        )
    }
}

@Suite(.serialized)
struct ModelSelectionPersistenceTests {
    private let selectedModelDefaultsKey = "selectedModelBySession"

    @MainActor
    private func makeState(selectedModels: [String: String] = [:], seedShortlist: Bool = false) -> AppState {
        let defaults = UserDefaults(suiteName: "opencode.tests.modelsel.\(UUID().uuidString)")!
        if !selectedModels.isEmpty, let encoded = try? JSONEncoder().encode(selectedModels) {
            defaults.set(encoded, forKey: selectedModelDefaultsKey)
        }
        let state = AppState(userDefaults: defaults)
        if seedShortlist {
            state.addModelsToShortlist(state.modelPresets)
        }
        return state
    }

    @Test @MainActor func legacyGLMSelectionMapsToCurrentGLM53Preset() {
        for legacyID in ["zai-coding-plan/glm-5.1", "zai-coding-plan/glm-5.2", "zai-coding-plan/glm-5-turbo"] {
                let sessionID = "session-glm"
                let state = makeState(selectedModels: [sessionID: legacyID], seedShortlist: true)
                let session = Session(
                    id: sessionID,
                    slug: sessionID,
                    projectID: "p1",
                    directory: "/tmp",
                    parentID: nil,
                    title: sessionID,
                    version: "1",
                    time: .init(created: 0, updated: 100, archived: nil),
                    share: nil,
                    summary: nil
                )

                state.selectSession(session)

                #expect(state.selectedModelIndex == 0)
                #expect(state.modelPresets[state.selectedModelIndex].displayName == "GLM-5.3")
                #expect(state.modelPresets[state.selectedModelIndex].id == "zai-coding-plan/glm-5.3")
        }
    }

    @Test @MainActor func legacyGPTSelectionMapsToCurrentGPT56SolPreset() {
        let sessionID = "session-gpt"
        for legacyID in ["openai/gpt-5.4", "openai/gpt-5.5", "openai/gpt-5.6-sol-pro", "openai/gpt-5.6-sol-fast"] {
            let state = makeState(selectedModels: [sessionID: legacyID], seedShortlist: true)
            let session = Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: sessionID,
                version: "1",
                time: .init(created: 0, updated: 100, archived: nil),
                share: nil,
                summary: nil
            )

            state.selectSession(session)

            #expect(state.selectedModelIndex == 1)
            #expect(state.modelPresets[state.selectedModelIndex].displayName == "GPT-5.6 Sol")
            #expect(state.modelPresets[state.selectedModelIndex].id == "openai/gpt-5.6-sol")
        }
    }

    @Test @MainActor func legacyKimiSelectionMapsToCurrentOllamaGLMPreset() {
        let sessionID = "session-glm-ollama"
        let state = makeState(selectedModels: [sessionID: "ollama-cloud/kimi-k2.6"], seedShortlist: true)
        let session = Session(
            id: sessionID,
            slug: sessionID,
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: sessionID,
            version: "1",
            time: .init(created: 0, updated: 100, archived: nil),
            share: nil,
            summary: nil
        )

        state.selectSession(session)

        #expect(state.modelPresets[state.selectedModelIndex].displayName == "Ollama GLM 5.2")
        #expect(state.modelPresets[state.selectedModelIndex].id == "ollama-cloud/glm-5.2")
    }

    @Test @MainActor func defaultSelectionUsesGemini37Flash() {
        let state = makeState()

        #expect(state.selectedModelIndex == 2)
        #expect(state.modelPresets[state.selectedModelIndex].displayName == "Gemini 3.7 Flash")
        #expect(state.modelPresets[state.selectedModelIndex].id == "google/gemini-3.7-flash")
    }

    @Test @MainActor func defaultPresetsIncludeDeepSeekLocal() {
        let state = makeState()

        #expect(state.modelPresets.contains(where: { $0.id == "ds4/deepseek-v4-flash" }))
        let preset = state.modelPresets.first(where: { $0.id == "ds4/deepseek-v4-flash" })
        #expect(preset?.displayName == "DeepSeek Local")
    }

    @Test @MainActor func defaultPresetsExcludeRemovedGPTVariants() {
        let state = makeState()

        #expect(!state.modelPresets.contains(where: { $0.id == "openai/gpt-5.6-sol-pro" }))
        #expect(!state.modelPresets.contains(where: { $0.id == "openai/gpt-5.6-sol-fast" }))
        #expect(state.modelPresets.contains(where: {
            $0.id == "openai/gpt-5.6-terra-fast" && $0.displayName == "GPT-5.6 Terra Fast"
        }))
        #expect(state.modelPresets.contains(where: {
            $0.id == "openai/gpt-5.6-luna" && $0.displayName == "GPT-5.6 Luna"
        }))
        #expect(state.modelPresets.contains(where: {
            $0.id == "xai/grok-4.6" && $0.displayName == "Grok 4.6"
        }))
        #expect(state.modelPresets.last?.id == "qwen38/qwen3.8-27b")
        #expect(state.modelPresets.last?.displayName == "Qwen 3.8 27B")
    }
}

struct ArchivedSessionTests {
    @Test func sessionDecodingWithArchived() throws {
        let json = """
        {"id":"s1","slug":"s1","projectID":"p1","directory":"/tmp","parentID":null,"title":"Test","version":"1","time":{"created":1000,"updated":2000,"archived":1500},"share":null,"summary":null}
        """
        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(Session.self, from: data)
        #expect(session.time.archived == 1500)
    }

    @Test @MainActor func sortedSessionsIncludesArchivedSessions() {
        let state = AppState()

        let s1 = makeSession(id: "s1", archived: nil)
        let s2 = makeSession(id: "s2", archived: 123)
        state.sessions = [s1, s2]

        #expect(state.sortedSessions.map(\.id) == ["s1", "s2"])
    }

    @Test @MainActor func activeAndArchivedSessionFiltersUseArchivedTimestampSign() {
        let state = AppState()
        state.sessions = [
            makeSession(id: "active", title: "Active", archived: nil),
            makeSession(id: "restored", title: "Restored", archived: -1),
            makeSession(id: "archived", title: "Archived", archived: 123),
        ]

        #expect(state.filteredSessions(archived: false).map(\.id) == ["active", "restored"])
        #expect(state.filteredSessions(archived: true).map(\.id) == ["archived"])
    }

    @Test @MainActor func archiveAndRestoreSessionPatchArchivedTimestamp() async throws {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.sessions = [makeSession(id: "s1", title: "Session", archived: nil)]

        try await state.archiveSession(sessionID: "s1")
        var calls = await apiClient.updateSessionArchivedCalls
        #expect(calls.count == 1)
        #expect(calls[0].0 == "s1")
        #expect(calls[0].1 > 0)
        #expect(state.filteredSessions(archived: true).map(\.id) == ["s1"])

        try await state.restoreSession(sessionID: "s1")
        calls = await apiClient.updateSessionArchivedCalls
        #expect(calls.count == 2)
        #expect(calls[1].0 == "s1")
        #expect(calls[1].1 == -1)
        #expect(state.filteredSessions(archived: false).map(\.id) == ["s1"])
    }

    @Test @MainActor func archiveParentSessionArchivesChildrenRecursively() async throws {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.sessions = [
            makeSession(id: "parent", title: "Parent", archived: nil),
            makeSession(id: "child-a", title: "Child A", parentID: "parent", archived: nil),
            makeSession(id: "child-b", title: "Child B", parentID: "parent", archived: nil),
        ]

        try await state.archiveSession(sessionID: "parent")

        let calls = await apiClient.updateSessionArchivedCalls
        #expect(Set(calls.map(\.0)) == Set(["parent", "child-a", "child-b"]))
        #expect(calls.last?.0 == "parent")
        #expect(calls.allSatisfy { $0.1 > 0 })
        #expect(state.filteredSessions(archived: false).isEmpty)
        #expect(Set(state.filteredSessions(archived: true).map(\.id)) == Set(["parent", "child-a", "child-b"]))
    }

    @Test @MainActor func restoreParentSessionRestoresParentBeforeChildren() async throws {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.sessions = [
            makeSession(id: "parent", title: "Parent", archived: 123),
            makeSession(id: "child-a", title: "Child A", parentID: "parent", archived: 123),
            makeSession(id: "child-b", title: "Child B", parentID: "parent", archived: 123),
        ]

        try await state.restoreSession(sessionID: "parent")

        let calls = await apiClient.updateSessionArchivedCalls
        #expect(Set(calls.map(\.0)) == Set(["parent", "child-a", "child-b"]))
        #expect(calls.first?.0 == "parent")
        #expect(calls.allSatisfy { $0.1 == -1 })
    }

    @Test @MainActor func sendingArchivedSessionRestoresBeforePrompt() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        state.sessions = [makeSession(id: "s1", title: "Archived", archived: 123)]

        let success = await state.sendMessage("continue")

        #expect(success)
        let archiveCalls = await apiClient.updateSessionArchivedCalls
        #expect(archiveCalls.count == 1)
        #expect(archiveCalls[0].0 == "s1")
        #expect(archiveCalls[0].1 == -1)
        #expect(await apiClient.promptAsyncCalls.map(\.0) == ["s1"])
        #expect(state.filteredSessions(archived: false).map(\.id) == ["s1"])
    }

    private func makeSession(id: String, title: String = "Title", parentID: String? = nil, archived: Int?) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/tmp",
            parentID: parentID,
            title: title,
            version: "1",
            time: .init(created: 0, updated: 0, archived: archived),
            share: nil,
            summary: nil
        )
    }
}

struct ProjectSelectionTests {
    @Test @MainActor func effectiveProjectDirectoryNilWhenNotSelected() {
        let state = AppState()
        state.selectedProjectWorktree = nil
        #expect(state.effectiveProjectDirectory == nil)
    }

    @Test @MainActor func effectiveProjectDirectoryReturnsSelectedWorktree() {
        let state = AppState()
        state.selectedProjectWorktree = "/Users/me/co/knowledge_working"
        #expect(state.effectiveProjectDirectory == "/Users/me/co/knowledge_working")
    }

    @Test @MainActor func effectiveProjectDirectoryCustomPathWhenCustomSelected() {
        let state = AppState()
        state.selectedProjectWorktree = AppState.customProjectSentinel
        state.customProjectPath = "/Users/me/custom/project"
        #expect(state.effectiveProjectDirectory == "/Users/me/custom/project")
    }

    @Test @MainActor func effectiveProjectDirectoryNilWhenCustomSelectedButEmpty() {
        let state = AppState()
        state.selectedProjectWorktree = AppState.customProjectSentinel
        state.customProjectPath = ""
        #expect(state.effectiveProjectDirectory == nil)
    }
}

// MARK: - Fork Session Tests

struct ForkSessionTests {

    private static func makeSession(id: String, parentID: String? = nil, updated: Int = 1) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/tmp",
            parentID: parentID,
            title: id,
            version: "1",
            time: .init(created: 0, updated: updated, archived: nil),
            share: nil,
            summary: nil
        )
    }

    @Test @MainActor func forkSessionCallsAPIAndSwitchesToNewSession() async {
        let apiClient = MockAPIClient()
        let forked = Self.makeSession(id: "forked-s1", parentID: "s1", updated: 99)
        await apiClient.setForkSessionResult(forked)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [Self.makeSession(id: "s1", updated: 10)]
        state.currentSessionID = "s1"

        await state.forkSession(messageID: "msg-42")

        let calls = await apiClient.forkSessionCalls
        #expect(calls.count == 1)
        #expect(calls[0].0 == "s1")
        #expect(calls[0].1 == "msg-42")
        #expect(state.sessions.first?.id == "forked-s1")
        #expect(state.currentSessionID == "forked-s1")
    }

    @Test @MainActor func forkSessionWithNilMessageIDCallsAPIWithNil() async {
        let apiClient = MockAPIClient()
        let forked = Self.makeSession(id: "forked-s2", parentID: "s2", updated: 50)
        await apiClient.setForkSessionResult(forked)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [Self.makeSession(id: "s2", updated: 5)]
        state.currentSessionID = "s2"

        await state.forkSession(messageID: nil)

        let calls = await apiClient.forkSessionCalls
        #expect(calls.count == 1)
        #expect(calls[0].1 == nil)
        #expect(state.currentSessionID == "forked-s2")
    }

    @Test @MainActor func forkSessionCollapsesExistingSessionWithSameID() async {
        let apiClient = MockAPIClient()
        let forked = Self.makeSession(id: "forked-s1", parentID: "s1", updated: 99)
        await apiClient.setForkSessionResult(forked)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [
            Self.makeSession(id: "forked-s1", parentID: "s1", updated: 50),
            Self.makeSession(id: "s1", updated: 10)
        ]
        state.currentSessionID = "s1"

        await state.forkSession(messageID: "msg-42")

        #expect(state.sessions.map(\.id) == ["forked-s1", "s1"])
        #expect(state.currentSessionID == "forked-s1")
    }

    @Test @MainActor func forkSessionDoesNothingWhenNotConnected() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = false
        state.currentSessionID = "s1"

        await state.forkSession(messageID: "msg-1")

        let calls = await apiClient.forkSessionCalls
        #expect(calls.isEmpty)
    }

    @Test @MainActor func forkSessionDoesNothingWhenNoCurrentSession() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.currentSessionID = nil

        await state.forkSession(messageID: "msg-1")

        let calls = await apiClient.forkSessionCalls
        #expect(calls.isEmpty)
    }

    @Test @MainActor func forkSessionSetsConnectionErrorOnFailure() async {
        let apiClient = MockAPIClient()
        await apiClient.setForkSessionError(APIError.httpError(statusCode: 500, data: Data()))
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [Self.makeSession(id: "s1", updated: 1)]
        state.currentSessionID = "s1"

        await state.forkSession(messageID: "msg-1")

        #expect(state.currentSessionID == "s1")
        #expect(state.connectionError != nil)
    }
}

// MARK: - Session Tree Tests

struct SessionTreeTests {

    private func makeSession(id: String, parentID: String? = nil, updated: Int, archived: Int? = nil) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/tmp",
            parentID: parentID,
            title: id,
            version: "1",
            time: .init(created: 0, updated: updated, archived: archived),
            share: nil,
            summary: nil
        )
    }

    @Test func sessionTreeBuildsHierarchy() {
        let sessions = [
            makeSession(id: "parent", updated: 100),
            makeSession(id: "child1", parentID: "parent", updated: 90),
            makeSession(id: "child2", parentID: "parent", updated: 80),
        ]
        let tree = AppState.buildSessionTree(from: sessions)
        #expect(tree.count == 1)
        #expect(tree[0].session.id == "parent")
        #expect(tree[0].children.count == 2)
        #expect(tree[0].children[0].session.id == "child1")
        #expect(tree[0].children[1].session.id == "child2")
    }

    @Test func sessionTreeOrphanedChildrenBecomeRoots() {
        let sessions = [
            makeSession(id: "root1", updated: 100),
            makeSession(id: "orphan", parentID: "missing-parent", updated: 90),
        ]
        let tree = AppState.buildSessionTree(from: sessions)
        #expect(tree.count == 2)
    }

    @Test func sessionTreeSortsRootsByUpdatedDesc() {
        let sessions = [
            makeSession(id: "older", updated: 50),
            makeSession(id: "newer", updated: 100),
            makeSession(id: "middle", updated: 75),
        ]
        let tree = AppState.buildSessionTree(from: sessions)
        #expect(tree.count == 3)
        #expect(tree[0].session.id == "newer")
        #expect(tree[1].session.id == "middle")
        #expect(tree[2].session.id == "older")
    }

    @Test func sessionTreeMultiLevel() {
        let sessions = [
            makeSession(id: "root", updated: 100),
            makeSession(id: "child", parentID: "root", updated: 90),
            makeSession(id: "grandchild", parentID: "child", updated: 80),
        ]
        let tree = AppState.buildSessionTree(from: sessions)
        #expect(tree.count == 1)
        #expect(tree[0].children.count == 1)
        #expect(tree[0].children[0].children.count == 1)
        #expect(tree[0].children[0].children[0].session.id == "grandchild")
    }

    @Test func sessionTreeEmptyInput() {
        let tree = AppState.buildSessionTree(from: [])
        #expect(tree.isEmpty)
    }

    @Test func attentionCountsRollUpThroughAllAncestors() {
        let sessions = [
            makeSession(id: "root", updated: 100),
            makeSession(id: "child", parentID: "root", updated: 90),
            makeSession(id: "grandchild", parentID: "child", updated: 80),
        ]

        let counts = AppState.attentionCountsBySession(
            sessions: sessions,
            attentionSessionIDs: ["grandchild", "grandchild"]
        )

        #expect(counts["grandchild"] == 2)
        #expect(counts["child"] == 2)
        #expect(counts["root"] == 2)
    }

    @Test func attentionSessionsSortAheadOfNewerSessions() {
        let sessions = [
            makeSession(id: "newer", updated: 200),
            makeSession(id: "attention", updated: 100),
        ]
        let tree = AppState.buildSessionTree(from: sessions)

        let prioritized = AppState.prioritizeAttention(
            tree,
            attentionCounts: ["attention": 1]
        )

        #expect(prioritized.map(\.id) == ["attention", "newer"])
    }

    @Test func sessionTreeExcludesArchivedWhenFiltered() {
        let sessions = [
            makeSession(id: "active", updated: 100),
            makeSession(id: "archived", updated: 90, archived: 1000),
        ]
        let filtered = sessions.filter { $0.time.archived == nil }
        let tree = AppState.buildSessionTree(from: filtered)
        #expect(tree.count == 1)
        #expect(tree[0].session.id == "active")
    }

    @Test @MainActor func sidebarSessionsHideChildrenAndSortRootsByUpdatedDesc() {
        let state = AppState()
        state.sessions = [
            makeSession(id: "root-old", updated: 50),
            makeSession(id: "child", parentID: "root-new", updated: 120),
            makeSession(id: "root-new", updated: 100),
        ]

        #expect(state.sidebarSessions.map(\.id) == ["root-new", "root-old"])
    }

    @Test @MainActor func sessionTreeRemainsCanonicalListWhenSidebarSessionsHideChildren() {
        let state = AppState()
        state.sessions = [
            makeSession(id: "root", updated: 100),
            makeSession(id: "child", parentID: "root", updated: 90),
            makeSession(id: "grandchild", parentID: "child", updated: 80),
            makeSession(id: "other-root", updated: 70),
        ]

        #expect(state.sidebarSessions.map(\.id) == ["root", "other-root"])
        #expect(state.sessionTree.count == 2)
        #expect(state.sessionTree[0].session.id == "root")
        #expect(state.sessionTree[0].children.count == 1)
        #expect(state.sessionTree[0].children[0].session.id == "child")
        #expect(state.sessionTree[0].children[0].children.count == 1)
        #expect(state.sessionTree[0].children[0].children[0].session.id == "grandchild")
    }

    @Test @MainActor func sessionTreeIncludesActiveAndArchivedSessions() {
        let state = AppState()
        state.sessions = [
            makeSession(id: "active-root", updated: 100),
            makeSession(id: "active-child", parentID: "active-root", updated: 90),
            makeSession(id: "archived-root", updated: 80, archived: 1_000),
            makeSession(id: "archived-child", parentID: "active-root", updated: 70, archived: 2_000),
        ]

        #expect(state.sidebarSessions.map(\.id) == ["active-root", "archived-root"])
        #expect(state.sessionTree.count == 2)
        #expect(state.sessionTree[0].session.id == "active-root")
        #expect(state.sessionTree[0].children.map(\.session.id) == ["active-child", "archived-child"])
        #expect(state.filteredSessions(archived: false).map(\.id) == ["active-root", "active-child"])
        #expect(state.filteredSessions(archived: true).map(\.id) == ["archived-root", "archived-child"])
    }

    @Test @MainActor func toggleSessionExpandedAddsAndRemovesSessionID() {
        let state = AppState()
        #expect(state.expandedSessionIDs.isEmpty)
        state.toggleSessionExpanded("s1")
        #expect(state.expandedSessionIDs.contains("s1"))
        state.toggleSessionExpanded("s1")
        #expect(state.expandedSessionIDs.contains("s1") == false)
    }
}

struct QuestionControllerTests {

    @Test func parseAskedEvent() {
        let props: [String: AnyCodable] = [
            "id": AnyCodable("question_1"),
            "sessionID": AnyCodable("s1"),
            "questions": AnyCodable([
                [
                    "question": "Which framework?",
                    "header": "Framework",
                    "options": [
                        ["label": "SwiftUI", "description": "Native iOS"],
                        ["label": "UIKit", "description": "Classic iOS"],
                    ],
                ] as [String: Any],
            ]),
        ]
        let parsed = QuestionController.parseAskedEvent(properties: props)
        #expect(parsed?.id == "question_1")
        #expect(parsed?.sessionID == "s1")
        #expect(parsed?.questions.count == 1)
        #expect(parsed?.questions.first?.options.count == 2)
    }

    @Test func parseAskedEventReturnsNilForInvalid() {
        let props: [String: AnyCodable] = [
            "sessionID": AnyCodable("s1"),
        ]
        let parsed = QuestionController.parseAskedEvent(properties: props)
        #expect(parsed == nil)
    }

    @Test func applyResolvedEventRemovesQuestion() {
        var questions: [QuestionRequest] = []
        let json = """
        {"id":"q1","sessionID":"s1","questions":[{"question":"Q","header":"H","options":[]}]}
        """
        if let req = try? JSONDecoder().decode(QuestionRequest.self, from: Data(json.utf8)) {
            questions.append(req)
        }
        #expect(questions.count == 1)

        QuestionController.applyResolvedEvent(
            properties: ["requestID": AnyCodable("q1")],
            to: &questions
        )
        #expect(questions.isEmpty)
    }

    @Test func applyResolvedEventIgnoresUnknownID() {
        var questions: [QuestionRequest] = []
        let json = """
        {"id":"q1","sessionID":"s1","questions":[{"question":"Q","header":"H","options":[]}]}
        """
        if let req = try? JSONDecoder().decode(QuestionRequest.self, from: Data(json.utf8)) {
            questions.append(req)
        }
        QuestionController.applyResolvedEvent(
            properties: ["requestID": AnyCodable("q_unknown")],
            to: &questions
        )
        #expect(questions.count == 1)
    }
}

struct AppStateFlowTests {
    @Test @MainActor func loadFileTreePreservesExpandedChildrenCache() async {
        let apiClient = MockAPIClient()
        let root = [FileNode(name: "src", path: "src", absolute: nil, type: "directory", ignored: false)]
        let children = [FileNode(name: "main.swift", path: "src/main.swift", absolute: nil, type: "file", ignored: false)]
        await apiClient.setFileListResult(root, forPath: "")

        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.expandedPaths = ["src"]
        state.fileChildrenCache = ["src": children]

        await state.loadFileTree()

        #expect(state.fileTreeRoot.map(\.path) == ["src"])
        #expect(state.isFileExpanded("src"))
        #expect(state.cachedChildren(for: "src")?.map(\.path) == ["src/main.swift"])
    }

    @Test @MainActor func loadFileTreeUsesSelectedProjectDirectory() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.selectedProjectWorktree = "/tmp/target"

        await state.loadFileTree()
        _ = await state.loadFileChildren(path: "src")

        let requests = await apiClient.fileListRequests
        #expect(requests.count == 2)
        #expect(requests[0].path == "")
        #expect(requests[0].directory == "/tmp/target")
        #expect(requests[1].path == "src")
        #expect(requests[1].directory == "/tmp/target")
    }

    @Test @MainActor func testConnectionConfiguresInjectedClient() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.configure(serverURL: "https://example.com:4096", username: "alice", password: "secret")

        await state.testConnection()

        #expect(state.isConnected == true)
        #expect(state.serverVersion == "test-version")
        #expect(await apiClient.configuredBaseURL == "https://example.com:4096")
        #expect(await apiClient.configuredUsername == "alice")
        #expect(await apiClient.configuredPassword == "secret")
    }

    @Test @MainActor func testConnectionReportsHealthFailure() async {
        let apiClient = MockAPIClient()
        await apiClient.setHealthError(APIError.invalidURL)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.configure(serverURL: "127.0.0.1:4096")

        await state.testConnection()

        #expect(state.isConnected == false)
        #expect(state.connectionError?.isEmpty == false)
    }

    @Test @MainActor func loadFileContentUsesDirectoryQueryForExternalHostPath() async throws {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.sessions = [
            Self.makeSession(id: "s1", updated: 1, directory: "/Users/grapeot/co/knowledge_working")
        ]
        state.currentSessionID = "s1"

        _ = try await state.loadFileContent(
            path: "Users/grapeot/co/vatic/agentic_trading/docs/slides_260617/outline.md"
        )

        #expect(await apiClient.fileContentRequests.map { $0.path } == ["outline.md"])
        #expect(await apiClient.fileContentRequests.map { $0.directory } == [
            "/Users/grapeot/co/vatic/agentic_trading/docs/slides_260617"
        ])
    }

    @Test @MainActor func loadSessionsSelectsFirstSessionWhenNeeded() async {
        let apiClient = MockAPIClient()
        await apiClient.setSessionsResult([
            Self.makeSession(id: "s-new", updated: 20),
            Self.makeSession(id: "s-old", updated: 10),
        ])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.currentSessionID = nil

        await state.loadSessions()

        #expect(state.sessions.count == 2)
        #expect(state.currentSessionID == "s-new")
    }

    @Test @MainActor func loadMoreSessionsRequestsLargerLimitAndKeepsOnlyRootSidebarSessions() async {
        let apiClient = MockAPIClient()
        let firstPageChildren = (0..<399).map { index in
            Self.makeSession(id: "child-\(index)", parentID: "root-1", updated: 99 - index)
        }
        let secondPageChildren = (0..<398).map { index in
            Self.makeSession(id: "child-\(index)", parentID: "root-1", updated: 99 - index)
        }

        await apiClient.setSessionsResult([
            Self.makeSession(id: "root-1", updated: 100),
        ] + firstPageChildren, forLimit: 400)
        await apiClient.setSessionsResult([
            Self.makeSession(id: "root-2", updated: 110),
            Self.makeSession(id: "root-1", updated: 100),
        ] + secondPageChildren, forLimit: 800)

        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true

        await state.loadSessions()
        #expect(state.sidebarSessions.map(\.id) == ["root-1"])
        #expect(state.canLoadMoreSessions == true)

        await state.loadMoreSessions()

        #expect(await apiClient.sessionLimitRequests == [400, 800])
        #expect(state.sidebarSessions.map(\.id) == ["root-2", "root-1"])
        #expect(state.canLoadMoreSessions == false)
    }

    @Test @MainActor func loadMoreSessionsPreservesChildHierarchyInCanonicalSessionTree() async {
        let apiClient = MockAPIClient()
        let fillerChildren = (0..<397).map { index in
            Self.makeSession(
                id: "child-extra-\(index)",
                parentID: "root-1",
                updated: 89 - index
            )
        }
        await apiClient.setSessionsResult([
            Self.makeSession(id: "root-1", updated: 100),
            Self.makeSession(id: "child-1", parentID: "root-1", updated: 95),
            Self.makeSession(id: "grandchild-1", parentID: "child-1", updated: 90),
        ] + fillerChildren, forLimit: 400)
        await apiClient.setSessionsResult([
            Self.makeSession(id: "root-2", updated: 110),
            Self.makeSession(id: "root-1", updated: 100),
            Self.makeSession(id: "child-1", parentID: "root-1", updated: 95),
            Self.makeSession(id: "grandchild-1", parentID: "child-1", updated: 90),
        ] + fillerChildren, forLimit: 800)

        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true

        await state.loadSessions()
        #expect(state.sessionTree.map(\.session.id) == ["root-1"])
        #expect(state.sessionTree[0].children.first?.session.id == "child-1")
        let initialChildOneNode = state.sessionTree[0].children.first(where: { $0.session.id == "child-1" })
        #expect(initialChildOneNode?.children.map(\.session.id) == ["grandchild-1"])
        #expect(state.canLoadMoreSessions == true)

        await state.loadMoreSessions()

        #expect(state.sidebarSessions.map(\.id) == ["root-2", "root-1"])
        #expect(state.sessionTree.map(\.session.id) == ["root-2", "root-1"])
        let rootOneNode = state.sessionTree.first(where: { $0.session.id == "root-1" })
        #expect(rootOneNode?.children.first?.session.id == "child-1")
        let reloadedChildOneNode = rootOneNode?.children.first(where: { $0.session.id == "child-1" })
        #expect(reloadedChildOneNode?.children.map(\.session.id) == ["grandchild-1"])
    }

    @Test @MainActor func createSessionAppendsNewCurrentSession() async {
        let apiClient = MockAPIClient()
        await apiClient.setCreateSessionResult(Self.makeSession(id: "created", updated: 30))
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [Self.makeSession(id: "existing", updated: 10)]
        state.messages = [Self.makeMessageRow(messageID: "m1", sessionID: "existing", text: "old")]
        state.partsByMessage = ["m1": Self.makeMessageRow(messageID: "m1", sessionID: "existing", text: "old").parts]

        await state.createSession()

        #expect(state.currentSessionID == "created")
        #expect(state.sessions.first?.id == "created")
        #expect(state.messages.isEmpty)
        #expect(state.partsByMessage.isEmpty)
    }

    @Test @MainActor func createSessionCollapsesExistingSessionWithSameID() async {
        let apiClient = MockAPIClient()
        let created = Self.makeSession(id: "created", updated: 30, title: "Created")
        await apiClient.setCreateSessionResult(created)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [
            Self.makeSession(id: "created", updated: 20, title: "Old Created"),
            Self.makeSession(id: "existing", updated: 10)
        ]

        await state.createSession()

        #expect(state.sessions.map(\.id) == ["created", "existing"])
        #expect(state.sessions.first?.title == "Created")
        #expect(state.currentSessionID == "created")
    }

    @Test @MainActor func sendMessageKeepsOptimisticRowAndMarksSendFailureInlineOnFailure() async {
        let apiClient = MockAPIClient()
        await apiClient.setPromptError(APIError.invalidURL)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        let succeeded = await state.sendMessage("hello")

        #expect(succeeded == false)
        // Row is retained with an inline failure banner; no modal alert.
        #expect(state.messages.count == 1)
        #expect(state.messages.first?.info.isUser == true)
        #expect(state.sendError == nil)
        let failedID = state.messages.first!.info.id
        #expect(state.messageStore.failedSendReasonsByID[failedID]?.isEmpty == false)
        #expect(state.messageStore.pendingOptimisticMessageIDs.contains(failedID) == false)
    }

    @Test @MainActor func sendMessageUsesDeterministicMessageIDSharedWithServer() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        _ = await state.sendMessage("hello")

        let sentMessageIDs = await apiClient.promptAsyncMessageIDs
        #expect(sentMessageIDs.count == 1)
        #expect(sentMessageIDs[0].hasPrefix("msg_"))
        // The optimistic row carries the exact id sent to the server, so
        // reconciliation is pure id membership (no text/timestamp heuristics).
        #expect(state.messages.first?.info.id == sentMessageIDs[0])
        #expect(state.messageStore.pendingOptimisticMessageIDs == Set(sentMessageIDs))
    }

    @Test @MainActor func loadMessagesStoresFetchedRowsAndParts() async {
        let apiClient = MockAPIClient()
        let loaded = [Self.makeMessageRow(messageID: "m1", sessionID: "s1", text: "hi")]
        await apiClient.setMessagesResult(loaded)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.loadMessages()

        #expect(state.messages.count == 1)
        #expect(state.partsByMessage["m1"]?.count == 1)
        #expect(state.partsByMessage["m1"]?.first?.text == "hi")
    }

    @Test @MainActor func appendOptimisticUserMessageIncludesImageAttachmentPart() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        let attachment = Self.makeAttachment(filename: "photo.jpg")

        let tempMessageID = state.appendOptimisticUserMessage("look", attachments: [attachment])

        let parts = state.partsByMessage[tempMessageID] ?? []
        #expect(parts.map(\.type) == ["text", "file"])
        #expect(parts.last?.mime == "image/jpeg")
        #expect(parts.last?.filename == "photo.jpg")
        #expect(parts.last?.url == attachment.dataURL)
    }

    @Test @MainActor func sendMessagePassesImageAttachmentsToAPI() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        let attachment = Self.makeAttachment(filename: "photo.jpg")

        let success = await state.sendMessage("look", attachments: [attachment])

        #expect(success)
        let calls = await apiClient.promptAsyncCalls
        #expect(calls.count == 1)
        #expect(calls[0].0 == "s1")
        #expect(calls[0].1 == "look")
        #expect(calls[0].2 == [attachment])
    }

    @Test func visibleMessagesHidesRowsAtAndAfterRevertMessageID() {
        let rows = [
            Self.makeMessageRow(messageID: "msg-1", sessionID: "s1", role: "user", text: "first"),
            Self.makeMessageRow(messageID: "msg-2", sessionID: "s1", role: "assistant", text: "reply"),
            Self.makeMessageRow(messageID: "msg-3", sessionID: "s1", role: "user", text: "edit me"),
            Self.makeMessageRow(messageID: "msg-4", sessionID: "s1", role: "assistant", text: "old reply"),
        ]

        let visible = AppState.visibleMessages(rows, revertMessageID: "msg-3")

        #expect(visible.map(\.info.id) == ["msg-1", "msg-2"])
    }

    @Test @MainActor func editFromMessageCallsRevertAndStoresDraft() async {
        let apiClient = MockAPIClient()
        var reverted = Self.makeSession(id: "s1", updated: 20)
        reverted.revert = .init(messageID: "msg-3", partID: nil, snapshot: nil, diff: nil)
        await apiClient.setRevertSessionResult(reverted)
        await apiClient.setMessagesResult([
            Self.makeMessageRow(messageID: "msg-1", sessionID: "s1", role: "user", text: "first"),
            Self.makeMessageRow(messageID: "msg-2", sessionID: "s1", role: "assistant", text: "reply"),
        ])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [Self.makeSession(id: "s1", updated: 10)]
        state.currentSessionID = "s1"
        state.messages = [
            Self.makeMessageRow(messageID: "msg-1", sessionID: "s1", role: "user", text: "first"),
            Self.makeMessageRow(messageID: "msg-2", sessionID: "s1", role: "assistant", text: "reply"),
            Self.makeMessageRow(messageID: "msg-3", sessionID: "s1", role: "user", text: "edit me"),
        ]

        let draft = await state.editFromMessage(messageID: "msg-3")

        #expect(draft == "edit me")
        #expect(state.draftText(for: "s1") == "edit me")
        #expect(state.currentSession?.revert?.messageID == "msg-3")
        #expect(state.messages.map(\.info.id) == ["msg-1", "msg-2"])
        #expect(await apiClient.revertSessionCalls.count == 1)
        #expect(await apiClient.revertSessionCalls.first?.0 == "s1")
        #expect(await apiClient.revertSessionCalls.first?.1 == "msg-3")
        #expect(await apiClient.messagesCallCount == 1)
    }

    @Test @MainActor func editFromMessageKeepsDraftUnchangedOnFailure() async {
        let apiClient = MockAPIClient()
        await apiClient.setRevertSessionError(APIError.invalidURL)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.sessions = [Self.makeSession(id: "s1", updated: 10)]
        state.currentSessionID = "s1"
        state.setDraftText("existing draft", for: "s1")
        state.messages = [
            Self.makeMessageRow(messageID: "msg-3", sessionID: "s1", role: "user", text: "edit me"),
        ]

        let draft = await state.editFromMessage(messageID: "msg-3")

        #expect(draft == nil)
        #expect(state.draftText(for: "s1") == "existing draft")
        #expect(state.currentSession?.revert == nil)
        #expect(state.sendError != nil)
    }

    @Test @MainActor func loadOlderMessagesIncreasesLimitAndAppliesLargerWindow() async {
        let apiClient = MockAPIClient()
        let firstPage = (0..<20).map { index in
            Self.makeMessageRow(messageID: "m\(index)", sessionID: "s1", text: "message \(index)")
        }
        let expandedPage = (0..<40).map { index in
            Self.makeMessageRow(messageID: "m\(index)", sessionID: "s1", text: "message \(index)")
        }
        await apiClient.setMessagesResult(firstPage, forLimit: 20)
        await apiClient.setMessagesResult(expandedPage, forLimit: 40)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.loadMessages()
        let didLoadOlder = await state.loadOlderMessagesForCurrentSession()

        #expect(didLoadOlder == true)
        #expect(await apiClient.messageLimitRequests == [20, 40])
        #expect(state.messages.count == 40)
        #expect(state.loadedMessageLimitBySessionID["s1"] == 40)
        #expect(state.hasMoreHistoryBySessionID["s1"] == true)
    }

    @Test @MainActor func loadOlderMessagesSkipsWhenInitialWindowIsNotFull() async {
        let apiClient = MockAPIClient()
        let firstPage = (0..<10).map { index in
            Self.makeMessageRow(messageID: "m\(index)", sessionID: "s1", text: "message \(index)")
        }
        await apiClient.setMessagesResult(firstPage, forLimit: 20)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.loadMessages()
        let didLoadOlder = await state.loadOlderMessagesForCurrentSession()

        #expect(didLoadOlder == false)
        #expect(await apiClient.messageLimitRequests == [20])
        #expect(state.messages.count == 10)
        #expect(state.hasMoreHistoryBySessionID["s1"] == false)
    }

    @Test @MainActor func loadMessagesReplacesOptimisticRowWhenServerConfirmsSameMessageID() async {
        let apiClient = MockAPIClient()
        let now = Int(Date().timeIntervalSince1970 * 1000)
        await apiClient.setMessagesResult([
            Self.makeMessageRow(
                messageID: "msg_shared",
                sessionID: "s1",
                role: "user",
                text: "[analyze-mode]\nANALYSIS MODE. Gather context.\n---\nhello world",
                created: now,
                completed: now
            ),
            Self.makeMessageRow(messageID: "m-assistant", sessionID: "s1", text: "reply")
        ])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        // Server-side text rewrites (plugin prefixes, whitespace) are
        // irrelevant: the optimistic row sent msg_shared and the server
        // persisted it under the same id.
        _ = state.appendOptimisticUserMessage("hello world", messageID: "msg_shared")
        await state.loadMessages()

        #expect(state.messages.map(\.info.id) == ["msg_shared", "m-assistant"])
        #expect(state.messageStore.pendingOptimisticMessageIDs.isEmpty)
        #expect(state.partsByMessage["msg_shared"]?.first?.text?.contains("analyze-mode") == true)
    }

    @Test @MainActor func loadMessagesKeepsOptimisticRowUntilServerRowArrives() async {
        let apiClient = MockAPIClient()
        await apiClient.setMessagesResult([
            Self.makeMessageRow(messageID: "m-assistant", sessionID: "s1", text: "older reply")
        ])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        // Idle session: with deterministic ids the pending row survives until
        // its id shows up server-side, regardless of session busy state.
        state.sessionStatuses["s1"] = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)

        _ = state.appendOptimisticUserMessage("still in flight", messageID: "msg_pending")
        await state.loadMessages()

        #expect(state.messages.map(\.info.id) == ["m-assistant", "msg_pending"])
        #expect(state.messageStore.pendingOptimisticMessageIDs == ["msg_pending"])
    }

    @Test @MainActor func sessionErrorMarksPendingOptimisticRowAsFailedInline() async {
        let apiClient = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: apiClient)
        state.currentSessionID = "s1"

        let pendingID = state.appendOptimisticUserMessage("hello", messageID: "msg_pending")

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.error","properties":{"sessionID":"s1","error":{"name":"UnknownError","data":{"message":"Error: boom\\nCaused by: stack trace line 2"}}}}}
        """))

        // Inline banner under the row; reason is the first meaningful line,
        // prefixed with the error name. No modal alert, no row removal.
        #expect(state.messageStore.failedSendReasonsByID[pendingID] == "UnknownError: Error: boom")
        #expect(state.messageStore.pendingOptimisticMessageIDs.isEmpty)
        #expect(state.messages.contains(where: { $0.info.id == pendingID }))
        #expect(state.sendError == nil)
        #expect(await apiClient.messagesCallCount == 1)
    }

    @Test @MainActor func sessionErrorIgnoresOtherSessions() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        let pendingID = state.appendOptimisticUserMessage("hello", messageID: "msg_pending")

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.error","properties":{"sessionID":"s2","error":{"name":"UnknownError","data":{"message":"boom"}}}}}
        """))

        #expect(state.messageStore.failedSendReasonsByID[pendingID] == nil)
        #expect(state.messageStore.pendingOptimisticMessageIDs == [pendingID])
        #expect(await apiClient.messagesCallCount == 0)
    }

    @Test @MainActor func sessionErrorWithoutPendingRowStillReloads() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.error","properties":{"sessionID":"s1","error":{"name":"APIError","data":{"message":"provider down"}}}}}
        """))

        // No optimistic row to mark; the reload surfaces assistant-row errors.
        #expect(state.messageStore.failedSendReasonsByID.isEmpty)
        #expect(await apiClient.messagesCallCount == 1)
    }

    @Test @MainActor func sessionErrorReasonFallsBackWhenUndecodable() async {
        let props: [String: AnyCodable] = ["error": AnyCodable("not an object")]
        let reason = AppState.sessionErrorDisplayReason(properties: props)
        #expect(reason == L10n.t(.errorOperationFailed))
    }

    @Test @MainActor func messageUpdatedIgnoresOtherSession() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        state.streamingPartTexts = ["m1:p1": "partial"]

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s2","messageID":"m2"}}}
        """))

        #expect(state.streamingPartTexts["m1:p1"] == "partial")
        #expect(await apiClient.messagesCallCount == 0)
        #expect(await apiClient.sessionDiffCallCount == 0)
    }

    @Test @MainActor func messageUpdatedForCurrentSessionClearsStreamingAndReloads() async {
        let apiClient = MockAPIClient()
        await apiClient.setMessagesResult([Self.makeMessageRow(messageID: "m1", sessionID: "s1", text: "Final")])
        await apiClient.setSessionDiffResult([Self.makeDiff(file: "Sources/MessageStore.swift")])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        state.streamingPartTexts = ["m1:p1": "partial"]
        state.streamingReasoningPart = Self.makeReasoningPart(messageID: "m1", partID: "p-reasoning", sessionID: "s1")

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","messageID":"m1"}}}
        """))

        #expect(state.streamingPartTexts.isEmpty)
        #expect(state.streamingReasoningPart == nil)
        #expect(state.messages.count == 1)
        #expect(state.messages.first?.parts.first?.text == "Final")
        #expect(state.sessionDiffs == [Self.makeDiff(file: "Sources/MessageStore.swift")])
        #expect(await apiClient.messagesCallCount == 1)
        #expect(await apiClient.sessionDiffCallCount == 1)
    }

    @Test @MainActor func sessionUpdatedSkipsProjectMismatchForNonCurrentSession() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.selectedProjectWorktree = "/project/a"
        state.currentSessionID = "s-current"
        state.sessions = [Self.makeSession(id: "s-current", updated: 10, directory: "/project/a", title: "Current")]

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.updated","properties":{"session":{"id":"s-other","slug":"s-other","projectID":"p1","directory":"/project/b","parentID":null,"title":"Other","version":"1","time":{"created":0,"updated":20},"share":null,"summary":null}}}}
        """))

        #expect(state.sessions.count == 1)
        #expect(state.sessions.first?.id == "s-current")
        #expect(state.sessions.first?.title == "Current")
    }

    @Test @MainActor func sessionUpdatedUsesServerDefaultProjectScope() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.selectedProjectWorktree = nil
        state.serverCurrentProjectWorktree = "/project/a"
        state.sessions = [Self.makeSession(id: "s-current", updated: 10, directory: "/project/a", title: "Current")]

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.updated","properties":{"session":{"id":"s-other","slug":"s-other","projectID":"p1","directory":"/project/b","parentID":null,"title":"Other","version":"1","time":{"created":0,"updated":20},"share":null,"summary":null}}}}
        """))

        #expect(state.sessions.map(\.id) == ["s-current"])
    }

    @Test @MainActor func sessionUpdatedDoesNotInsertUnknownProjectBeforeDefaultLoads() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.selectedProjectWorktree = nil
        state.serverCurrentProjectWorktree = nil
        state.sessions = [Self.makeSession(id: "s-known", updated: 10, directory: "/project/a", title: "Known")]

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.updated","properties":{"session":{"id":"s-other","slug":"s-other","projectID":"p1","directory":"/project/b","parentID":null,"title":"Other","version":"1","time":{"created":0,"updated":20},"share":null,"summary":null}}}}
        """))

        #expect(state.sessions.map(\.id) == ["s-known"])
    }

    @Test @MainActor func sessionUpdatedStillAppliesToCurrentSessionAcrossProjectMismatch() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.selectedProjectWorktree = "/project/a"
        state.currentSessionID = "s-current"
        state.sessions = [Self.makeSession(id: "s-current", updated: 10, directory: "/project/a", title: "Old Title")]

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.updated","properties":{"session":{"id":"s-current","slug":"s-current","projectID":"p1","directory":"/project/b","parentID":null,"title":"New Title","version":"1","time":{"created":0,"updated":30},"share":null,"summary":null}}}}
        """))

        #expect(state.sessions.count == 1)
        #expect(state.sessions.first?.id == "s-current")
        #expect(state.sessions.first?.title == "New Title")
        #expect(state.sessions.first?.directory == "/project/b")
    }

    @Test @MainActor func sessionUpdatedCollapsesDuplicateSessionEntries() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.selectedProjectWorktree = nil
        state.currentSessionID = "s-current"
        state.sessions = [
            Self.makeSession(id: "s-current", updated: 10, title: "First"),
            Self.makeSession(id: "s-current", updated: 9, title: "Duplicate"),
            Self.makeSession(id: "s-other", updated: 8, title: "Other")
        ]

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.updated","properties":{"session":{"id":"s-current","slug":"s-current","projectID":"p1","directory":"/tmp","parentID":null,"title":"Fresh","version":"2","time":{"created":0,"updated":30},"share":null,"summary":null}}}}
        """))

        #expect(state.sessions.map(\.id) == ["s-current", "s-other"])
        #expect(state.sessions.first?.title == "Fresh")
        #expect(state.sessions.first?.version == "2")
    }

    @Test @MainActor func sessionUpdatedNoOpsWhenPayloadIsUnchanged() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        let current = Self.makeSession(id: "s-current", updated: 10, title: "Current")
        state.sessions = [
            current,
            Self.makeSession(id: "s-other", updated: 8, title: "Other")
        ]

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.updated","properties":{"session":{"id":"s-current","slug":"s-current","projectID":"p1","directory":"/tmp","parentID":null,"title":"Current","version":"1","time":{"created":0,"updated":10},"share":null,"summary":null}}}}
        """))

        #expect(state.sessions == [current, Self.makeSession(id: "s-other", updated: 8, title: "Other")])
    }

    @Test @MainActor func messagePartUpdatedAccumulatesStreamingMessageText() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","delta":"Hello","part":{"id":"p1","messageID":"m1","sessionID":"s1","type":"text"}}}}
        """))
        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","delta":" world","part":{"id":"p1","messageID":"m1","sessionID":"s1","type":"text"}}}}
        """))

        #expect(state.streamingPartTexts["m1:p1"] == "Hello world")
        #expect(state.messages.count == 1)
        #expect(state.messages.first?.info.id == "m1")
        #expect(state.messages.first?.parts.first?.text == "Hello world")
        #expect(state.partsByMessage["m1"]?.first?.text == "Hello world")
    }

    @Test @MainActor func messagePartUpdatedWithoutDeltaReloadsAndClearsStreamingState() async {
        let apiClient = MockAPIClient()
        await apiClient.setMessagesResult([Self.makeMessageRow(messageID: "m1", sessionID: "s1", text: "Final")])
        await apiClient.setSessionDiffResult([Self.makeDiff(file: "Sources/AppState.swift")])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","delta":"Draft","part":{"id":"p1","messageID":"m1","sessionID":"s1","type":"text"}}}}
        """))
        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","part":{"id":"p1","messageID":"m1","sessionID":"s1","type":"text"}}}}
        """))

        #expect(state.streamingPartTexts["m1:p1"] == nil)
        #expect(state.messages.count == 1)
        #expect(state.messages.first?.parts.first?.text == "Final")
        #expect(state.sessionDiffs == [Self.makeDiff(file: "Sources/AppState.swift")])
        #expect(await apiClient.messagesCallCount == 1)
        #expect(await apiClient.sessionDiffCallCount == 1)
    }

    @Test @MainActor func messagePartUpdatedIgnoresNonCurrentSession() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s2","delta":"ignored","part":{"id":"p1","messageID":"m2","sessionID":"s2","type":"text"}}}}
        """))

        #expect(state.streamingPartTexts.isEmpty)
        #expect(state.messages.isEmpty)
        #expect(await apiClient.messagesCallCount == 0)
        #expect(await apiClient.sessionDiffCallCount == 0)
    }

    @Test @MainActor func sessionStatusIdleClearsStreamingStateForCurrentSession() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","delta":"thinking","part":{"id":"p-reasoning","messageID":"m1","sessionID":"s1","type":"reasoning"}}}}
        """))
        #expect(state.streamingReasoningPart?.messageID == "m1")

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"session.status","properties":{"sessionID":"s1","status":{"type":"idle","attempt":null,"message":null,"next":null}}}}
        """))

        #expect(state.sessionStatuses["s1"]?.type == "idle")
        #expect(state.streamingReasoningPart == nil)
        #expect(state.streamingPartTexts.isEmpty)
    }

    @Test @MainActor func deleteCurrentSessionSelectsNextMostRecentSession() async throws {
        let apiClient = MockAPIClient()
        await apiClient.setMessagesResult([Self.makeMessageRow(messageID: "m-next", sessionID: "next", text: "next")])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.sessions = [
            Self.makeSession(id: "current", updated: 10),
            Self.makeSession(id: "next", updated: 20),
        ]
        state.currentSessionID = "current"

        try await state.deleteSession(sessionID: "current")

        #expect(state.currentSessionID == "next")
        #expect(state.sessions.count == 1)
        #expect(state.sessions.first?.id == "next")
        #expect(await apiClient.deletedSessionIDs == ["current"])
    }

    private static func makeSession(id: String, parentID: String? = nil, updated: Int, directory: String = "/tmp", title: String? = nil) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: directory,
            parentID: parentID,
            title: title ?? id,
            version: "1",
            time: .init(created: 0, updated: updated, archived: nil),
            share: nil,
            summary: nil
        )
    }

    private static func makeDiff(file: String) -> FileDiff {
        FileDiff(file: file, before: "", after: "+change", additions: 1, deletions: 0, status: "M")
    }

    private static func makeReasoningPart(messageID: String, partID: String, sessionID: String) -> Part {
        Part(
            id: partID,
            messageID: messageID,
            sessionID: sessionID,
            type: "reasoning",
            text: nil,
            tool: nil,
            callID: nil,
            state: nil,
            metadata: nil,
            files: nil
        )
    }

    private static func makeSSEEvent(_ json: String) -> SSEEvent {
        try! JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8))
    }

    private static func makeMessageRow(
        messageID: String,
        sessionID: String,
        role: String = "assistant",
        text: String,
        created: Int = 0,
        completed: Int = 1
    ) -> MessageWithParts {
        let message = Message(
            id: messageID,
            sessionID: sessionID,
            role: role,
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: created, completed: completed),
            finish: "stop",
            tokens: nil,
            cost: nil
        )
        let part = Part(
            id: "p-\(messageID)",
            messageID: messageID,
            sessionID: sessionID,
            type: "text",
            text: text,
            tool: nil,
            callID: nil,
            state: nil,
            metadata: nil,
            files: nil
        )
        return MessageWithParts(info: message, parts: [part])
    }

    private static func makeAttachment(filename: String) -> ComposerImageAttachment {
        ComposerImageAttachment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            filename: filename,
            mime: "image/jpeg",
            dataURL: "data:image/jpeg;base64,AAA",
            thumbnailData: Data([0x01, 0x02]),
            byteSize: 3
        )
    }
}
