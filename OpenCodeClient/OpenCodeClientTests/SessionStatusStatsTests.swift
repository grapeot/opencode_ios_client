//
//  SessionStatusStatsTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

// MARK: - Compact token formatting

struct CompactTokenCountTests {

    @Test func belowThousandIsRaw() {
        #expect(MessageRowView.compactTokenCount(0) == "0")
        #expect(MessageRowView.compactTokenCount(1) == "1")
        #expect(MessageRowView.compactTokenCount(950) == "950")
        #expect(MessageRowView.compactTokenCount(999) == "999")
    }

    @Test func kilobyteRange() {
        #expect(MessageRowView.compactTokenCount(1_000) == "1K")
        #expect(MessageRowView.compactTokenCount(1_500) == "1.5K")
        #expect(MessageRowView.compactTokenCount(85_200) == "85.2K")
        #expect(MessageRowView.compactTokenCount(999_999) == "1M")
    }

    @Test func megabyteRange() {
        #expect(MessageRowView.compactTokenCount(1_000_000) == "1M")
        #expect(MessageRowView.compactTokenCount(1_100_000) == "1.1M")
        #expect(MessageRowView.compactTokenCount(1_110_000) == "1.11M")
        #expect(MessageRowView.compactTokenCount(852_000_000) == "852M")
        #expect(MessageRowView.compactTokenCount(999_999_999) == "1B")
    }

    @Test func gigabyteRange() {
        #expect(MessageRowView.compactTokenCount(1_000_000_000) == "1B")
        #expect(MessageRowView.compactTokenCount(2_000_000_000) == "2B")
        #expect(MessageRowView.compactTokenCount(2_100_000_000) == "2.1B")
        #expect(MessageRowView.compactTokenCount(1_110_000_000) == "1.11B")
    }
}

// MARK: - SessionStatsStore

private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "opencode.tests.stats.\(UUID().uuidString)")!
}

struct SessionStatsStoreTests {

    @Test @MainActor func observeUserMessageCountsOncePerID() {
        let store = SessionStatsStore(defaults: isolatedDefaults())
        #expect(store.observeUserMessage(id: "u1", sessionID: "s1"))
        #expect(store.observeUserMessage(id: "u1", sessionID: "s1") == false)
        #expect(store.observeUserMessage(id: "u2", sessionID: "s1"))
        let stats = store.stats(for: "s1")
        #expect(stats.rounds == 2)
        #expect(stats.toolCalls == 0)
        #expect(stats.baselineComplete == false)
    }

    @Test @MainActor func observeToolPartCountsOncePerPartID() {
        let store = SessionStatsStore(defaults: isolatedDefaults())
        #expect(store.observeToolPart(id: "tp1", sessionID: "s1"))
        // Replayed statuses for the same part (running/completed) must not
        // double-count.
        #expect(store.observeToolPart(id: "tp1", sessionID: "s1") == false)
        #expect(store.observeToolPart(id: "tp2", sessionID: "s1"))
        #expect(store.stats(for: "s1").toolCalls == 2)
        #expect(store.stats(for: "s1").rounds == 0)
    }

    @Test @MainActor func partialReconcileOnlyAddsNewIDs() {
        let store = SessionStatsStore(defaults: isolatedDefaults())
        store.observeUserMessage(id: "u-live", sessionID: "s1")

        // A window that re-contains the live id plus older ids: only the
        // unseen ones are counted.
        store.reconcile(
            sessionID: "s1",
            userMessageIDs: ["u-live", "u-old-1", "u-old-2"],
            toolPartIDs: ["tp-old-1"],
            isComplete: false
        )
        let stats = store.stats(for: "s1")
        #expect(stats.rounds == 3)
        #expect(stats.toolCalls == 1)
        #expect(stats.baselineComplete == false)

        // Reconciling the same window again changes nothing.
        store.reconcile(
            sessionID: "s1",
            userMessageIDs: ["u-live", "u-old-1", "u-old-2"],
            toolPartIDs: ["tp-old-1"],
            isComplete: false
        )
        #expect(store.stats(for: "s1").rounds == 3)
    }

    @Test @MainActor func completeReconcileRecomputesExactly() {
        let store = SessionStatsStore(defaults: isolatedDefaults())
        store.observeUserMessage(id: "u-live", sessionID: "s1")
        store.observeToolPart(id: "tp-live", sessionID: "s1")

        store.reconcile(
            sessionID: "s1",
            userMessageIDs: ["u-1", "u-2", "u-live"],
            toolPartIDs: ["tp-a", "tp-b", "tp-live"],
            isComplete: true
        )
        let stats = store.stats(for: "s1")
        #expect(stats.rounds == 3)
        #expect(stats.toolCalls == 3)
        #expect(stats.baselineComplete == true)
    }

    @Test @MainActor func resetForRevertRecomputesFromWindow() {
        let store = SessionStatsStore(defaults: isolatedDefaults())
        store.observeUserMessage(id: "u1", sessionID: "s1")
        store.observeUserMessage(id: "u2", sessionID: "s1")
        store.observeToolPart(id: "tp1", sessionID: "s1")
        store.reconcile(sessionID: "s1", userMessageIDs: ["u1", "u2"], toolPartIDs: ["tp1"], isComplete: true)
        #expect(store.stats(for: "s1").baselineComplete == true)

        // Revert to u1: u2 and its parts are gone.
        store.resetForRevert(sessionID: "s1", userMessageIDs: ["u1"], toolPartIDs: [])
        let stats = store.stats(for: "s1")
        #expect(stats.rounds == 1)
        #expect(stats.toolCalls == 0)
        #expect(stats.baselineComplete == false)
    }

    @Test @MainActor func statsSurviveStoreRecreation() {
        let defaults = isolatedDefaults()
        let store = SessionStatsStore(defaults: defaults)
        store.observeUserMessage(id: "u1", sessionID: "s1")
        store.observeToolPart(id: "tp1", sessionID: "s1")

        let reloaded = SessionStatsStore(defaults: defaults)
        #expect(reloaded.stats(for: "s1").rounds == 1)
        #expect(reloaded.stats(for: "s1").toolCalls == 1)
        // Deduplication must hold across restarts.
        #expect(reloaded.observeUserMessage(id: "u1", sessionID: "s1") == false)
        #expect(reloaded.observeUserMessage(id: "u2", sessionID: "s1"))
        #expect(reloaded.stats(for: "s1").rounds == 2)
    }

    @Test @MainActor func removeDropsSessionState() {
        let store = SessionStatsStore(defaults: isolatedDefaults())
        store.observeUserMessage(id: "u1", sessionID: "s1")
        store.remove(sessionID: "s1")
        #expect(store.stats(for: "s1") == SessionStatsStore.SessionStats())
        // Re-observing after removal starts a fresh count.
        #expect(store.observeUserMessage(id: "u1", sessionID: "s1"))
        #expect(store.stats(for: "s1").rounds == 1)
    }

    @Test @MainActor func sessionsAreIsolated() {
        let store = SessionStatsStore(defaults: isolatedDefaults())
        store.observeUserMessage(id: "u1", sessionID: "s1")
        #expect(store.stats(for: "s2").rounds == 0)
    }
}

// MARK: - Session model decoding

struct SessionTokensDecodingTests {

    private let baseJSON = """
    {"id":"ses_1","slug":"calm","projectID":"p1","directory":"/work","parentID":null,"title":"t","version":"1","time":{"created":1,"updated":2}}
    """

    @Test func decodesServerProvidedTokensAndCost() throws {
        let json = """
        {"id":"ses_1","slug":"calm","projectID":"p1","directory":"/work","parentID":null,"title":"t","version":"1","time":{"created":1,"updated":2},"tokens":{"input":14542,"output":34,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.0022}
        """
        let session = try JSONDecoder().decode(Session.self, from: json.data(using: .utf8)!)
        #expect(session.tokens?.input == 14542)
        #expect(session.tokens?.output == 34)
        #expect(session.tokens?.total == 14576)
        #expect(session.cost == 0.0022)
        _ = baseJSON
    }

    @Test func decodesAggregateWithoutTotalField() throws {
        // Newer server payloads omit `total`; TokenInfo derives it.
        let json = """
        {"id":"ses_1","slug":"calm","projectID":"p1","directory":"/work","parentID":null,"title":"t","version":"1","time":{"created":1,"updated":2},"tokens":{"input":100,"output":5,"reasoning":3}}
        """
        let session = try JSONDecoder().decode(Session.self, from: json.data(using: .utf8)!)
        #expect(session.tokens?.total == 108)
        #expect(session.tokens?.cache == nil)
        #expect(session.cost == nil)
    }

    @Test func missingFieldsDecodeAsNil() throws {
        let session = try JSONDecoder().decode(Session.self, from: baseJSON.data(using: .utf8)!)
        #expect(session.tokens == nil)
        #expect(session.cost == nil)
    }
}

// MARK: - sessionTotalTokens

struct SessionTotalTokensTests {

    private func makeSession(id: String, tokens: Message.TokenInfo? = nil) -> Session {
        var session = Session(
            id: id,
            slug: "calm",
            projectID: "p1",
            directory: "/work",
            parentID: nil,
            title: "t",
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
        session.tokens = tokens
        return session
    }

    private static func makeTokenInfo(_ json: String) -> Message.TokenInfo {
        try! JSONDecoder().decode(Message.TokenInfo.self, from: json.data(using: .utf8)!)
    }

    private func makeAssistantRow(id: String, total: Int) -> MessageWithParts {
        MessageWithParts(
            info: Message(
                id: id,
                sessionID: "s1",
                role: "assistant",
                parentID: nil,
                providerID: nil,
                modelID: nil,
                model: nil,
                error: nil,
                time: .init(created: 0, completed: 1),
                finish: "stop",
                tokens: Self.makeTokenInfo("{\"total\":\(total),\"input\":\(max(total - 5, 0)),\"output\":3,\"reasoning\":2}"),
                cost: nil
            ),
            parts: []
        )
    }

    @Test @MainActor func prefersServerAggregate() {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1", tokens: Self.makeTokenInfo("""
        {"total":20142,"input":20000,"output":90,"reasoning":52}
        """))]
        #expect(state.sessionTotalTokens(sessionID: "s1") == 20_142)
    }

    @Test @MainActor func fallsBackToCompleteWindowSum() {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1")]
        state.messages = [makeAssistantRow(id: "m1", total: 100), makeAssistantRow(id: "m2", total: 55)]
        state.hasMoreHistoryBySessionID["s1"] = false
        #expect(state.sessionTotalTokens(sessionID: "s1") == 155)
    }

    @Test @MainActor func hidesSegmentForPartialWindowWithoutAggregate() {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1")]
        state.messages = [makeAssistantRow(id: "m1", total: 100)]
        state.hasMoreHistoryBySessionID["s1"] = true
        #expect(state.sessionTotalTokens(sessionID: "s1") == nil)
    }

    @Test @MainActor func zeroAggregateFallsThroughToWindow() {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1", tokens: Self.makeTokenInfo("""
        {"total":0,"input":0,"output":0,"reasoning":0}
        """))]
        state.messages = [makeAssistantRow(id: "m1", total: 42)]
        state.hasMoreHistoryBySessionID["s1"] = false
        #expect(state.sessionTotalTokens(sessionID: "s1") == 42)
    }
}

// MARK: - SSE increments through AppState

struct SSEStatsIncrementTests {

    /// The SSE handlers reload the message list after events, and a complete
    /// window is recomputed exactly — so the mock must mirror what the real
    /// server would return (persisted rows), not an empty list.
    private static func makeRow(
        messageID: String,
        role: String,
        toolPartIDs: [String]
    ) -> MessageWithParts {
        let message = Message(
            id: messageID,
            sessionID: "s1",
            role: role,
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 0, completed: 1),
            finish: role == "assistant" ? "stop" : nil,
            tokens: nil,
            cost: nil
        )
        let parts = toolPartIDs.map { partID in
            Part(
                id: partID,
                messageID: messageID,
                sessionID: "s1",
                type: "tool",
                text: nil,
                tool: "bash",
                callID: nil,
                state: nil,
                metadata: nil,
                files: nil
            )
        }
        return MessageWithParts(info: message, parts: parts)
    }

    @Test @MainActor func messageUpdatedUserRoleIncrementsRounds() async {
        let apiClient = MockAPIClient()
        await apiClient.setMessagesResult([Self.makeRow(messageID: "u1", role: "user", toolPartIDs: [])])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","info":{"id":"u1","role":"user","sessionID":"s1","time":{"created":1}}}}}
        """))
        #expect(state.statsStore.stats(for: "s1").rounds == 1)

        // Replayed event must not double-count.
        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","info":{"id":"u1","role":"user","sessionID":"s1","time":{"created":1}}}}}
        """))
        #expect(state.statsStore.stats(for: "s1").rounds == 1)
    }

    @Test @MainActor func messageUpdatedOtherSessionDoesNotCount() async {
        let apiClient = MockAPIClient()
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s2","info":{"id":"u1","role":"user","sessionID":"s2","time":{"created":1}}}}}
        """))
        #expect(state.statsStore.stats(for: "s1").rounds == 0)
    }

    @Test @MainActor func toolPartEventIncrementsToolCallsOncePerPartID() async {
        let apiClient = MockAPIClient()
        await apiClient.setMessagesResult([Self.makeRow(messageID: "m1", role: "assistant", toolPartIDs: ["tp1"])])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.currentSessionID = "s1"

        for status in ["pending", "running", "completed"] {
            await state.applySSEEventForTesting(Self.makeSSEEvent("""
            {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","part":{"id":"tp1","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash","state":{"status":"\(status)"}}}}}
            """))
        }
        #expect(state.statsStore.stats(for: "s1").toolCalls == 1)

        await apiClient.setMessagesResult([Self.makeRow(messageID: "m1", role: "assistant", toolPartIDs: ["tp1", "tp2"])])
        await state.applySSEEventForTesting(Self.makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","part":{"id":"tp2","messageID":"m1","sessionID":"s1","type":"tool","tool":"read","state":{"status":"pending"}}}}}
        """))
        #expect(state.statsStore.stats(for: "s1").toolCalls == 2)
    }

    private static func makeSSEEvent(_ json: String) -> SSEEvent {
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(SSEEvent.self, from: data)
    }
}
