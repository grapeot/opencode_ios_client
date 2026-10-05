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
        #expect(MessageRowView.compactTokenCount(999_999_999_999) == "1T")
    }

    @Test func terabyteRange() {
        #expect(MessageRowView.compactTokenCount(1_000_000_000_000) == "1T")
        #expect(MessageRowView.compactTokenCount(1_234_567_890_123) == "1.23T")
    }
}

// MARK: - Elapsed stopwatch formatting

struct ElapsedStatusTextTests {

    @Test func belowAnHourIsZeroPaddedMinutesSeconds() {
        #expect(ChatTabView.elapsedStatusText(seconds: 0) == "00:00")
        #expect(ChatTabView.elapsedStatusText(seconds: 7) == "00:07")
        #expect(ChatTabView.elapsedStatusText(seconds: 41) == "00:41")
        #expect(ChatTabView.elapsedStatusText(seconds: 221) == "03:41")
        #expect(ChatTabView.elapsedStatusText(seconds: 599) == "09:59")
    }

    @Test func atOrAboveAnHourAddsZeroPaddedHours() {
        #expect(ChatTabView.elapsedStatusText(seconds: 3_599) == "59:59")
        #expect(ChatTabView.elapsedStatusText(seconds: 3_600) == "01:00:00")
        #expect(ChatTabView.elapsedStatusText(seconds: 7_421) == "02:03:41")
        #expect(ChatTabView.elapsedStatusText(seconds: 177_790) == "49:23:10")
    }

    @Test func negativeClampsToZero() {
        // Clock skew (message timestamp in the future) must never render a
        // negative duration.
        #expect(ChatTabView.elapsedStatusText(seconds: -1) == "00:00")
        #expect(ChatTabView.elapsedStatusText(seconds: -9_999) == "00:00")
    }

    @Test func spokenTextIsNonEmptyForEveryInput() {
        // Guards the accessibility fallback: zero and skew must not yield nil.
        for seconds in [-1, 0, 1, 221, 3_600, 7_421] {
            #expect(!ChatTabView.elapsedSpokenText(seconds: seconds).isEmpty)
        }
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

    @Test func synthesizedTotalIncludesCacheLikeServer() throws {
        // The server's `total` sums every component, cache included. A payload
        // that omits `total` must synthesize the same number, or the aggregate
        // (cache read often dominates a long session) undercounts.
        let json = """
        {"id":"ses_1","slug":"calm","projectID":"p1","directory":"/work","parentID":null,"title":"t","version":"1","time":{"created":1,"updated":2},"tokens":{"input":21889,"output":2750,"reasoning":37,"cache":{"read":16128,"write":0}}}
        """
        let session = try JSONDecoder().decode(Session.self, from: json.data(using: .utf8)!)
        #expect(session.tokens?.total == 40804)
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

// MARK: - sessionCacheHitRate

struct SessionCacheHitRateTests {

    private static func makeTokenInfo(_ json: String) -> Message.TokenInfo {
        try! JSONDecoder().decode(Message.TokenInfo.self, from: json.data(using: .utf8)!)
    }

    private func makeSession(id: String, tokensJSON: String? = nil) -> Session {
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
        if let tokensJSON {
            session.tokens = Self.makeTokenInfo(tokensJSON)
        }
        return session
    }

    private func makeAssistantRow(id: String, tokensJSON: String) -> MessageWithParts {
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
                tokens: Self.makeTokenInfo(tokensJSON),
                cost: nil
            ),
            parts: []
        )
    }

    @Test @MainActor func prefersServerAggregate() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        // Real wire shape: total = input + output + reasoning + cache.read,
        // with `input` counting only non-cached input.
        state.sessions = [makeSession(id: "s1", tokensJSON: """
        {"total":38809,"input":1562,"output":108,"reasoning":60,"cache":{"read":37079,"write":0}}
        """)]
        let rate = state.sessionCacheHitRate(sessionID: "s1")
        #expect(rate != nil)
        #expect(abs(rate! - 37079.0 / 38641.0) < 1e-9)
    }

    @Test @MainActor func noCacheFieldsMeansZeroPercent() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1", tokensJSON: """
        {"total":250,"input":200,"output":40,"reasoning":10}
        """)]
        // No cache field with input > 0 is a real 0%, not "no data":
        // this host simply does not cache.
        let rate = state.sessionCacheHitRate(sessionID: "s1")
        #expect(rate != nil)
        #expect(rate! == 0.0)
    }

    @Test @MainActor func fallsBackToCompleteWindow() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1")]
        state.messages = [
            makeAssistantRow(id: "m1", tokensJSON: """
            {"total":400,"input":300,"output":90,"reasoning":10,"cache":{"read":0,"write":0}}
            """),
            makeAssistantRow(id: "m2", tokensJSON: """
            {"total":1400,"input":100,"output":200,"reasoning":100,"cache":{"read":900,"write":0}}
            """),
        ]
        state.hasMoreHistoryBySessionID["s1"] = false
        let rate = state.sessionCacheHitRate(sessionID: "s1")
        // (0 + 900) / (300 + 100 + 0 + 900) = 900/1300
        #expect(rate != nil)
        #expect(abs(rate! - 900.0 / 1300.0) < 1e-9)
    }

    @Test @MainActor func partialWindowWithoutAggregateIsNil() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1")]
        state.messages = [
            makeAssistantRow(id: "m1", tokensJSON: """
            {"total":400,"input":300,"output":90,"reasoning":10,"cache":{"read":0,"write":0}}
            """),
        ]
        state.hasMoreHistoryBySessionID["s1"] = true
        #expect(state.sessionCacheHitRate(sessionID: "s1") == nil)
    }

    @Test @MainActor func inputlessAggregateFallsThroughToWindow() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [makeSession(id: "s1", tokensJSON: """
        {"total":50,"input":0,"output":50,"reasoning":0,"cache":{"read":0,"write":0}}
        """)]
        state.messages = [
            makeAssistantRow(id: "m1", tokensJSON: """
            {"total":1100,"input":100,"output":100,"reasoning":0,"cache":{"read":900,"write":0}}
            """),
        ]
        state.hasMoreHistoryBySessionID["s1"] = false
        let rate = state.sessionCacheHitRate(sessionID: "s1")
        #expect(rate != nil)
        #expect(abs(rate! - 0.9) < 1e-9)
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

// MARK: - Subagent rollup (tokens + cache hit rate fold into the main number)

struct SessionSubagentRollupTests {

    private func makeSession(
        id: String,
        parentID: String? = nil,
        tokensJSON: String? = nil
    ) -> Session {
        var session = Session(
            id: id,
            slug: "calm",
            projectID: "p1",
            directory: "/work",
            parentID: parentID,
            title: "t",
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
        if let tokensJSON {
            session.tokens = try! JSONDecoder().decode(
                Message.TokenInfo.self, from: tokensJSON.data(using: .utf8)!
            )
        }
        return session
    }

    @Test @MainActor func groupContainsSelfAndAllDescendantsSelfFirst() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [
            makeSession(id: "main", tokensJSON: "{\"total\":100,\"input\":10,\"output\":40,\"reasoning\":10,\"cache\":{\"read\":40,\"write\":0}}"),
            makeSession(id: "child-a", parentID: "main", tokensJSON: "{\"total\":300,\"input\":30,\"output\":120,\"reasoning\":30,\"cache\":{\"read\":120,\"write\":0}}"),
            makeSession(id: "child-b", parentID: "main", tokensJSON: "{\"total\":500,\"input\":50,\"output\":200,\"reasoning\":50,\"cache\":{\"read\":200,\"write\":0}}"),
            // Grandchild: subagent of a subagent (defensive; live data shows none).
            makeSession(id: "grand", parentID: "child-a", tokensJSON: "{\"total\":77,\"input\":7,\"output\":30,\"reasoning\":7,\"cache\":{\"read\":33,\"write\":0}}"),
        ]
        let group = state.sessionGroup(including: "main")
        #expect(group.first?.id == "main")
        #expect(Set(group.map(\.id)) == Set(["main", "child-a", "child-b", "grand"]))
        #expect(state.sessionGroup(including: "child-a").map(\.id) == ["child-a", "grand"])
    }

    @Test @MainActor func groupIsCycleSafe() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        // A mutual parentID cycle must terminate: neither session may be
        // appended twice or loop forever.
        state.sessions = [
            makeSession(id: "a", parentID: "b"),
            makeSession(id: "b", parentID: "a"),
        ]
        let group = state.sessionGroup(including: "a")
        #expect(group.count == 2)
        #expect(Set(group.map(\.id)) == Set(["a", "b"]))
    }

    @Test @MainActor func totalIncludesDescendantAggregates() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [
            makeSession(id: "main", tokensJSON: "{\"total\":100,\"input\":10,\"output\":40,\"reasoning\":10,\"cache\":{\"read\":40,\"write\":0}}"),
            makeSession(id: "child-a", parentID: "main", tokensJSON: "{\"total\":300,\"input\":30,\"output\":120,\"reasoning\":30,\"cache\":{\"read\":120,\"write\":0}}"),
            makeSession(id: "child-b", parentID: "main", tokensJSON: "{\"total\":500,\"input\":50,\"output\":200,\"reasoning\":50,\"cache\":{\"read\":200,\"write\":0}}"),
        ]
        #expect(state.sessionTotalTokens(sessionID: "main") == 900)
        // Unrelated sessions are never folded in.
        state.sessions.append(makeSession(id: "other", tokensJSON: "{\"total\":999,\"input\":9,\"output\":399,\"reasoning\":9,\"cache\":{\"read\":382,\"write\":0}}"))
        #expect(state.sessionTotalTokens(sessionID: "main") == 900)
    }

    @Test @MainActor func totalHidesWhenMainUnknownEvenWithSubagentData() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        // Main has no aggregate and a partial window: its own part is
        // unknowable, so the number hides even though a subagent has data.
        state.sessions = [
            makeSession(id: "main"),
            makeSession(id: "child-a", parentID: "main", tokensJSON: "{\"total\":300,\"input\":30,\"output\":120,\"reasoning\":30,\"cache\":{\"read\":120,\"write\":0}}"),
        ]
        state.hasMoreHistoryBySessionID["main"] = true
        #expect(state.sessionTotalTokens(sessionID: "main") == nil)
    }

    @Test @MainActor func mainWindowFallbackPlusSubagentAggregate() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [
            makeSession(id: "main"),
            makeSession(id: "child-a", parentID: "main", tokensJSON: "{\"total\":300,\"input\":30,\"output\":120,\"reasoning\":30,\"cache\":{\"read\":120,\"write\":0}}"),
        ]
        // Host omits the aggregate on main; the loaded window is complete,
        // so main's part comes from the window and the subagent from its
        // aggregate.
        state.messages = [
            MessageWithParts(
                info: Message(
                    id: "m1", sessionID: "main", role: "assistant", parentID: nil,
                    providerID: nil, modelID: nil, model: nil, error: nil,
                    time: .init(created: 0, completed: 1), finish: "stop",
                    tokens: try! JSONDecoder().decode(Message.TokenInfo.self, from:
                        "{\"total\":155,\"input\":150,\"output\":3,\"reasoning\":2}".data(using: .utf8)!),
                    cost: nil
                ),
                parts: []
            ),
        ]
        state.hasMoreHistoryBySessionID["main"] = false
        #expect(state.sessionTotalTokens(sessionID: "main") == 455)
    }

    @Test @MainActor func cacheHitRateIsComputedAcrossTheWholeTree() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [
            makeSession(id: "main", tokensJSON: "{\"total\":410,\"input\":100,\"output\":90,\"reasoning\":10,\"cache\":{\"read\":300,\"write\":0}}"),
            makeSession(id: "child-a", parentID: "main", tokensJSON: "{\"total\":500,\"input\":50,\"output\":90,\"reasoning\":10,\"cache\":{\"read\":450,\"write\":0}}"),
        ]
        // (300 + 450) / (100 + 50 + 300 + 450) = 750/900
        let rate = state.sessionCacheHitRate(sessionID: "main")
        #expect(rate != nil)
        #expect(abs(rate! - 750.0 / 900.0) < 1e-9)
    }

    @Test @MainActor func cacheHitRateHidesWhenMainUnknown() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: isolatedDefaults())
        state.sessions = [
            makeSession(id: "main"),
            makeSession(id: "child-a", parentID: "main", tokensJSON: "{\"total\":500,\"input\":50,\"output\":90,\"reasoning\":10,\"cache\":{\"read\":450,\"write\":0}}"),
        ]
        state.hasMoreHistoryBySessionID["main"] = true
        #expect(state.sessionCacheHitRate(sessionID: "main") == nil)
    }
}
