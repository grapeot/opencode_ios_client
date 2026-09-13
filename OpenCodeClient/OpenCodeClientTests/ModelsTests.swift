//
//  ModelsTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

// MARK: - Message & Role Tests

struct MessageRoleTests {

    @Test func messageIsAssistant() throws {
        let json = """
        {"id":"m2","sessionID":"s1","role":"assistant","parentID":null,"model":{"providerID":"openai","modelID":"gpt-4"},"time":{"created":100,"completed":200},"finish":"stop"}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)
        #expect(message.isAssistant == true)
        #expect(message.isUser == false)
        #expect(message.finish == "stop")
    }

    @Test func messageWithNilModel() throws {
        let json = """
        {"id":"m3","sessionID":"s1","role":"user","parentID":"m2","model":null,"time":{"created":50,"completed":null},"finish":null}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)
        #expect(message.model == nil)
        #expect(message.parentID == "m2")
    }
}

// MARK: - Message Throughput Tests

struct MessageThroughputTests {

    private func makeMessage(_ extra: String) throws -> Message {
        let json = """
        {"id":"m1","sessionID":"s1","role":"assistant","parentID":null,"model":{"providerID":"openai","modelID":"gpt-4"},\(extra)}
        """
        return try JSONDecoder().decode(Message.self, from: json.data(using: .utf8)!)
    }

    @Test func throughputBasic() throws {
        // 2000ms window, 200 output tokens -> 100 t/s
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":3000},\"tokens\":{\"output\":200,\"reasoning\":0}")
        #expect(m.throughputExcludingToolSeconds(0) == 100.0)
    }

    @Test func throughputIncludesReasoning() throws {
        // 3000ms window, 200 output + 100 reasoning = 300 tokens -> 100 t/s
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":4000},\"tokens\":{\"output\":200,\"reasoning\":100}")
        #expect(m.generatedTokens == 300)
        #expect(m.throughputExcludingToolSeconds(0) == 100.0)
    }

    @Test func throughputNilWhileRunning() throws {
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":null},\"tokens\":{\"output\":200}")
        #expect(m.throughputExcludingToolSeconds(0) == nil)
    }

    @Test func throughputNilZeroWindow() throws {
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":1000},\"tokens\":{\"output\":200}")
        #expect(m.throughputExcludingToolSeconds(0) == nil)
    }

    @Test func throughputNilNoTokens() throws {
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":3000},\"tokens\":{\"output\":0,\"reasoning\":0}")
        #expect(m.generatedTokens == 0)
        #expect(m.throughputExcludingToolSeconds(0) == nil)
    }

    @Test func throughputLabelInteger() throws {
        // 1460 tokens / 10s = 146 t/s -> "146 t/s"
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":11000},\"tokens\":{\"output\":1460}")
        #expect(m.throughputLabelExcludingToolSeconds(0) == "146 t/s")
    }

    @Test func throughputLabelDecimal() throws {
        // 83 tokens / 10s = 8.3 t/s -> "8.3 t/s"
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":11000},\"tokens\":{\"output\":83}")
        #expect(m.throughputLabelExcludingToolSeconds(0) == "8.3 t/s")
    }

    @Test func throughputLabelNilWhenUncomputed() throws {
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":null}")
        #expect(m.throughputLabelExcludingToolSeconds(0) == nil)
    }

    @Test func throughputNilWhenTokensMissing() throws {
        // Valid 2s window but no tokens field at all -> generatedTokens 0 -> nil
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":3000}")
        #expect(m.generatedTokens == 0)
        #expect(m.throughputExcludingToolSeconds(0) == nil)
    }

    @Test func throughputNilNegativeWindow() throws {
        // completed before created (bad data) -> nil, never a negative rate
        let m = try makeMessage("\"time\":{\"created\":3000,\"completed\":1000},\"tokens\":{\"output\":200}")
        #expect(m.throughputExcludingToolSeconds(0) == nil)
    }

    @Test func throughputExcludesToolSeconds() throws {
        // Real case: 529 tokens, 56.157s step window of which a write tool ran
        // 48.345s -> 67.7 t/s instead of 9.4 t/s.
        let m = try makeMessage("\"time\":{\"created\":0,\"completed\":56157},\"tokens\":{\"output\":529}")
        let value = m.throughputExcludingToolSeconds(48.345)
        #expect(abs((value ?? -1) - 67.72) < 0.05)
        // Zero tool time is the raw step window: 529 / 56.157s = 9.42 t/s.
        #expect(abs((m.throughputExcludingToolSeconds(0) ?? -1) - 9.42) < 0.01)
    }

    @Test func throughputFallsBackWhenToolTimeExceedsWindow() throws {
        // Clock skew can make tool time swallow the window; never divide by a
        // non-positive window, fall back to the raw step window.
        let m = try makeMessage("\"time\":{\"created\":0,\"completed\":5000},\"tokens\":{\"output\":500}")
        #expect(m.throughputExcludingToolSeconds(9.0) == 100.0)
    }

    @Test func throughputExcludingToolSecondsNilWhileRunning() throws {
        let m = try makeMessage("\"time\":{\"created\":1000,\"completed\":null},\"tokens\":{\"output\":200}")
        #expect(m.throughputExcludingToolSeconds(1.0) == nil)
    }

    @Test func throughputLabelExcludesToolSeconds() throws {
        let m = try makeMessage("\"time\":{\"created\":0,\"completed\":56157},\"tokens\":{\"output\":529}")
        #expect(m.throughputLabelExcludingToolSeconds(48.345) == "68 t/s")
    }
}

// MARK: - Tool timing extraction tests

struct MessageToolTimingTests {

    private func messageWithParts(_ parts: String) throws -> MessageWithParts {
        let json = """
        {"info":{"id":"m1","sessionID":"s1","role":"assistant","time":{"created":0,"completed":60000},"tokens":{"output":600}},"parts":[\(parts)]}
        """
        return try JSONDecoder().decode(MessageWithParts.self, from: json.data(using: .utf8)!)
    }

    @Test func sumsToolStateTime() throws {
        // Two completed tools: 48s + 5s = 53s. Step window 60s -> 7s of
        // generation, so 600 tokens / 7s = 85.7 t/s.
        let m = try messageWithParts("""
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","tool":"write","state":{"status":"completed","time":{"start":1000,"end":49000},"input":{"path":"a"},"output":"ok"}},
        {"id":"p2","messageID":"m1","sessionID":"s1","type":"tool","tool":"read","state":{"status":"completed","time":{"start":50000,"end":55000}}}
        """)
        #expect(abs(m.toolRunSeconds - 53.0) < 0.001)
        #expect(abs((m.info.throughputExcludingToolSeconds(m.toolRunSeconds) ?? -1) - (600.0 / 7.0)) < 0.01)
    }

    @Test func toolRunSecondsZeroWithoutStateTime() throws {
        // Older payloads carry no state.time; the correction must degrade to the
        // raw step window instead of dropping tool time it cannot see.
        let m = try messageWithParts("""
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","tool":"write","state":{"status":"completed","input":{"path":"a"},"output":"ok"}},
        {"id":"p2","messageID":"m1","sessionID":"s1","type":"text","text":"hi"}
        """)
        #expect(m.toolRunSeconds == 0)
        #expect(m.info.throughputExcludingToolSeconds(m.toolRunSeconds) == 10.0)
    }

    @Test func runningToolWithoutEndDoesNotCount() throws {
        // start but no end -> still running -> no measurable tool time yet.
        let m = try messageWithParts("""
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash","state":{"status":"running","time":{"start":1000},"input":{"command":"sleep 60"}}}
        """)
        #expect(m.toolRunSeconds == 0)
    }
}

// MARK: - ContextUsage Throughput Aggregation Tests

struct ContextUsageThroughputTests {

    private func message(
        _ id: String,
        _ role: String,
        _ created: Int,
        _ completed: String,
        _ output: Int,
        _ reasoning: Int = 0
    ) throws -> MessageWithParts {
        let json = """
        {"info":{"id":"\(id)","sessionID":"ses_x","role":"\(role)","model":{"providerID":"openai","modelID":"gpt-4"},"time":{"created":\(created),"completed":\(completed)},"tokens":{"output":\(output),"reasoning":\(reasoning)}},"parts":[]}
        """
        return try JSONDecoder().decode(MessageWithParts.self, from: json.data(using: .utf8)!)
    }

    @Test @MainActor
    func aggregatesThroughputAndExcludesRunning() async throws {
        let state = AppState()
        let session = try JSONDecoder().decode(Session.self, from: """
        {"id":"ses_x","slug":"ses_x","projectID":"p1","directory":"/workspace","title":"S","version":"1","time":{"created":1,"updated":2}}
        """.data(using: .utf8)!)
        state.sessions = [session]
        state.currentSessionID = "ses_x"
        state.providerModelsIndex["openai/gpt-4"] = ProviderModel(
            id: "gpt-4", name: "G", providerID: "openai",
            limit: ProviderModelLimit(context: 100_000, input: nil, output: nil)
        )

        // user (ignored) + A (2s, 200 out) + B (3s, 300 out + 100 reasoning)
        // + C (still running, no completed -> excluded).
        state.messages = [
            try message("mU", "user", 9000, "null", 0, 0),
            try message("mA", "assistant", 1000, "3000", 200, 0),
            try message("mB", "assistant", 4000, "7000", 300, 100),
            try message("mC", "assistant", 8000, "null", 500, 0),
        ]

        let snap = state.contextUsageSnapshot
        #expect(snap != nil)
        #expect(snap?.totalOutputTokens == 600)
        #expect(snap?.totalGenerationSeconds == 5.0)
        #expect(snap?.averageThroughput == 120.0)
    }

    @Test @MainActor
    func excludesToolTimeFromAggregate() async throws {
        let state = AppState()
        let session = try JSONDecoder().decode(Session.self, from: """
        {"id":"ses_x","slug":"ses_x","projectID":"p1","directory":"/workspace","title":"S","version":"1","time":{"created":1,"updated":2}}
        """.data(using: .utf8)!)
        state.sessions = [session]
        state.currentSessionID = "ses_x"
        state.providerModelsIndex["openai/gpt-4"] = ProviderModel(
            id: "gpt-4", name: "G", providerID: "openai",
            limit: ProviderModelLimit(context: 100_000, input: nil, output: nil)
        )

        // A: 2s step, 200 out, no tools. B: 60s step, 600 out, 53s inside tools.
        // Generation time = 2 + 7 = 9s, tokens = 800 -> 88.9 t/s. Counting the
        // raw step windows would report 12.9 t/s.
        let withTool = try JSONDecoder().decode(MessageWithParts.self, from: """
        {"info":{"id":"mB","sessionID":"ses_x","role":"assistant","model":{"providerID":"openai","modelID":"gpt-4"},"time":{"created":0,"completed":60000},"tokens":{"output":600,"reasoning":0}},"parts":[{"id":"p1","messageID":"mB","sessionID":"ses_x","type":"tool","tool":"write","state":{"status":"completed","time":{"start":1000,"end":54000},"input":{"path":"a"}}}]}
        """.data(using: .utf8)!)
        state.messages = [
            try message("mA", "assistant", 1000, "3000", 200, 0),
            withTool,
        ]

        let snap = state.contextUsageSnapshot
        #expect(snap?.totalOutputTokens == 800)
        #expect(abs((snap?.totalGenerationSeconds ?? -1) - 9.0) < 0.001)
        #expect(abs((snap?.averageThroughput ?? -1) - (800.0 / 9.0)) < 0.01)
    }

    @Test @MainActor
    func snapshotNilWithoutAnyCompletedStep() async throws {
        let state = AppState()
        let session = try JSONDecoder().decode(Session.self, from: """
        {"id":"ses_x","slug":"ses_x","projectID":"p1","directory":"/workspace","title":"S","version":"1","time":{"created":1,"updated":2}}
        """.data(using: .utf8)!)
        state.sessions = [session]
        state.currentSessionID = "ses_x"
        state.providerModelsIndex["openai/gpt-4"] = ProviderModel(
            id: "gpt-4", name: "G", providerID: "openai",
            limit: ProviderModelLimit(context: 100_000, input: nil, output: nil)
        )
        // Only an in-flight assistant (no completed) -> no LLM time to divide by.
        state.messages = [try message("mA", "assistant", 1000, "null", 200, 0)]

        let snap = state.contextUsageSnapshot
        #expect(snap?.averageThroughput == nil)
        #expect(snap?.totalGenerationSeconds == nil)
    }
}

// MARK: - StepTiming (SSE-derived decoding) Tests

struct StepTimingTests {

    private func timing(
        _ first: TimeInterval?,
        _ last: TimeInterval?,
        _ output: Int?
    ) -> MessageStore.StepTiming {
        MessageStore.StepTiming(
            sessionID: "s1",
            firstVisibleAt: first.map { Date(timeIntervalSinceReferenceDate: $0) },
            lastVisibleAt: last.map { Date(timeIntervalSinceReferenceDate: $0) },
            outputTokens: output
        )
    }

    @Test func decodeOverVisibleWindow() {
        // 100 output tokens over (4.7 - 3.2) = 1.5s.
        let t = timing(3.2, 4.7, 100)
        #expect(abs((t.decode ?? -1) - (100.0 / 1.5)) < 0.01)
        #expect(t.decodeLabel == "67 t/s decoding")
    }

    @Test func decodeEndsAtLastVisibleTokenNotStepFinish() {
        // Generated tokens stopped at 4.0s; the step-finish part only arrived
        // after the step's tool ran. The window must end at the last token.
        let t = timing(3.2, 4.0, 100)
        #expect(abs((t.decode ?? -1) - 125.0) < 0.01)
    }

    @Test func decodeCoversToolCallOnlyStep() {
        // No text at all: the visible window is the tool-call JSON input stream.
        let t = timing(1.0, 3.0, 200)
        #expect(abs((t.decode ?? -1) - 100.0) < 0.01)
    }

    @Test func decodeLabelDecimalBelowTen() {
        // 15 output over 3.0s -> 5.0 t/s -> one decimal
        let t = timing(0, 3.0, 15)
        #expect(t.decodeLabel == "5.0 t/s decoding")
    }

    @Test func decodeNilMissingEitherEndOrTokens() {
        #expect(timing(3.2, 4.7, nil).decode == nil)
        #expect(timing(3.2, 4.7, 0).decode == nil)
        #expect(timing(nil, 4.7, 100).decode == nil)
        // Only one visible token: no measurable window, so no number.
        #expect(timing(3.2, nil, 100).decode == nil)
    }

    @Test func decodeNilOnNonPositiveWindow() {
        // end before or equal to the first visible token -> no window
        #expect(timing(3.2, 3.2, 100).decode == nil)
        #expect(timing(3.2, 3.1, 100).decode == nil)
    }
}

// MARK: - ModelPreset Tests

struct ModelPresetTests {

    @Test func modelPresetId() {
        let preset = ModelPreset(displayName: "Claude", providerID: "anthropic", modelID: "claude-3")
        #expect(preset.id == "anthropic/claude-3")
        #expect(preset.displayName == "Claude")
    }

    @Test func modelPresetDecoding() throws {
        let json = """
        {"displayName":"GPT-4","providerID":"openai","modelID":"gpt-4-turbo"}
        """
        let data = json.data(using: .utf8)!
        let preset = try JSONDecoder().decode(ModelPreset.self, from: data)
        #expect(preset.id == "openai/gpt-4-turbo")
    }
}

// MARK: - Session Tests

struct SessionDecodingTests {

    @Test func sessionWithShareAndSummary() throws {
        let json = """
        {"id":"s2","slug":"s2","projectID":"p1","directory":"/workspace","parentID":"s1","title":"Feature Branch","version":"2","time":{"created":1000,"updated":2000},"share":{"url":"https://example.com/share/s2"},"summary":{"additions":42,"deletions":10,"files":3}}
        """
        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(Session.self, from: data)
        #expect(session.parentID == "s1")
        #expect(session.share?.url == "https://example.com/share/s2")
        #expect(session.summary?.additions == 42)
        #expect(session.summary?.deletions == 10)
        #expect(session.summary?.files == 3)
    }

    @Test func sessionStatusDecoding() throws {
        let json = """
        {"type":"busy","attempt":2,"message":"Processing...","next":null}
        """
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(SessionStatus.self, from: data)
        #expect(status.type == "busy")
        #expect(status.attempt == 2)
        #expect(status.message == "Processing...")
    }

    @Test func sessionStatusIdleDecoding() throws {
        let json = """
        {"type":"idle","attempt":null,"message":null,"next":null}
        """
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(SessionStatus.self, from: data)
        #expect(status.type == "idle")
        #expect(status.attempt == nil)
    }
}

// MARK: - Part Type Check Tests

struct PartTypeTests {

    private func makePart(type: String, tool: String? = nil, text: String? = nil) throws -> Part {
        let toolStr = tool.map { "\"\($0)\"" } ?? "null"
        let textStr = text.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"\(type)","text":\(textStr),"tool":\(toolStr),"callID":null,"state":null,"metadata":null,"files":null}
        """
        return try JSONDecoder().decode(Part.self, from: json.data(using: .utf8)!)
    }

    @Test func partIsText() throws {
        let part = try makePart(type: "text", text: "Hello world")
        #expect(part.isText == true)
        #expect(part.isReasoning == false)
        #expect(part.isTool == false)
        #expect(part.isPatch == false)
        #expect(part.isStepStart == false)
        #expect(part.isStepFinish == false)
    }

    @Test func partIsReasoning() throws {
        let part = try makePart(type: "reasoning", text: "Let me think...")
        #expect(part.isReasoning == true)
        #expect(part.isText == false)
    }

    @Test func partIsTool() throws {
        let part = try makePart(type: "tool", tool: "bash")
        #expect(part.isTool == true)
        #expect(part.isText == false)
    }

    @Test func partIsPatch() throws {
        let part = try makePart(type: "patch")
        #expect(part.isPatch == true)
    }

    @Test func partIsStepStart() throws {
        let part = try makePart(type: "step-start")
        #expect(part.isStepStart == true)
        #expect(part.isStepFinish == false)
    }

    @Test func partIsStepFinish() throws {
        let part = try makePart(type: "step-finish")
        #expect(part.isStepFinish == true)
        #expect(part.isStepStart == false)
    }
}

// MARK: - File Path Navigation Tests

struct FilePathNavigationTests {

    @Test func filePathsFromFilesArray() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"patch","text":null,"tool":null,"callID":null,"state":null,"metadata":null,"files":[{"path":"src/main.swift","additions":5,"deletions":2,"status":"modified"},{"path":"src/utils.swift","additions":10,"deletions":0,"status":"added"}]}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation.count == 2)
        #expect(part.filePathsForNavigation.contains("src/main.swift"))
        #expect(part.filePathsForNavigation.contains("src/utils.swift"))
    }

    @Test func filePathsFromMetadata() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"read_file","callID":"c1","state":null,"metadata":{"path":"docs/README.md","title":null,"input":null},"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation == ["docs/README.md"])
    }

    @Test func filePathsFromStateInputPath() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"write_file","callID":"c1","state":{"status":"completed","input":{"path":"src/new_file.swift","content":"// new"},"metadata":{}},"metadata":null,"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation.contains("src/new_file.swift"))
    }

    @Test func filePathsDeduplicated() throws {
        // state.input.path same as metadata.path — should not duplicate
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"edit_file","callID":"c1","state":{"status":"completed","input":{"path":"src/app.swift"},"metadata":{}},"metadata":{"path":"src/app.swift","title":null,"input":null},"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation.count == 1)
        #expect(part.filePathsForNavigation[0] == "src/app.swift")
    }

    @Test func filePathsFromUpdateFilePatch() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"apply_patch","callID":"c1","state":{"status":"completed","input":{"patchText":"*** Begin Patch\\n*** Update File: lib/parser.py\\n@@ -10,3 +10,5 @@\\n+import os"},"metadata":{}},"metadata":null,"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation.contains("lib/parser.py"))
    }

    @Test func filePathsEmptyWhenNone() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"text","text":"Hello","tool":null,"callID":null,"state":null,"metadata":null,"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation.isEmpty)
    }

    // Path normalization: a/, b/ prefix, #L, :line:col suffixes stripped (via filePathsForNavigation)
    @Test func filePathsNormalizedFromMetadata() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"read_file","callID":"c1","state":null,"metadata":{"path":"a/src/app.swift","title":null,"input":null},"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation == ["src/app.swift"])
    }

    @Test func filePathsNormalizedStripHashAndLine() throws {
        // # and everything after -> stripped first; :line:col at end -> stripped
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"read_file","callID":"c1","state":null,"metadata":{"path":"docs/readme.md#L42","title":null,"input":null},"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation == ["docs/readme.md"])
    }

    @Test func filePathsNormalizedStripLineColSuffix() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"read_file","callID":"c1","state":null,"metadata":{"path":"src/app.swift:42:10","title":null,"input":null},"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation == ["src/app.swift"])
    }
}

// MARK: - PathNormalizer (Code Review 1.4)

struct PathNormalizerTests {

    @Test func stripsABPrefix() {
        #expect(PathNormalizer.normalize("a/src/app.swift") == "src/app.swift")
        #expect(PathNormalizer.normalize("b/docs/readme.md") == "docs/readme.md")
    }

    @Test func stripsHashAndSuffix() {
        #expect(PathNormalizer.normalize("docs/readme.md#L42") == "docs/readme.md")
    }

    @Test func stripsLineColSuffix() {
        #expect(PathNormalizer.normalize("src/app.swift:42:10") == "src/app.swift")
        #expect(PathNormalizer.normalize("lib/parser.py:10") == "lib/parser.py")
    }

    @Test func trimsWhitespace() {
        #expect(PathNormalizer.normalize("  src/app.swift  ") == "src/app.swift")
    }

    @Test func leavesPlainPathUnchanged() {
        #expect(PathNormalizer.normalize("src/main.swift") == "src/main.swift")
    }

    @Test func stripsDotDotSegments() {
        #expect(PathNormalizer.normalize("../secrets.txt") == "secrets.txt")
        #expect(PathNormalizer.normalize("src/../app.swift") == "app.swift")
        #expect(PathNormalizer.normalize("a/../b/./c.txt") == "b/c.txt")
    }

    @Test func foldsParentDirectorySegmentsForMarkdownAssets() {
        #expect(
            PathNormalizer.normalize("docs/reports/../assets/timeline_40d.png")
                == "docs/assets/timeline_40d.png"
        )
        #expect(
            PathNormalizer.resolveWorkspaceRelativePath(
                "docs/reports/../assets/timeline_40d.png",
                workspaceDirectory: "/Users/test/workspace"
            ) == "docs/assets/timeline_40d.png"
        )
    }

    @Test func resolvesWorkspaceRelativeFromAbsolutePath() {
        let dir = "/Users/test/workspace"
        let abs = "/Users/test/workspace/docs/readme.md#L42"
        #expect(PathNormalizer.resolveWorkspaceRelativePath(abs, workspaceDirectory: dir) == "docs/readme.md")
    }

    @Test func resolvesWorkspaceRelativeKeepsRelativePath() {
        let dir = "/Users/test/workspace"
        let rel = "docs/readme.md"
        #expect(PathNormalizer.resolveWorkspaceRelativePath(rel, workspaceDirectory: dir) == "docs/readme.md")
    }

    @Test func resolvesWorkspaceRelativeDecodesPercentEncoding() {
        let dir = "/Users/test/workspace"
        let abs = "/Users/test/workspace/src%2Fapp.swift"
        #expect(PathNormalizer.resolveWorkspaceRelativePath(abs, workspaceDirectory: dir) == "src/app.swift")
    }

    @Test func resolvesWorkspaceRelativePreservesExternalHostPath() {
        let dir = "/Users/grapeot/co/knowledge_working"
        let absWithoutSlash = "Users/grapeot/co/vatic/agentic_trading/docs/slides_260617/outline.md"
        #expect(
            PathNormalizer.resolveWorkspaceRelativePath(absWithoutSlash, workspaceDirectory: dir)
                == "/Users/grapeot/co/vatic/agentic_trading/docs/slides_260617/outline.md"
        )
    }
}

// MARK: - PartStateBridge Tests

struct PartStateBridgeTests {

    @Test func stateWithOutputAndTitle() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"bash","callID":"c1","state":{"status":"completed","input":{"command":"ls -la"},"output":"file1 file2","title":"Listing files","metadata":{}},"metadata":null,"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.toolReason == "Listing files")
        #expect(part.toolInputSummary == "ls -la")
        #expect(part.toolOutput == "file1 file2")
    }

    @Test func stateWithOutputDirectly() throws {
        // When state has output directly at top level
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"custom","callID":"c1","state":{"status":"running","input":{},"output":"partial result","title":"Fetching data"},"metadata":null,"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.toolReason == "Fetching data")
        #expect(part.toolOutput == "partial result")
    }

    @Test func stateWithStringInput() throws {
        let json = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"eval","callID":"c1","state":{"status":"completed","input":"print('hello')"},"metadata":null,"files":null}
        """
        let data = json.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.toolInputSummary == "print('hello')")
        // No path extraction from string input
        #expect(part.filePathsForNavigation.isEmpty)
    }
}

// MARK: - API Response Model Tests

struct APIResponseModelTests {

    @Test func fileContentTextDecoding() throws {
        let json = """
        {"type":"text","content":"# Hello World"}
        """
        let data = json.data(using: .utf8)!
        let fc = try JSONDecoder().decode(FileContent.self, from: data)
        #expect(fc.text == "# Hello World")
        #expect(fc.type == "text")
    }

    @Test func fileContentBinaryDecoding() throws {
        let json = """
        {"type":"binary","content":null}
        """
        let data = json.data(using: .utf8)!
        let fc = try JSONDecoder().decode(FileContent.self, from: data)
        #expect(fc.text == nil)
        #expect(fc.type == "binary")
    }

    @Test func fileNodeDecoding() throws {
        let json = """
        {"name":"src","path":"src","absolute":"/workspace/src","type":"directory","ignored":false}
        """
        let data = json.data(using: .utf8)!
        let node = try JSONDecoder().decode(FileNode.self, from: data)
        #expect(node.id == "src")
        #expect(node.type == "directory")
        #expect(node.absolute == "/workspace/src")
        #expect(node.ignored == false)
    }

    @Test func fileDiffDecoding() throws {
        let json = """
        {"file":"main.swift","before":"old","after":"new","additions":5,"deletions":3,"status":"modified"}
        """
        let data = json.data(using: .utf8)!
        let diff = try JSONDecoder().decode(FileDiff.self, from: data)
        #expect(diff.id == "main.swift")
        #expect(diff.additions == 5)
        #expect(diff.deletions == 3)
        #expect(diff.status == "modified")
    }

    @Test func fileDiffEquality() {
        let d1 = FileDiff(file: "a.swift", before: "", after: "x", additions: 1, deletions: 0, status: nil)
        let d2 = FileDiff(file: "a.swift", before: "", after: "y", additions: 2, deletions: 0, status: nil)
        #expect(d1 == d2) // equality is by file name only
    }

    @Test func healthResponseDecoding() throws {
        let json = """
        {"healthy":true,"version":"1.2.3"}
        """
        let data = json.data(using: .utf8)!
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        #expect(health.healthy == true)
        #expect(health.version == "1.2.3")
    }

    @Test func projectDecoding() throws {
        let json = """
        {"id":"abc123","worktree":"/Users/me/co/knowledge_working","vcs":"git","icon":{"color":"pink"},"time":{"created":1770951645865,"updated":1771000000360},"sandboxes":[]}
        """
        let data = json.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: data)
        #expect(project.id == "abc123")
        #expect(project.worktree == "/Users/me/co/knowledge_working")
        #expect(project.displayName == "knowledge_working")
    }

    @Test func fileStatusEntryDecoding() throws {
        let json = """
        {"path":"src/app.swift","status":"modified"}
        """
        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(FileStatusEntry.self, from: data)
        #expect(entry.path == "src/app.swift")
        #expect(entry.status == "modified")
    }
}

// MARK: - Agent Info Tests

struct AgentInfoTests {

    @Test func agentInfoDecoding() throws {
        let json = """
        {"name":"Sisyphus (Ultraworker)","description":"Powerful orchestrator","mode":"primary","hidden":false,"native":false}
        """
        let data = json.data(using: .utf8)!
        let agent = try JSONDecoder().decode(AgentInfo.self, from: data)
        #expect(agent.id == "Sisyphus (Ultraworker)")
        #expect(agent.name == "Sisyphus (Ultraworker)")
        #expect(agent.description == "Powerful orchestrator")
        #expect(agent.mode == "primary")
        #expect(agent.hidden == false)
        #expect(agent.isVisible == true)
    }

    @Test func agentInfoShortName() throws {
        let agent1 = AgentInfo(name: "Sisyphus (Ultraworker)", description: nil, mode: nil, hidden: nil, native: nil)
        #expect(agent1.shortName == "Sisyphus")
        
        let agent2 = AgentInfo(name: "build", description: nil, mode: nil, hidden: nil, native: nil)
        #expect(agent2.shortName == "build")
        
        let agent3 = AgentInfo(name: "explore", description: nil, mode: nil, hidden: nil, native: nil)
        #expect(agent3.shortName == "explore")
    }

    @Test func agentInfoHiddenNotVisible() throws {
        let agent = AgentInfo(name: "hidden_agent", description: nil, mode: nil, hidden: true, native: nil)
        #expect(agent.isVisible == false)
    }

    @Test func agentInfoArrayDecoding() throws {
        let json = """
        [
            {"name":"Sisyphus","description":"Orchestrator","mode":"primary","hidden":false},
            {"name":"build","description":"Default agent","mode":"subagent","hidden":true},
            {"name":"plan","description":"Planning mode","mode":"subagent","hidden":false}
        ]
        """
        let data = json.data(using: .utf8)!
        let agents = try JSONDecoder().decode([AgentInfo].self, from: data)
        #expect(agents.count == 3)
        #expect(agents[0].name == "Sisyphus")
        #expect(agents[1].hidden == true)
        #expect(agents[2].isVisible == false)
    }

    @Test func agentInfoMinimalFields() throws {
        let json = """
        {"name":"minimal"}
        """
        let data = json.data(using: .utf8)!
        let agent = try JSONDecoder().decode(AgentInfo.self, from: data)
        #expect(agent.name == "minimal")
        #expect(agent.description == nil)
        #expect(agent.mode == nil)
        #expect(agent.hidden == nil)
        #expect(agent.isVisible == true)
    }

    @Test func agentInfoModeFiltering() throws {
        let primary = AgentInfo(name: "Sisyphus", description: nil, mode: "primary", hidden: false, native: nil)
        let all = AgentInfo(name: "Prometheus", description: nil, mode: "all", hidden: false, native: nil)
        let subagent = AgentInfo(name: "explore", description: nil, mode: "subagent", hidden: false, native: nil)
        let hiddenPrimary = AgentInfo(name: "hidden", description: nil, mode: "primary", hidden: true, native: nil)
        let noMode = AgentInfo(name: "noMode", description: nil, mode: nil, hidden: false, native: nil)
        
        #expect(primary.isVisible == true)
        #expect(all.isVisible == true)
        #expect(subagent.isVisible == false)
        #expect(hiddenPrimary.isVisible == false)
        #expect(noMode.isVisible == true)
    }
}

// MARK: - ModelPreset ShortName Tests

struct ModelPresetShortNameTests {
    
    @Test func deepseekShortName() {
        let preset = ModelPreset(displayName: "DeepSeek", providerID: "deepseek", modelID: "deepseek-v4-flash")
        #expect(preset.shortName == "DeepSeek")
    }

    @Test func deepseekLocalShortName() {
        let preset = ModelPreset(displayName: "DeepSeek Local", providerID: "ds4", modelID: "deepseek-v4-flash")
        #expect(preset.shortName == "DS-L")
    }

    @Test func ollamaGLMShortName() {
        let preset = ModelPreset(displayName: "Ollama GLM 5.2", providerID: "ollama-cloud", modelID: "glm-5.2")
        #expect(preset.shortName == "OGLM-5.2")
    }
    
    @Test func geminiShortName() {
        let preset = ModelPreset(displayName: "Gemini 3.1 Pro", providerID: "google", modelID: "gemini-3.1-pro")
        #expect(preset.shortName == "Gemini")
    }
    
    @Test func gptShortName() {
        let preset = ModelPreset(displayName: "GPT-5.3 Codex", providerID: "openai", modelID: "gpt-5.3-codex")
        #expect(preset.shortName == "GPT")
    }

    @Test func gptTerraFastShortName() {
        let terra = ModelPreset(displayName: "GPT-5.6 Terra Fast", providerID: "openai", modelID: "gpt-5.6-terra-fast")

        #expect(terra.shortName == "GPT-TF")
    }

    @Test func gptLunaShortName() {
        let luna = ModelPreset(displayName: "GPT-5.6 Luna", providerID: "openai", modelID: "gpt-5.6-luna")

        #expect(luna.shortName == "GPT-L")
    }

    @Test func grok46ShortName() {
        let preset = ModelPreset(displayName: "Grok 4.6", providerID: "xai", modelID: "grok-4.6")
        #expect(preset.shortName == "Grok")
    }

    @Test func unknownModelFallsBackToDisplayName() {
        let preset = ModelPreset(displayName: "Custom Model", providerID: "custom", modelID: "custom-1")
        #expect(preset.shortName == "Custom Model")
    }
}

struct QuestionModelTests {

    @Test func questionOptionDecoding() throws {
        let json = """
        {"label":"React Native","description":"Cross-platform mobile framework"}
        """
        let data = json.data(using: .utf8)!
        let opt = try JSONDecoder().decode(QuestionOption.self, from: data)
        #expect(opt.label == "React Native")
        #expect(opt.description == "Cross-platform mobile framework")
        #expect(opt.id == "React Native")
    }

    @Test func questionInfoDecoding() throws {
        let json = """
        {"question":"Which framework?","header":"Framework","options":[{"label":"SwiftUI","description":"Native iOS"}],"multiple":true,"custom":false}
        """
        let data = json.data(using: .utf8)!
        let info = try JSONDecoder().decode(QuestionInfo.self, from: data)
        #expect(info.question == "Which framework?")
        #expect(info.header == "Framework")
        #expect(info.options.count == 1)
        #expect(info.allowMultiple == true)
        #expect(info.allowCustom == false)
    }

    @Test func questionInfoDefaultValues() throws {
        let json = """
        {"question":"Pick one","header":"Choice","options":[]}
        """
        let data = json.data(using: .utf8)!
        let info = try JSONDecoder().decode(QuestionInfo.self, from: data)
        #expect(info.allowMultiple == false)
        #expect(info.allowCustom == true)
    }

    @Test func questionRequestDecoding() throws {
        let json = """
        {"id":"question_abc","sessionID":"s1","questions":[{"question":"Pick one","header":"Q1","options":[{"label":"A","description":"Option A"}]}],"tool":{"messageID":"m1","callID":"c1"}}
        """
        let data = json.data(using: .utf8)!
        let req = try JSONDecoder().decode(QuestionRequest.self, from: data)
        #expect(req.id == "question_abc")
        #expect(req.sessionID == "s1")
        #expect(req.questions.count == 1)
        #expect(req.tool?.messageID == "m1")
        #expect(req.tool?.callID == "c1")
    }

    @Test func questionRequestWithoutTool() throws {
        let json = """
        {"id":"question_xyz","sessionID":"s2","questions":[{"question":"Yes or no?","header":"Confirm","options":[{"label":"Yes","description":"Proceed"},{"label":"No","description":"Cancel"}]}]}
        """
        let data = json.data(using: .utf8)!
        let req = try JSONDecoder().decode(QuestionRequest.self, from: data)
        #expect(req.tool == nil)
        #expect(req.questions[0].options.count == 2)
    }
}

struct QuestionSSEEventTests {

    @Test func sseEventQuestionAsked() throws {
        let json = """
        {"payload":{"type":"question.asked","properties":{"id":"question_1","sessionID":"s1","questions":[{"question":"Pick one","header":"Choice","options":[{"label":"A","description":"Option A"},{"label":"B","description":"Option B"}],"multiple":false}]}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "question.asked")
        let props = event.payload.properties ?? [:]
        #expect((props["id"]?.value as? String) == "question_1")
        #expect((props["sessionID"]?.value as? String) == "s1")
    }

    @Test func sseEventQuestionReplied() throws {
        let json = """
        {"payload":{"type":"question.replied","properties":{"sessionID":"s1","requestID":"question_1","answers":[["A"]]}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "question.replied")
        let props = event.payload.properties ?? [:]
        #expect((props["requestID"]?.value as? String) == "question_1")
    }

    @Test func sseEventQuestionRejected() throws {
        let json = """
        {"payload":{"type":"question.rejected","properties":{"sessionID":"s1","requestID":"question_1"}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "question.rejected")
        let props = event.payload.properties ?? [:]
        #expect((props["requestID"]?.value as? String) == "question_1")
    }
}
