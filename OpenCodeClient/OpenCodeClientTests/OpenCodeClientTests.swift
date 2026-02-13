//
//  OpenCodeClientTests.swift
//  OpenCodeClientTests
//
//  Created by Yan Wang on 2/12/26.
//

import Foundation
import Testing
@testable import OpenCodeClient

// MARK: - Existing Tests

struct OpenCodeClientTests {

    @Test func defaultServerAddress() {
        #expect(APIClient.defaultServer == "localhost:4096")
    }

    @Test func sessionDecoding() throws {
        let json = """
        {"id":"s1","slug":"s1","projectID":"p1","directory":"/tmp","parentID":null,"title":"Test","version":"1","time":{"created":0,"updated":0},"share":null,"summary":null}
        """
        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(Session.self, from: data)
        #expect(session.id == "s1")
        #expect(session.title == "Test")
    }

    @Test func messageDecoding() throws {
        let json = """
        {"id":"m1","sessionID":"s1","role":"user","parentID":null,"model":{"providerID":"anthropic","modelID":"claude-3"},"time":{"created":0,"completed":null},"finish":null}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)
        #expect(message.id == "m1")
        #expect(message.isUser == true)
    }

    // Regression: server.connected event has no directory; SSEEvent.directory must be optional
    @Test func sseEventDecodingWithoutDirectory() throws {
        let json = """
        {"payload":{"type":"server.connected","properties":{}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.directory == nil)
        #expect(event.payload.type == "server.connected")
    }

    @Test func sseEventDecodingWithDirectory() throws {
        let json = """
        {"directory":"/path/to/workspace","payload":{"type":"message.updated","properties":{}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.directory == "/path/to/workspace")
        #expect(event.payload.type == "message.updated")
    }

    // handleSSEEvent depends on these event structures - document expected format
    @Test func sseEventSessionStatus() throws {
        let json = """
        {"payload":{"type":"session.status","properties":{"sessionID":"s1","status":{"type":"busy","attempt":1,"message":"Processing","next":null}}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "session.status")
        let props = event.payload.properties ?? [:]
        #expect((props["sessionID"]?.value as? String) == "s1")
        let statusObj = props["status"]?.value as? [String: Any]
        #expect(statusObj != nil)
        #expect((statusObj?["type"] as? String) == "busy")
    }

    @Test func sseEventPermissionAsked() throws {
        let json = """
        {"payload":{"type":"permission.asked","properties":{"sessionID":"s1","permissionID":"perm1","description":"Run command","tool":"run_terminal_cmd"}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "permission.asked")
        let props = event.payload.properties ?? [:]
        #expect((props["sessionID"]?.value as? String) == "s1")
        #expect((props["permissionID"]?.value as? String) == "perm1")
        #expect((props["description"]?.value as? String) == "Run command")
        #expect((props["tool"]?.value as? String) == "run_terminal_cmd")
    }

    @Test func sseEventTodoUpdated() throws {
        let json = """
        {"payload":{"type":"todo.updated","properties":{"sessionID":"s1","todos":[{"id":"t1","content":"Task 1","completed":false},{"id":"t2","content":"Task 2","completed":true}]}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "todo.updated")
        let props = event.payload.properties ?? [:]
        #expect((props["sessionID"]?.value as? String) == "s1")
        let todosObj = props["todos"]?.value
        #expect(JSONSerialization.isValidJSONObject(todosObj ?? []))
    }

    @Test func sseEventMessageUpdated() throws {
        let json = """
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","messageID":"m1"}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "message.updated")
        let props = event.payload.properties ?? [:]
        #expect((props["sessionID"]?.value as? String) == "s1")
    }

    // Think Streaming: message.part.updated with delta for typing effect
    @Test func sseEventMessagePartUpdatedWithDelta() throws {
        let json = """
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","messageID":"m1","delta":"Hello ","part":{"id":"p1","messageID":"m1","sessionID":"s1","type":"reasoning"}}}}
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEEvent.self, from: data)
        #expect(event.payload.type == "message.part.updated")
        let props = event.payload.properties ?? [:]
        #expect((props["sessionID"]?.value as? String) == "s1")
        #expect((props["delta"]?.value as? String) == "Hello ")
        let partObj = props["part"]?.value as? [String: Any]
        #expect(partObj != nil)
        #expect((partObj?["messageID"] as? String) == "m1")
        #expect((partObj?["id"] as? String) == "p1")
    }

    // Regression: Part.state can be String or object (ToolState); was causing loadMessages decode failure during thinking
    @Test func partDecodingWithStateAsString() throws {
        let partJson = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"read_file","callID":"c1","state":"pending","metadata":null,"files":null}
        """
        let data = partJson.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.stateDisplay == "pending")
        #expect(part.isTool == true)
    }

    @Test func partDecodingWithStateAsObject() throws {
        let partJson = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"read_file","callID":"c1","state":{"status":"running","input":{},"time":{"start":1700000000}},"metadata":null,"files":null}
        """
        let data = partJson.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.stateDisplay == "running")
    }

    @Test func partDecodingWithStateObjectWithTitle() throws {
        let partJson = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"run_terminal_cmd","callID":"c1","state":{"status":"completed","input":{},"output":"done","title":"Running command","metadata":{},"time":{"start":0,"end":1}},"metadata":null,"files":null}
        """
        let data = partJson.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.stateDisplay == "completed")
    }

    @Test func messageWithPartsDecodingWithToolStateObject() throws {
        let json = """
        {"info":{"id":"m1","sessionID":"s1","role":"assistant","parentID":null,"model":{"providerID":"anthropic","modelID":"claude-3"},"time":{"created":0,"completed":null},"finish":null},"parts":[{"id":"p1","messageID":"m1","sessionID":"s1","type":"text","text":"Hello","tool":null,"callID":null,"state":null,"metadata":null,"files":null},{"id":"p2","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"read_file","callID":"c1","state":{"status":"running","input":{},"time":{"start":0}},"metadata":null,"files":null}]}
        """
        let data = json.data(using: .utf8)!
        let msg = try JSONDecoder().decode(MessageWithParts.self, from: data)
        #expect(msg.parts.count == 2)
        #expect(msg.parts[0].stateDisplay == nil)
        #expect(msg.parts[1].stateDisplay == "running")
    }

    @Test func partFilePathsFromApplyPatch() throws {
        // patchText with "*** Add File: path" - path should be extracted
        let partJson = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"apply_patch","callID":"c1","state":{"status":"completed","input":{"patchText":"*** Begin Patch\\n*** Add File: research/deepseek-news-2026-02.md\\n+# content"},"metadata":{}},"metadata":null,"files":null}
        """
        let data = partJson.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation.contains("research/deepseek-news-2026-02.md"))
    }
}

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
}

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
        #expect(PathNormalizer.normalize("src/../app.swift") == "src/app.swift")
        #expect(PathNormalizer.normalize("a/../b/./c.txt") == "b/c.txt")
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

// MARK: - AppError Tests

struct AppErrorTests {
    
    @Test func appErrorConnectionFailed() {
        let error = AppError.connectionFailed("Network unreachable")
        #expect(error.localizedDescription.contains("连接失败"))
        #expect(error.isConnectionError == true)
        #expect(error.isRecoverable == true)
    }
    
    @Test func appErrorUnauthorized() {
        let error = AppError.unauthorized
        #expect(error.localizedDescription.contains("未授权"))
        #expect(error.isRecoverable == true)
    }
    
    @Test func appErrorFromFileNotFound() {
        let error = AppError.fileNotFound("/path/to/file.swift")
        #expect(error.localizedDescription.contains("文件不存在"))
        #expect(error.isRecoverable == false)
    }
    
    @Test func appErrorFromNSError() {
        let nsError = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "Request timed out"])
        let appError = AppError.from(nsError)
        if case .connectionFailed = appError {
            #expect(Bool(true))
        } else {
            Issue.record("Expected connectionFailed error")
        }
    }
    
    @Test func appErrorEquality() {
        let e1 = AppError.connectionFailed("test")
        let e2 = AppError.connectionFailed("test")
        let e3 = AppError.connectionFailed("other")
        #expect(e1 == e2)
        #expect(e1 != e3)
    }
}

// MARK: - LayoutConstants Tests

struct LayoutConstantsTests {
    
    @Test func splitViewFractions() {
        #expect(LayoutConstants.SplitView.sidebarWidthFraction == 1.0 / 6.0)
        #expect(LayoutConstants.SplitView.previewWidthFraction == 5.0 / 12.0)
        #expect(LayoutConstants.SplitView.chatWidthFraction == 5.0 / 12.0)
    }
    
    @Test func splitViewFractionsSum() {
        let total = LayoutConstants.SplitView.sidebarWidthFraction 
                  + LayoutConstants.SplitView.previewWidthFraction 
                  + LayoutConstants.SplitView.chatWidthFraction
        #expect(total == 1.0)
    }
    
    @Test func splitViewBoundFractions() {
        #expect(LayoutConstants.SplitView.sidebarMinFraction < LayoutConstants.SplitView.sidebarWidthFraction)
        #expect(LayoutConstants.SplitView.sidebarMaxFraction > LayoutConstants.SplitView.sidebarWidthFraction)
        #expect(LayoutConstants.SplitView.paneMinFraction < LayoutConstants.SplitView.previewWidthFraction)
        #expect(LayoutConstants.SplitView.paneMaxFraction > LayoutConstants.SplitView.previewWidthFraction)
    }
    
    @Test func animationDurations() {
        #expect(LayoutConstants.Animation.shortDuration < LayoutConstants.Animation.defaultDuration)
        #expect(LayoutConstants.Animation.defaultDuration < LayoutConstants.Animation.longDuration)
    }
    
    @Test func spacingValues() {
        #expect(LayoutConstants.Spacing.compact < LayoutConstants.Spacing.standard)
        #expect(LayoutConstants.Spacing.standard < LayoutConstants.Spacing.comfortable)
        #expect(LayoutConstants.Spacing.comfortable < LayoutConstants.Spacing.spacious)
    }
}

// MARK: - Speech Recognition Defaults

struct SpeechRecognitionDefaultsTests {

    @Test @MainActor func speechRecognitionDefaultPromptAndTerminology() async {
        // Clear stored values so AppState falls back to defaults
        UserDefaults.standard.removeObject(forKey: "aiBuilderCustomPrompt")
        UserDefaults.standard.removeObject(forKey: "aiBuilderTerminology")
        let state = AppState()
        #expect(state.aiBuilderCustomPrompt.contains("snake_case"))
        #expect(state.aiBuilderCustomPrompt.contains("lowercase"))
        #expect(state.aiBuilderTerminology == "adhoc_jobs, life_consulting, survey_sessions, thought_review")
    }

    @Test @MainActor func speechRecognitionPersistence() async {
        let state = AppState()
        state.aiBuilderCustomPrompt = "test prompt"
        state.aiBuilderTerminology = "foo, bar"
        #expect(state.aiBuilderCustomPrompt == "test prompt")
        #expect(state.aiBuilderTerminology == "foo, bar")
        // Restore defaults for other tests
        UserDefaults.standard.removeObject(forKey: "aiBuilderCustomPrompt")
        UserDefaults.standard.removeObject(forKey: "aiBuilderTerminology")
    }
}

// MARK: - APIConstants Tests

struct APIConstantsTests {
    
    @Test func defaultServer() {
        #expect(APIConstants.defaultServer == "localhost:4096")
    }
    
    @Test func sseEndpoint() {
        #expect(APIConstants.sseEndpoint == "/global/event")
    }
    
    @Test func healthEndpoint() {
        #expect(APIConstants.healthEndpoint == "/global/health")
    }
    
    @Test func timeoutValues() {
        #expect(APIConstants.Timeout.connection > 0)
        #expect(APIConstants.Timeout.request > APIConstants.Timeout.connection)
    }
}

// MARK: - SSH Tunnel Tests

struct SSHTunnelTests {

    @Test func sshTunnelConfigDefault() {
        let config = SSHTunnelConfig()
        #expect(config.isEnabled == false)
        #expect(config.host == "")
        #expect(config.port == 22)
        #expect(config.username == "")
        #expect(config.remotePort == 18080)
    }

    @Test func sshTunnelConfigValidation() {
        var config = SSHTunnelConfig()
        #expect(config.isValid == false)
        
        config.host = "example.com"
        config.username = "user"
        #expect(config.isValid == true)
        
        config.port = 0
        #expect(config.isValid == false)
        
        config.port = 22
        config.remotePort = 0
        #expect(config.isValid == false)
    }

    @Test func sshTunnelConfigCoding() throws {
        var config = SSHTunnelConfig()
        config.isEnabled = true
        config.host = "vps.example.com"
        config.port = 2222
        config.username = "testuser"
        config.remotePort = 8080
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SSHTunnelConfig.self, from: data)
        
        #expect(decoded.isEnabled == true)
        #expect(decoded.host == "vps.example.com")
        #expect(decoded.port == 2222)
        #expect(decoded.username == "testuser")
        #expect(decoded.remotePort == 8080)
    }

    @Test func sshTunnelConfigEquatable() {
        let c1 = SSHTunnelConfig(isEnabled: true, host: "a.com", port: 22, username: "u", remotePort: 18080)
        let c2 = SSHTunnelConfig(isEnabled: true, host: "a.com", port: 22, username: "u", remotePort: 18080)
        let c3 = SSHTunnelConfig(isEnabled: false, host: "a.com", port: 22, username: "u", remotePort: 18080)
        
        #expect(c1 == c2)
        #expect(c1 != c3)
    }

    @Test func sshConnectionStatusEquatable() {
        #expect(SSHConnectionStatus.disconnected == SSHConnectionStatus.disconnected)
        #expect(SSHConnectionStatus.connecting == SSHConnectionStatus.connecting)
        #expect(SSHConnectionStatus.connected == SSHConnectionStatus.connected)
        #expect(SSHConnectionStatus.error("msg") == SSHConnectionStatus.error("msg"))
        #expect(SSHConnectionStatus.error("a") != SSHConnectionStatus.error("b"))
        #expect(SSHConnectionStatus.disconnected != SSHConnectionStatus.connected)
    }

    @Test func sshErrorDescriptions() {
        #expect(SSHError.connectionFailed("timeout").errorDescription?.contains("timeout") == true)
        #expect(SSHError.authenticationFailed.errorDescription?.contains("Authentication") == true)
        #expect(SSHError.keyNotFound.errorDescription?.contains("key not found") == true)
        #expect(SSHError.invalidKeyFormat.errorDescription?.contains("Invalid") == true)
        #expect(SSHError.tunnelFailed("x").errorDescription?.contains("Tunnel") == true)
        #expect(SSHError.hostKeyMismatch(expected: "a", got: "b").errorDescription?.contains("Host key mismatch") == true)
    }

    @Test @MainActor func sshTunnelManagerInitialStatus() {
        let manager = SSHTunnelManager()
        #expect(manager.status == .disconnected)
        #expect(manager.config.isEnabled == false)
    }

    @Test @MainActor func sshTunnelManagerConfigPersistence() {
        let manager = SSHTunnelManager()
        manager.config.host = "test.example.com"
        manager.config.port = 2222
        manager.config.username = "testuser"
        manager.config.remotePort = 9999
        
        // Create a new manager to test persistence
        let manager2 = SSHTunnelManager()
        #expect(manager2.config.host == "test.example.com")
        #expect(manager2.config.port == 2222)
        #expect(manager2.config.username == "testuser")
        #expect(manager2.config.remotePort == 9999)
        
        // Clean up
        manager2.config = .default
    }
}

// MARK: - SSH Key Manager Tests

struct SSHKeyManagerTests {

    @Test func sshKeyGenerationProducesValidKeys() throws {
        let (privateKey, publicKey) = try SSHKeyManager.generateKeyPair()
        
        #expect(!privateKey.isEmpty)
        #expect(!publicKey.isEmpty)
        #expect(publicKey.hasPrefix("ssh-ed25519 "))
        #expect(publicKey.contains("opencode-ios"))
    }

    @Test func sshKeyPublicKeyStorage() {
        SSHKeyManager.deleteKeyPair()  // Clean start
        
        let testKey = "ssh-ed25519 AAAA... test-key"
        SSHKeyManager.savePublicKey(testKey)
        
        #expect(SSHKeyManager.getPublicKey() == testKey)
        
        // Clean up
        SSHKeyManager.deleteKeyPair()
        #expect(SSHKeyManager.getPublicKey() == nil)
    }

    @Test func sshKeyDeleteKeyPair() throws {
        let (_, publicKey) = try SSHKeyManager.generateKeyPair()
        SSHKeyManager.savePublicKey(publicKey)
        
        // Just verify delete doesn't crash and clears public key
        SSHKeyManager.deleteKeyPair()
        
        #expect(SSHKeyManager.getPublicKey() == nil)
    }

    @Test func sshKeyRotateGeneratesNewKey() throws {
        // Ensure we have a key first
        _ = try SSHKeyManager.ensureKeyPair()
        let publicKey1 = SSHKeyManager.getPublicKey() ?? ""
        
        let publicKey2 = try SSHKeyManager.rotateKey()
        
        #expect(publicKey1 != publicKey2)
        #expect(SSHKeyManager.getPublicKey() == publicKey2)
        
        // Clean up
        SSHKeyManager.deleteKeyPair()
    }
}

struct SSHKnownHostStoreTests {

    @Test func knownHostTrustAndClear() throws {
        let host = "unit-test.example.com"
        let port = 2222
        SSHKnownHostStore.clear(host: host, port: port)

        let (_, publicKey) = try SSHKeyManager.generateKeyPair()
        SSHKnownHostStore.trust(host: host, port: port, openSSHKey: publicKey)

        #expect(SSHKnownHostStore.trustedOpenSSHKey(host: host, port: port) == publicKey)
        #expect((SSHKnownHostStore.fingerprint(host: host, port: port) ?? "").hasPrefix("SHA256:"))

        SSHKnownHostStore.clear(host: host, port: port)
        #expect(SSHKnownHostStore.trustedOpenSSHKey(host: host, port: port) == nil)
    }
}
