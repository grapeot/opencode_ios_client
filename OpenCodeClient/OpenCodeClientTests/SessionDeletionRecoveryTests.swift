import Foundation
import Testing
@testable import OpenCodeClient

struct SessionDeletionRecoveryTests {
    private let notFound = APIError.httpError(statusCode: 404, data: Data())

    @Test @MainActor func continuous404RecoveryIsBounded() async {
        let api = SessionRecoveryAPIClient()
        await api.setSessionsResult([makeSession(id: "gone", updated: 20), makeSession(id: "other", updated: 10)])
        await api.setMessagesError(notFound)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.sessions = [makeSession(id: "gone", updated: 20), makeSession(id: "other", updated: 10)]
        state.currentSessionID = "gone"
        state.setDraftText("stay", for: "gone")

        await state.loadMessages()
        await state.loadMessages()

        #expect(await api.messagesCallCount == 2)
        #expect(await api.messageSessionIDs == ["gone", "other"])
        #expect(await api.sessionsCallCount == 1)
        #expect(state.currentSessionID == nil)
        #expect(state.sessions.map(\.id) == ["other"])
        #expect(state.sessionScope.confirmedMissingSessionIDs.isEmpty)
        #expect(state.draftText(for: "gone") == "stay")
        #expect(persistedDraft(defaults, "gone") == "stay")

        await api.setMessagesError(nil)
        await api.setMessages([makeMessage(id: "m-gone", sessionID: "gone", role: "user", text: "back")], forSession: "gone")
        await api.setSessionsResult([makeSession(id: "gone", updated: 20), makeSession(id: "other", updated: 10)])
        await state.loadSessions()

        #expect(state.sessions.map(\.id) == ["gone", "other"])
        #expect(state.currentSessionID == "gone")
        #expect(state.sessionScope.confirmedMissingSessionIDs.isEmpty)
        #expect(state.draftText(for: "gone") == "stay")
    }

    @Test @MainActor func stop404RecoveryHydratesAlternativeModelDiffAndTodos() async {
        let api = SessionRecoveryAPIClient()
        let alt = makeSession(id: "alt", updated: 30)
        let altModel = Message.ModelInfo(providerID: "anthropic", modelID: "m-b")
        await api.setSessionsResult([makeSession(id: "gone", updated: 20), alt])
        await api.setAbortError(notFound)
        await api.setMessages([
            makeMessage(id: "m-alt", sessionID: "alt", role: "assistant", text: "from-b", model: altModel),
        ], forSession: "alt")
        await api.setSessionDiff([
            FileDiff(file: "kept.swift", before: "", after: "b", additions: 1, deletions: 0, status: "added"),
        ], forSession: "alt")
        await api.setSessionTodos([
            TodoItem(content: "ship", status: "pending", priority: "high", id: "todo-b"),
        ], forSession: "alt")
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.sessions = [makeSession(id: "gone", updated: 20), alt]
        state.currentSessionID = "gone"
        state.modelShortlist = [
            ModelShortlistItem(providerID: "openai", modelID: "m-a", displayName: "M_A", shortName: "M_A"),
        ]
        state.selectedModelIndex = 0
        state.selectedModelIDBySessionID["gone"] = "openai/m-a"
        state.setDraftText("stay", for: "gone")
        #expect(state.selectedModelIDBySessionID["alt"] == nil)
        #expect(state.selectedModel?.id == "openai/m-a")

        await state.abortSession()

        #expect(state.currentSessionID == "alt")
        #expect(state.messages.map(\.info.id) == ["m-alt"])
        #expect(state.selectedModel?.id == "anthropic/m-b")
        #expect(state.selectedModelIDBySessionID["alt"] == "anthropic/m-b")
        #expect(state.sessionDiffs.map(\.file) == ["kept.swift"])
        #expect(state.currentTodos.map(\.id) == ["todo-b"])
        #expect(state.sessionScope.confirmedMissingSessionIDs.isEmpty)
        #expect(state.draftText(for: "gone") == "stay")
        #expect(await api.sessionsCallCount == 1)
        #expect(await api.messageSessionIDs == ["alt"])
        #expect(await api.sessionDiffSessionIDs == ["alt"])
        #expect(await api.sessionTodoSessionIDs == ["alt"])
    }

    @Test @MainActor func remoteDeleteWhileDisconnectedClearsSelectionWithoutRequests() async {
        let api = SessionRecoveryAPIClient()
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = false
        state.sessions = [makeSession(id: "gone", updated: 20), makeSession(id: "keep", updated: 10)]
        state.currentSessionID = "gone"

        await state.handleRemoteSessionDeleted(sessionID: "gone")

        #expect(state.currentSessionID == nil)
        #expect(state.sessions.map(\.id) == ["keep"])
        #expect(await api.messagesCallCount == 0)
        #expect(await api.sessionsCallCount == 0)
    }

    @Test @MainActor func remoteDeleteCurrentSessionSelectsRemainingSession() async throws {
        let api = SessionRecoveryAPIClient()
        let keep = makeSession(id: "keep", updated: 30)
        await api.setSessionsResult([keep])
        await api.setMessages([makeMessage(id: "m-keep", sessionID: "keep", role: "assistant", text: "kept")], forSession: "keep")
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.sessions = [makeSession(id: "gone", updated: 20), keep]
        state.currentSessionID = "gone"
        state.messages = [makeMessage(id: "m-gone", sessionID: "gone", role: "assistant", text: "gone")]

        await state.applySSEEventForTesting(try SSEEvent.sessionDeleted("gone"))

        #expect(state.currentSessionID == "keep")
        #expect(state.sessions.map(\.id) == ["keep"])
        #expect(state.messages.map(\.info.id) == ["m-keep"])
        #expect(await api.messagesCallCount == 1)
        #expect(await api.messageSessionIDs == ["keep"])
        #expect(await api.sessionsCallCount == 1)
    }

    @Test @MainActor func inFlightSessionListDoesNotReinsertDeletedSelection() async {
        let api = SessionRecoveryAPIClient()
        await api.setSuspendSessions(true)
        let keep = makeSession(id: "keep", updated: 30)
        await api.setSessionsResult([keep])
        await api.setMessages([makeMessage(id: "m-keep", sessionID: "keep", role: "assistant", text: "kept")], forSession: "keep")
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.sessions = [makeSession(id: "gone", updated: 20), keep]
        state.currentSessionID = "gone"

        let loadTask = Task { @MainActor in
            await state.loadSessions()
        }
        await api.waitUntilSessionsPending(1)
        let remoteTask = Task { @MainActor in
            await state.handleRemoteSessionDeleted(sessionID: "gone")
        }
        await api.waitUntilSessionsPending(2)
        #expect(state.currentSessionID == nil)
        #expect(!state.sessions.contains { $0.id == "gone" })

        await api.releaseNextSessionsFetch()
        await loadTask.value
        #expect(state.currentSessionID == "keep")
        #expect(state.sessions.map(\.id) == ["keep"])
        #expect(state.messages.map(\.info.id) == ["m-keep"])

        await api.releaseNextSessionsFetch()
        await remoteTask.value
        #expect(state.currentSessionID == "keep")
        #expect(state.sessions.map(\.id) == ["keep"])
        #expect(await api.sessionsCallCount == 2)
        #expect(await api.messagesCallCount == 1)
    }

    @Test @MainActor func offPageSelectionIsRetainedWhenSessionIsNotMissing() async {
        let api = SessionRecoveryAPIClient()
        let old = makeSession(id: "old", updated: 5)
        let new = makeSession(id: "new", updated: 40)
        await api.setSessionsResult([new])
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.sessions = [old, new]
        state.currentSessionID = "old"
        state.messages = [makeMessage(id: "m-old", sessionID: "old", role: "user", text: "stay")]

        await state.loadSessions()

        #expect(state.currentSessionID == "old")
        #expect(state.sessions.map(\.id) == ["old", "new"])
        #expect(state.messages.map(\.info.id) == ["m-old"])
        #expect(await api.messagesCallCount == 0)
        #expect(await api.sessionsCallCount == 1)
        #expect(state.sessionScope.confirmedMissingSessionIDs.isEmpty)
    }

    @Test @MainActor func deleteInFlightOfCurrentSessionDoesNotOverwriteNewSelection() async throws {
        let api = SessionRecoveryAPIClient()
        await api.setSuspendDeletes(true)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.sessions = [
            makeSession(id: "gone", updated: 20),
            makeSession(id: "keep", updated: 30),
            makeSession(id: "moved", updated: 10),
        ]
        state.currentSessionID = "gone"
        state.messages = [makeMessage(id: "m-gone", sessionID: "gone", role: "assistant", text: "gone")]

        let task = Task { @MainActor in
            try await state.deleteSession(sessionID: "gone")
        }
        await api.waitUntilDeletesPending(1)
        state.currentSessionID = "moved"
        state.messages = [makeMessage(id: "m-moved", sessionID: "moved", role: "user", text: "moved")]
        await api.releaseNextDelete()
        try await task.value

        #expect(state.currentSessionID == "moved")
        #expect(state.messages.map(\.info.id) == ["m-moved"])
        #expect(state.sessions.map(\.id) == ["keep", "moved"])
        #expect(await api.messagesCallCount == 0)
        #expect(await api.deletedSessionIDs == ["gone"])
    }

    @Test @MainActor func deleteInFlightOfOtherSessionDoesNotRestoreOldSelection() async throws {
        let api = SessionRecoveryAPIClient()
        await api.setSuspendDeletes(true)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.sessions = [
            makeSession(id: "gone", updated: 20),
            makeSession(id: "keep", updated: 30),
            makeSession(id: "moved", updated: 10),
        ]
        state.currentSessionID = "keep"
        state.messages = [makeMessage(id: "m-keep", sessionID: "keep", role: "assistant", text: "keep")]

        let task = Task { @MainActor in
            try await state.deleteSession(sessionID: "gone")
        }
        await api.waitUntilDeletesPending(1)
        state.currentSessionID = "moved"
        state.messages = [makeMessage(id: "m-moved", sessionID: "moved", role: "user", text: "moved")]
        await api.releaseNextDelete()
        try await task.value

        #expect(state.currentSessionID == "moved")
        #expect(state.messages.map(\.info.id) == ["m-moved"])
        #expect(!state.sessions.contains { $0.id == "gone" })
        #expect(state.sessions.contains { $0.id == "keep" })
        #expect(await api.messagesCallCount == 0)
    }

    @Test @MainActor func validateInFlight404DoesNotClearNewSelection() async {
        let api = SessionRecoveryAPIClient()
        await api.setSuspendMessages(true)
        await api.setMessagesError(notFound)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.sessions = [makeSession(id: "gone", updated: 20), makeSession(id: "moved", updated: 10)]
        state.currentSessionID = "gone"
        state.messages = [makeMessage(id: "m-gone", sessionID: "gone", role: "assistant", text: "gone")]

        let task = Task { @MainActor in
            await state.validateAndRecoverCurrentSession()
        }
        await api.waitUntilMessagesPending(1)
        state.currentSessionID = "moved"
        state.messages = [makeMessage(id: "m-moved", sessionID: "moved", role: "user", text: "moved")]
        await api.releaseNextMessagesFetch()
        await task.value

        #expect(state.currentSessionID == "moved")
        #expect(state.messages.map(\.info.id) == ["m-moved"])
        #expect(state.sessions.map(\.id) == ["gone", "moved"])
        #expect(await api.sessionsCallCount == 0)
        #expect(await api.messagesCallCount == 1)
        #expect(!state.sessionScope.confirmedMissingSessionIDs.contains("gone"))
    }

    @Test @MainActor func deleteCurrentSessionStillSelectsMostRecentlyUpdated() async throws {
        let api = SessionRecoveryAPIClient()
        await api.setMessages([makeMessage(id: "m-keep", sessionID: "keep", role: "user", text: "next")], forSession: "keep")
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.sessions = [
            makeSession(id: "gone", updated: 20),
            makeSession(id: "keep", updated: 30),
            makeSession(id: "older", updated: 5),
        ]
        state.currentSessionID = "gone"

        try await state.deleteSession(sessionID: "gone")

        #expect(state.currentSessionID == "keep")
        #expect(state.sessions.map(\.id).sorted() == ["keep", "older"])
        #expect(state.messages.map(\.info.id) == ["m-keep"])
        #expect(!state.sessionScope.confirmedMissingSessionIDs.contains("keep"))
    }

    @Test @MainActor func deleteRemovesOnlyTargetStatsAndTimings() async throws {
        let api = SessionRecoveryAPIClient()
        await api.setMessages([makeMessage(id: "u-keep", sessionID: "keep", role: "user", text: "kept")], forSession: "keep")
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.sessions = [
            makeSession(id: "gone", updated: 10),
            makeSession(id: "keep", updated: 30),
            makeSession(id: "other", updated: 5),
        ]
        state.currentSessionID = "gone"
        state.statsStore.observeUserMessage(id: "u-gone", sessionID: "gone")
        state.statsStore.observeUserMessage(id: "u-keep", sessionID: "keep")
        finishTiming(state, messageID: "m-gone", sessionID: "gone", tokens: 4)
        finishTiming(state, messageID: "m-keep", sessionID: "keep", tokens: 12)
        state.messageStore.recordPartType(sessionID: "gone", partID: "p-gone", type: "text")
        state.messageStore.recordPartType(sessionID: "keep", partID: "p-keep", type: "tool")
        state.revertResetPendingSessionIDs = ["gone", "other"]

        state.clearCurrentSessionViewState()
        #expect(state.stepTimings["m-keep"]?.outputTokens == 12)
        #expect(state.stepTimings["m-gone"]?.outputTokens == 4)
        #expect(state.messageStore.partType(for: "p-keep", inSession: "keep") == "tool")

        try await state.deleteSession(sessionID: "gone")

        #expect(state.currentSessionID == "keep")
        #expect(state.statsStore.stats(for: "gone").rounds == 0)
        #expect(state.statsStore.stats(for: "gone").seenUserMessageIDs.isEmpty)
        #expect(state.statsStore.stats(for: "keep").rounds == 1)
        #expect(state.statsStore.stats(for: "keep").seenUserMessageIDs == Set(["u-keep"]))
        #expect(state.stepTimings["m-gone"] == nil)
        #expect(state.stepTimings["m-keep"]?.outputTokens == 12)
        #expect(state.stepTimings["m-keep"]?.sessionID == "keep")
        #expect(state.messageStore.partType(for: "p-gone", inSession: "gone") == nil)
        #expect(state.messageStore.partType(for: "p-keep", inSession: "keep") == "tool")
        #expect(state.revertResetPendingSessionIDs == Set(["other"]))

        let reloadedStats = SessionStatsStore(defaults: defaults)
        let reloadedMessages = MessageStore(defaults: defaults)
        #expect(reloadedStats.stats(for: "gone").seenUserMessageIDs.isEmpty)
        #expect(reloadedStats.stats(for: "keep").rounds == 1)
        #expect(reloadedStats.stats(for: "keep").seenUserMessageIDs == Set(["u-keep"]))
        #expect(reloadedMessages.stepTimings["m-gone"] == nil)
        #expect(reloadedMessages.stepTimings["m-keep"]?.outputTokens == 12)
        #expect(reloadedMessages.stepTimings["m-keep"]?.sessionID == "keep")
    }

    @Test @MainActor func deleteOfOtherSessionClearsSelectionWhenUserSwitchesToTarget() async throws {
        let api = SessionRecoveryAPIClient()
        let gone = makeSession(id: "gone", updated: 20)
        let keep = makeSession(id: "keep", updated: 30)
        await api.setMessages([makeMessage(id: "m-gone", sessionID: "gone", role: "user", text: "opened")], forSession: "gone")
        await api.setSuspendDeletes(true)
        await api.setSuspendSessionDiffs(true)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.sessions = [gone, keep]
        state.currentSessionID = "keep"
        state.messages = [makeMessage(id: "m-keep", sessionID: "keep", role: "assistant", text: "keep")]

        let task = Task { @MainActor in
            try await state.deleteSession(sessionID: "gone")
        }
        await api.waitUntilDeletesPending(1)
        state.selectSession(gone)
        await api.waitUntilSessionDiffsPending(1)
        #expect(state.currentSessionID == "gone")
        #expect(state.messages.map(\.info.id) == ["m-gone"])

        await api.releaseNextDelete()
        try await task.value

        #expect(state.currentSessionID == nil)
        #expect(state.messages.isEmpty)
        #expect(state.sessions.map(\.id) == ["keep"])
        #expect(state.sessionScope.confirmedMissingSessionIDs.contains("gone"))
        #expect(defaults.string(forKey: "currentSessionID") == nil)
        #expect(await api.deletedSessionIDs == ["gone"])
        #expect(await api.messageSessionIDs == ["gone"])
        #expect(await api.messagesCallCount == 1)
        await api.releaseNextSessionDiff()
    }

    @Test @MainActor func lateValidate404DoesNotUndoSuccessfulOpen() async {
        let api = SessionRecoveryAPIClient()
        await api.setSuspendMessages(true)
        await api.setMessagesError(notFound)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.sessions = [makeSession(id: "gone", updated: 20), makeSession(id: "moved", updated: 10)]
        state.currentSessionID = "gone"

        let task = Task { @MainActor in
            await state.validateAndRecoverCurrentSession()
        }
        await api.waitUntilMessagesPending(1)
        state.currentSessionID = "moved"
        state.messages = [makeMessage(id: "m-moved", sessionID: "moved", role: "user", text: "moved")]
        await reopenUntilMessagesLoaded(state, api: api, sessionID: "gone")
        #expect(state.currentSessionID == "gone")
        #expect(state.messages.map(\.info.id) == ["m-reopen"])
        state.setDraftText("saved after reopen", for: "gone")
        state.currentSessionID = "moved"
        state.messages = [makeMessage(id: "m-moved", sessionID: "moved", role: "user", text: "moved")]

        await api.releaseNextMessagesFetch()
        await task.value

        #expect(state.currentSessionID == "moved")
        #expect(state.messages.map(\.info.id) == ["m-moved"])
        #expect(state.sessions.contains { $0.id == "gone" })
        #expect(!state.sessionScope.confirmedMissingSessionIDs.contains("gone"))
        #expect(state.draftText(for: "gone") == "saved after reopen")
        #expect(persistedDraft(defaults, "gone") == "saved after reopen")
        #expect(await api.sessionsCallCount == 0)
        await api.releaseNextSessionDiff()
    }

    @Test @MainActor func lateMessages404DoesNotUndoSuccessfulOpen() async {
        let api = SessionRecoveryAPIClient()
        await api.setSuspendMessages(true)
        await api.setMessagesError(notFound)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.sessions = [makeSession(id: "gone", updated: 20), makeSession(id: "moved", updated: 10)]
        state.currentSessionID = "gone"
        state.messages = [makeMessage(id: "m-gone", sessionID: "gone", role: "assistant", text: "old")]

        let task = Task { @MainActor in
            await state.loadMessages()
        }
        await api.waitUntilMessagesPending(1)
        state.currentSessionID = "moved"
        state.messages = [makeMessage(id: "m-moved", sessionID: "moved", role: "user", text: "moved")]
        await reopenUntilMessagesLoaded(state, api: api, sessionID: "gone")
        state.setDraftText("saved after reopen", for: "gone")
        state.currentSessionID = "moved"
        state.messages = [makeMessage(id: "m-moved", sessionID: "moved", role: "user", text: "moved")]

        await api.releaseNextMessagesFetch()
        await task.value

        #expect(state.currentSessionID == "moved")
        #expect(state.messages.map(\.info.id) == ["m-moved"])
        #expect(state.sessions.contains { $0.id == "gone" })
        #expect(!state.sessionScope.confirmedMissingSessionIDs.contains("gone"))
        #expect(state.draftText(for: "gone") == "saved after reopen")
        #expect(persistedDraft(defaults, "gone") == "saved after reopen")
        #expect(await api.sessionsCallCount == 0)
        await api.releaseNextSessionDiff()
    }

    @Test @MainActor func confirmedDeleteRejectsLateListPayloadAndUpdated() async throws {
        let api = SessionRecoveryAPIClient()
        let gone = makeSession(id: "gone", updated: 20)
        let keep = makeSession(id: "keep", updated: 30)
        await api.setSessionsResult([gone, keep])
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.selectedProjectWorktree = "/tmp"
        state.loadedSessionLimit = 2
        state.sessions = [gone, keep]
        state.currentSessionID = "keep"
        state.setDraftText("doomed", for: "gone")
        state.setDraftText("kept", for: "keep")

        try await state.deleteSession(sessionID: "gone")

        #expect(state.currentSessionID == "keep")
        #expect(state.draftText(for: "gone").isEmpty)
        #expect(persistedDraft(defaults, "gone") == nil)
        #expect(state.draftText(for: "keep") == "kept")
        #expect(state.sessionScope.confirmedMissingSessionIDs.contains("gone"))

        await state.loadSessions()
        #expect(state.sessions.map(\.id) == ["keep"])
        #expect(state.currentSessionID == "keep")
        #expect(state.hasMoreSessions == true)

        await state.applySSEEventForTesting(try SSEEvent.sessionUpdated("gone"))
        #expect(state.sessions.map(\.id) == ["keep"])
        #expect(state.currentSessionID == "keep")
        #expect(state.sessionScope.confirmedMissingSessionIDs.contains("gone"))
    }

    @Test @MainActor func confirmedDeleteRejectsGoneOnLoadMore() async throws {
        let api = SessionRecoveryAPIClient()
        let keep = makeSession(id: "keep", updated: 30)
        let page = [makeSession(id: "gone", updated: 9_000), keep] + (0..<798).map { makeSession(id: "s-\($0)", updated: $0) }
        await api.setSessionsResult(page)
        let (state, defaults, suite) = makeState(api)
        defer { defaults.removePersistentDomain(forName: suite) }
        state.isConnected = true
        state.hasMoreSessions = true
        state.sessions = [makeSession(id: "gone", updated: 20), keep]
        state.currentSessionID = "keep"

        try await state.deleteSession(sessionID: "gone")
        await state.loadMoreSessions()

        #expect(state.currentSessionID == "keep")
        #expect(!state.sessions.contains { $0.id == "gone" })
        #expect(state.sessions.contains { $0.id == "keep" })
        #expect(state.sessions.count == 799)
        #expect(state.hasMoreSessions == true)
        #expect(state.loadedSessionLimit == 800)
        #expect(await api.sessionsCallCount == 1)
    }

    @MainActor
    private func finishTiming(_ state: AppState, messageID: String, sessionID: String, tokens: Int) {
        state.messageStore.recordStepStart(messageID, sessionID: sessionID)
        state.messageStore.recordVisibleToken(messageID, sessionID: sessionID)
        state.messageStore.recordStepFinish(messageID, sessionID: sessionID, outputTokens: tokens)
    }

    @MainActor
    private func reopenUntilMessagesLoaded(_ state: AppState, api: SessionRecoveryAPIClient, sessionID: String) async {
        await api.setSuspendMessages(false)
        await api.setMessagesError(nil)
        await api.setMessages([makeMessage(id: "m-reopen", sessionID: sessionID, role: "user", text: "back")], forSession: sessionID)
        await api.setSuspendSessionDiffs(true)
        state.sessions.removeAll { $0.id == sessionID }
        await state.openReferencedSession(sessionID: sessionID)
        await api.waitUntilSessionDiffsPending(1)
    }
}

@MainActor
private func makeState(_ api: SessionRecoveryAPIClient) -> (AppState, UserDefaults, String) {
    let suite = "opencode.tests.w01.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let state = AppState(
        apiClient: api,
        sseClient: MockSSEClient(),
        sshTunnelManager: SSHTunnelManager(),
        userDefaults: defaults
    )
    return (state, defaults, suite)
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

private func makeMessage(
    id: String,
    sessionID: String,
    role: String,
    text: String,
    model: Message.ModelInfo? = nil
) -> MessageWithParts {
    let message = Message(
        id: id,
        sessionID: sessionID,
        role: role,
        parentID: nil,
        providerID: nil,
        modelID: nil,
        model: model,
        error: nil,
        time: .init(created: 1, completed: 2),
        finish: "stop",
        tokens: nil,
        cost: nil
    )
    let part = Part(
        id: "p-\(id)",
        messageID: id,
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

private func persistedDraft(_ defaults: UserDefaults, _ sessionID: String) -> String? {
    guard let data = defaults.data(forKey: AppState.draftInputsBySessionKey),
          let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
        return nil
    }
    return decoded[sessionID]
}

private extension SSEEvent {
    static func sessionDeleted(_ sessionID: String) throws -> SSEEvent {
        let json = #"{"payload":{"type":"session.deleted","properties":{"sessionID":"\#(sessionID)"}}}"#
        return try JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8))
    }

    static func sessionUpdated(_ sessionID: String) throws -> SSEEvent {
        let json = #"{"payload":{"type":"session.updated","properties":{"session":{"id":"\#(sessionID)","slug":"\#(sessionID)","projectID":"p1","directory":"/tmp","parentID":null,"title":"revived","version":"1","time":{"created":0,"updated":50},"share":null,"summary":null}}}}"#
        return try JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8))
    }
}

actor SessionRecoveryAPIClient: APIClientProtocol {
    private(set) var messagesCallCount = 0
    private(set) var messageSessionIDs: [String] = []
    private(set) var sessionsCallCount = 0
    private(set) var deletedSessionIDs: [String] = []
    private(set) var sessionDiffSessionIDs: [String] = []
    private(set) var sessionTodoSessionIDs: [String] = []

    private var sessionsResult: [Session] = []
    private var messagesResult: [MessageWithParts] = []
    private var messagesBySession: [String: [MessageWithParts]] = [:]
    private var diffsBySession: [String: [FileDiff]] = [:]
    private var todosBySession: [String: [TodoItem]] = [:]
    private var messagesError: Error?
    private var abortError: Error?
    private var suspendSessions = false
    private var suspendMessages = false
    private var suspendDeletes = false
    private var suspendSessionDiffs = false
    private var sessionWaiters: [CheckedContinuation<Void, Never>] = []
    private var sessionObservers: [CheckedContinuation<Void, Never>] = []
    private var messageWaiters: [CheckedContinuation<Void, Never>] = []
    private var messageObservers: [CheckedContinuation<Void, Never>] = []
    private var deleteWaiters: [CheckedContinuation<Void, Never>] = []
    private var deleteObservers: [CheckedContinuation<Void, Never>] = []
    private var sessionDiffWaiters: [CheckedContinuation<Void, Never>] = []
    private var sessionDiffObservers: [CheckedContinuation<Void, Never>] = []

    func setSessionsResult(_ sessions: [Session]) {
        sessionsResult = sessions
    }

    func setMessages(_ messages: [MessageWithParts], forSession sessionID: String) {
        messagesBySession[sessionID] = messages
    }

    func setMessagesError(_ error: Error?) {
        messagesError = error
    }

    func setAbortError(_ error: Error?) {
        abortError = error
    }

    func setSessionDiff(_ diffs: [FileDiff], forSession sessionID: String) {
        diffsBySession[sessionID] = diffs
    }

    func setSessionTodos(_ todos: [TodoItem], forSession sessionID: String) {
        todosBySession[sessionID] = todos
    }

    func setSuspendSessions(_ value: Bool) {
        suspendSessions = value
    }

    func setSuspendMessages(_ value: Bool) {
        suspendMessages = value
    }

    func setSuspendDeletes(_ value: Bool) {
        suspendDeletes = value
    }

    func setSuspendSessionDiffs(_ value: Bool) {
        suspendSessionDiffs = value
    }

    func waitUntilSessionsPending(_ count: Int) async {
        while sessionWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sessionObservers.append(cont)
            }
        }
    }

    func waitUntilMessagesPending(_ count: Int) async {
        while messageWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                messageObservers.append(cont)
            }
        }
    }

    func waitUntilDeletesPending(_ count: Int) async {
        while deleteWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                deleteObservers.append(cont)
            }
        }
    }

    func releaseNextSessionsFetch() {
        guard !sessionWaiters.isEmpty else { return }
        sessionWaiters.removeFirst().resume()
    }

    func releaseNextMessagesFetch() {
        guard !messageWaiters.isEmpty else { return }
        messageWaiters.removeFirst().resume()
    }

    func releaseNextDelete() {
        guard !deleteWaiters.isEmpty else { return }
        deleteWaiters.removeFirst().resume()
    }

    func waitUntilSessionDiffsPending(_ count: Int) async {
        while sessionDiffWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sessionDiffObservers.append(cont)
            }
        }
    }

    func releaseNextSessionDiff() {
        guard !sessionDiffWaiters.isEmpty else { return }
        sessionDiffWaiters.removeFirst().resume()
    }

    func configure(baseURL: String, username: String?, password: String?) {}

    func health() async throws -> HealthResponse {
        HealthResponse(healthy: true, version: "test")
    }

    func projects() async throws -> [Project] { [] }
    func projectCurrent() async throws -> Project? { nil }

    func sessions(directory: String?, limit: Int) async throws -> [Session] {
        sessionsCallCount += 1
        if sessionsCallCount > 8 {
            throw APIError.httpError(statusCode: 599, data: Data())
        }
        if suspendSessions {
            await suspendSessionFetch()
        }
        return sessionsResult
    }

    func session(sessionID: String) async throws -> Session {
        makeSession(id: sessionID, updated: 1)
    }

    func createSession(title: String?, directory: String?) async throws -> Session {
        makeSession(id: "created", updated: 1)
    }

    func updateSession(sessionID: String, title: String) async throws -> Session {
        makeSession(id: sessionID, updated: 1)
    }

    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
        makeSession(id: sessionID, updated: 1)
    }

    func deleteSession(sessionID: String) async throws {
        deletedSessionIDs.append(sessionID)
        if suspendDeletes {
            await suspendDelete()
        }
    }

    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] {
        messagesCallCount += 1
        messageSessionIDs.append(sessionID)
        if messagesCallCount > 8 {
            throw APIError.httpError(statusCode: 599, data: Data())
        }
        let errorForThisCall = messagesError
        if suspendMessages {
            await suspendMessageFetch()
        }
        if let errorForThisCall { throw errorForThisCall }
        return messagesBySession[sessionID] ?? messagesResult
    }

    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {}

    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
        throw APIError.invalidURL
    }

    func abort(sessionID: String) async throws {
        if let abortError { throw abortError }
    }
    func sessionStatus() async throws -> [String: SessionStatus] { [:] }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
    func pendingQuestions() async throws -> [QuestionRequest] { [] }
    func replyQuestion(requestID: String, answers: [[String]]) async throws {}
    func rejectQuestion(requestID: String) async throws {}

    func providers() async throws -> ProvidersResponse {
        try JSONDecoder().decode(ProvidersResponse.self, from: Data("{\"providers\":[]}".utf8))
    }

    func providerRegistry() async throws -> ProviderRegistryResponse {
        ProviderRegistryResponse(providers: [], connectedProviderIDs: [])
    }

    func agents() async throws -> [AgentInfo] { [] }
    func sessionDiff(sessionID: String) async throws -> [FileDiff] {
        sessionDiffSessionIDs.append(sessionID)
        if suspendSessionDiffs {
            await suspendSessionDiff()
        }
        return diffsBySession[sessionID] ?? []
    }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] {
        sessionTodoSessionIDs.append(sessionID)
        return todosBySession[sessionID] ?? []
    }
    func fileList(path: String, directory: String?) async throws -> [FileNode] { [] }
    func fileContent(path: String, directory: String?) async throws -> FileContent {
        FileContent(type: "text", content: "")
    }
    func findFile(query: String, limit: Int) async throws -> [String] { [] }
    func fileStatus() async throws -> [FileStatusEntry] { [] }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session {
        makeSession(id: "forked", updated: 1)
    }
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
        makeSession(id: sessionID, updated: 1)
    }

    private func suspendSessionFetch() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionWaiters.append(cont)
            let pending = sessionObservers
            sessionObservers.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private func suspendMessageFetch() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            messageWaiters.append(cont)
            let pending = messageObservers
            messageObservers.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private func suspendDelete() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            deleteWaiters.append(cont)
            let pending = deleteObservers
            deleteObservers.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private func suspendSessionDiff() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionDiffWaiters.append(cont)
            let pending = sessionDiffObservers
            sessionDiffObservers.removeAll()
            pending.forEach { $0.resume() }
        }
    }
}
