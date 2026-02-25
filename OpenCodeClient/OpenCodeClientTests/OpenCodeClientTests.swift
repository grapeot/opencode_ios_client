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
        #expect(APIClient.defaultServer == "127.0.0.1:4096")
    }

    @Test @MainActor func migrateLegacyDefaultServerAddress() {
        let key = "serverURL"
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set("localhost:4096", forKey: key)
        let state = AppState()
        #expect(state.serverURL == "127.0.0.1:4096")
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

    @Test func messageDecodingWithoutTokenTotal() throws {
        let json = """
        {"id":"m2","sessionID":"s1","role":"assistant","parentID":"m1","providerID":"openai","modelID":"gpt-5.2","time":{"created":0,"completed":1},"finish":"stop","tokens":{"input":10,"output":2,"reasoning":3,"cache":{"read":0,"write":0}}}
        """
        let data = json.data(using: .utf8)!
        let message = try JSONDecoder().decode(Message.self, from: data)
        #expect(message.isAssistant == true)
        #expect(message.tokens?.input == 10)
        #expect(message.tokens?.output == 2)
        #expect(message.tokens?.reasoning == 3)
        #expect(message.tokens?.total == 15)
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

    @Test func partDecodingTodoFromMetadataWithObjectInput() throws {
        let partJson = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"todowrite","callID":"c1","state":{"status":"completed","input":{},"output":"[{\\"content\\":\\"Write tests\\",\\"status\\":\\"pending\\",\\"priority\\":\\"high\\"}]","title":"1 todo","metadata":{"todos":[{"content":"Write tests","status":"pending","priority":"high"}],"input":{"todos":[{"content":"Write tests","status":"pending","priority":"high"}]},"description":"todo update"},"time":{"start":0,"end":1}},"metadata":{"input":{"todos":[{"content":"Write tests","status":"pending","priority":"high"}]},"todos":[{"content":"Write tests","status":"pending","priority":"high"}]},"files":null}
        """
        let data = partJson.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.toolTodos.count == 1)
        #expect(part.toolTodos.first?.content == "Write tests")
        #expect(part.toolTodos.first?.id.isEmpty == false)
    }

    @Test func todoItemDecodingLegacyCompletedShape() throws {
        let json = """
        {"content":"Task 1","completed":true}
        """
        let data = json.data(using: .utf8)!
        let item = try JSONDecoder().decode(TodoItem.self, from: data)
        #expect(item.content == "Task 1")
        #expect(item.status == "completed")
        #expect(item.priority == "medium")
        #expect(item.id.isEmpty == false)
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
            time: .init(created: 0, updated: updated),
            share: nil,
            summary: nil
        )
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
        #expect(error.localizedDescription == L10n.errorMessage(.errorConnectionFailed, "Network unreachable"))
        #expect(error.isConnectionError == true)
        #expect(error.isRecoverable == true)
    }
    
    @Test func appErrorUnauthorized() {
        let error = AppError.unauthorized
        #expect(error.localizedDescription == L10n.t(.errorUnauthorized))
        #expect(error.isRecoverable == true)
    }
    
    @Test func appErrorFromFileNotFound() {
        let error = AppError.fileNotFound("/path/to/file.swift")
        #expect(error.localizedDescription == L10n.errorMessage(.errorFileNotFound, "/path/to/file.swift"))
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

struct LocalizationTests {

    @Test func localizationKeyCoverage() {
        #expect(L10n.missingEnglishKeys.isEmpty)
        #expect(L10n.missingChineseKeys.isEmpty)
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
        #expect(APIConstants.defaultServer == "127.0.0.1:4096")
    }

    @Test func legacyDefaultServer() {
        #expect(APIConstants.legacyDefaultServer == "localhost:4096")
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

struct MessageRenderingHeuristicTests {

    @Test func markdownHeuristicDetectsPlainText() {
        #expect(MessageRowView.hasMarkdownSyntax("this is a plain sentence") == false)
    }

    @Test func markdownHeuristicDetectsHeader() {
        #expect(MessageRowView.hasMarkdownSyntax("# Title") == true)
    }

    @Test func markdownHeuristicDetectsCodeFence() {
        #expect(MessageRowView.hasMarkdownSyntax("```swift\nprint(1)\n```") == true)
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

    @Test func ensureKeyPairRepairsMissingPublicKeyFromPrivateKey() throws {
        SSHKeyManager.deleteKeyPair()
        defer { SSHKeyManager.deleteKeyPair() }

        let (privateKey, _) = try SSHKeyManager.generateKeyPair()
        SSHKeyManager.savePrivateKey(privateKey)
        SSHKeyManager.savePublicKey("   ")

        let repaired = try SSHKeyManager.ensureKeyPair()

        #expect(!repaired.isEmpty)
        #expect(repaired.hasPrefix("ssh-ed25519 "))
        #expect(SSHKeyManager.getPublicKey() == repaired)
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
    
    @Test func opusShortName() {
        let preset = ModelPreset(displayName: "Opus 4.6", providerID: "anthropic", modelID: "claude-opus-4-6")
        #expect(preset.shortName == "Opus")
    }
    
    @Test func sonnetShortName() {
        let preset = ModelPreset(displayName: "Sonnet 4.6", providerID: "anthropic", modelID: "claude-sonnet-4-6")
        #expect(preset.shortName == "Sonnet")
    }
    
    @Test func geminiShortName() {
        let preset = ModelPreset(displayName: "Gemini 3.1 Pro", providerID: "google", modelID: "gemini-3.1-pro")
        #expect(preset.shortName == "Gemini")
    }
    
    @Test func gptShortName() {
        let preset = ModelPreset(displayName: "GPT-5.3 Codex", providerID: "openai", modelID: "gpt-5.3-codex")
        #expect(preset.shortName == "GPT")
    }
    
    @Test func unknownModelFallsBackToDisplayName() {
        let preset = ModelPreset(displayName: "Custom Model", providerID: "custom", modelID: "custom-1")
        #expect(preset.shortName == "Custom Model")
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

    @Test @MainActor func filteredSessionsHidesArchivedByDefault() {
        let state = AppState()
        state.showArchivedSessions = false
        
        let s1 = makeSession(id: "s1", archived: nil)
        let s2 = makeSession(id: "s2", archived: 123)
        state.sessions = [s1, s2]
        
        #expect(state.sortedSessions.count == 1)
        #expect(state.sortedSessions.first?.id == "s1")
    }

    @Test @MainActor func filteredSessionsShowsArchivedWhenEnabled() {
        let state = AppState()
        state.showArchivedSessions = true
        
        let s1 = makeSession(id: "s1", archived: nil)
        let s2 = makeSession(id: "s2", archived: 123)
        state.sessions = [s1, s2]
        
        #expect(state.sortedSessions.count == 2)
    }

    private func makeSession(id: String, archived: Int?) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: "Title",
            version: "1",
            time: .init(created: 0, updated: 0, archived: archived),
            share: nil,
            summary: nil
        )
    }
}
