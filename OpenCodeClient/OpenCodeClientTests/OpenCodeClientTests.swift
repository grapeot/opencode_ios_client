//
//  OpenCodeClientTests.swift
//  OpenCodeClientTests
//
//  Created by Yan Wang on 2/12/26.
//

import Foundation
import SwiftUI
import Testing
@testable import OpenCodeClient

// MARK: - Existing Tests

struct OpenCodeClientTests {

    @Test func defaultServerAddress() {
        #expect(APIClient.defaultServer == "127.0.0.1:4096")
    }

    @Test func correctMalformedServerURL() {
        // Malformed "host://host:port" from iOS .textContentType(.URL) autocorrect
        #expect(AppState.correctMalformedServerURL("quantum.tail63c3c5.ts.net://quantum.tail63c3c5.ts.net:4096") == "quantum.tail63c3c5.ts.net:4096")
        #expect(AppState.correctMalformedServerURL("host.example.com://host.example.com:8080") == "host.example.com:8080")
        // Legitimate URLs unchanged
        #expect(AppState.correctMalformedServerURL("http://quantum.tail63c3c5.ts.net:4096") == nil)
        #expect(AppState.correctMalformedServerURL("quantum.tail63c3c5.ts.net:4096") == nil)
        #expect(AppState.correctMalformedServerURL("127.0.0.1:4096") == nil)
    }

    @Test func ensureServerURLHasScheme() {
        #expect(AppState.ensureServerURLHasScheme("quantum.tail63c3c5.ts.net:4096") == "http://quantum.tail63c3c5.ts.net:4096")
        #expect(AppState.ensureServerURLHasScheme("127.0.0.1:4096") == "http://127.0.0.1:4096")
        #expect(AppState.ensureServerURLHasScheme("http://quantum.tail63c3c5.ts.net:4096") == nil)
        #expect(AppState.ensureServerURLHasScheme("https://example.com:443") == nil)
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

    @Test func testImageExtensionDetection() {
        #expect(ImageFileUtils.isImage("image.png") == true)
        #expect(ImageFileUtils.isImage("photo.jpg") == true)
        #expect(ImageFileUtils.isImage("photo.jpeg") == true)
        #expect(ImageFileUtils.isImage("animation.gif") == true)
        #expect(ImageFileUtils.isImage("asset.webp") == true)
        #expect(ImageFileUtils.isImage("capture.heic") == true)

        #expect(ImageFileUtils.isImage("file.swift") == false)
        #expect(ImageFileUtils.isImage("README.md") == false)
        #expect(ImageFileUtils.isImage("notes.txt") == false)
        #expect(ImageFileUtils.isImage("payload.json") == false)

        #expect(ImageFileUtils.isImage("ICON.PNG") == true)
        #expect(ImageFileUtils.isImage("photo.Jpg") == true)
        #expect(ImageFileUtils.isImage("archive.tar.gz") == false)
        #expect(ImageFileUtils.isImage("photo.edit.png") == true)
    }

    @Test func testBase64ImageDecoding() {
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5WZfQAAAAASUVORK5CYII="
        let data = Data(base64Encoded: base64PNG)
        #expect(data != nil)
        if let data {
            #expect(UIImage(data: data) != nil)
        }
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
            time: .init(created: 0, updated: updated, archived: nil),
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
}

struct WorkspaceMarkdownImageProviderTests {

    @Test func imageBaseURLResolvesParentDirectoryAssetPath() {
        let baseURL = WorkspaceMarkdownImageProvider.imageBaseURL(
            markdownFilePath: "adhoc_jobs/health_quantification/docs/reports/health_synthesis_report_2026-04-09.md"
        )
        let imageURL = URL(string: "../assets/timeline_40d.png", relativeTo: baseURL)
        #expect(
            WorkspaceMarkdownImageProvider.workspaceRelativePath(from: imageURL)
                == "adhoc_jobs/health_quantification/docs/assets/timeline_40d.png"
        )
    }

    @Test func decodesBase64DataURL() {
        let url = URL(string: "data:image/png;base64,aGVsbG8=")
        let data = WorkspaceMarkdownImageProvider.decodeDataURL(url)
        #expect(data == Data("hello".utf8))
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

    @Test func messageListSpacing() {
        #expect(LayoutConstants.MessageList.spacing == 20)
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

struct AIBuildersAudioClientTests {

    @Test func normalizedBaseURLAddsHTTPSWhenMissing() {
        let url = AIBuildersAudioClient.normalizedBaseURL(from: "space.ai-builders.com/backend")
        #expect(url.absoluteString == "https://space.ai-builders.com/backend")
    }

    @Test func realtimeWebSocketURLPreservesHostAndSwitchesScheme() throws {
        let baseURL = URL(string: "https://space.ai-builders.com/backend")!
        let websocketURL = try AIBuildersAudioClient.realtimeWebSocketURL(
            baseURL: baseURL,
            relativePath: "/v1/audio/realtime/ws?ticket=abc123"
        )
        #expect(websocketURL.absoluteString == "wss://space.ai-builders.com/v1/audio/realtime/ws?ticket=abc123")
    }

    @Test func realtimeWebSocketURLWithMountPath() throws {
        let baseURL = URL(string: "https://space.ai-builders.com/backend")!
        let websocketURL = try AIBuildersAudioClient.realtimeWebSocketURL(
            baseURL: baseURL,
            relativePath: "/backend/v1/audio/realtime/ws?ticket=abc123"
        )
        #expect(websocketURL.absoluteString == "wss://space.ai-builders.com/backend/v1/audio/realtime/ws?ticket=abc123")
    }

    @Test func buildAPIURLPreservesMountPath() throws {
        let baseWithMount = URL(string: "https://space.ai-builders.com/backend")!
        let url = AIBuildersAudioClient.buildAPIURL(base: baseWithMount, path: "/v1/audio/realtime/sessions")
        #expect(url?.absoluteString == "https://space.ai-builders.com/backend/v1/audio/realtime/sessions")
    }

    @Test func buildAPIURLWithoutMountPath() throws {
        let baseNoMount = URL(string: "https://space.ai-builders.com")!
        let url = AIBuildersAudioClient.buildAPIURL(base: baseNoMount, path: "/v1/audio/realtime/sessions")
        #expect(url?.absoluteString == "https://space.ai-builders.com/v1/audio/realtime/sessions")
    }

    @Test func mergedSpeechInputOmitsLeadingSpaceForEmptyPrefix() {
        #expect(ChatTabView.mergedSpeechInput(prefix: "", transcript: " hello world ") == "hello world")
    }

    @Test func mergedSpeechInputKeepsSeparatorForExistingInput() {
        #expect(ChatTabView.mergedSpeechInput(prefix: "Existing draft", transcript: "partial") == "Existing draft partial")
    }

    @Test func chatComposerReturnUsesSystemDuringMarkedTextComposition() {
        #expect(ChatComposerKeyAction.action(for: "\n", hasMarkedText: true, isShiftReturn: false) == .system)
    }

    @Test func chatComposerPlainReturnInsertsNewlineWhenNoMarkedText() {
        #expect(ChatComposerKeyAction.action(for: "\n", hasMarkedText: false, isShiftReturn: false) == .insertNewline)
    }

    @Test func chatComposerShiftReturnInsertsNewlineWhenNoMarkedText() {
        #expect(ChatComposerKeyAction.action(for: "\n", hasMarkedText: false, isShiftReturn: true) == .insertNewline)
    }

    @Test func chatComposerNonReturnLeavesSystemHandling() {
        #expect(ChatComposerKeyAction.action(for: "x", hasMarkedText: false, isShiftReturn: false) == .system)
    }

    @Test func chatComposerSendGateRejectsMarkedText() {
        #expect(ChatComposerSendGate.canSend(text: "nihao", isSending: false, hasMarkedText: true) == false)
    }

    @Test func chatComposerSendGateRejectsWhitespaceAndActiveSend() {
        #expect(ChatComposerSendGate.canSend(text: "   ", isSending: false, hasMarkedText: false) == false)
        #expect(ChatComposerSendGate.canSend(text: "hello", isSending: true, hasMarkedText: false) == false)
    }

    @Test func chatComposerSendGateAllowsCommittedText() {
        #expect(ChatComposerSendGate.canSend(text: "hello", isSending: false, hasMarkedText: false) == true)
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

struct ChatScrollBehaviorTests {

    @Test func shouldAutoScrollWhenBottomMarkerIsVisible() {
        #expect(
            ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: 640,
                viewportHeight: 600,
                threshold: 80
            ) == true
        )
    }

    @Test func shouldAutoScrollWhenBottomMarkerIsNearViewportBottom() {
        #expect(
            ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: 675,
                viewportHeight: 600,
                threshold: 80
            ) == true
        )
    }

    @Test func shouldNotAutoScrollWhenUserHasScrolledAwayFromBottom() {
        #expect(
            ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: 760,
                viewportHeight: 600,
                threshold: 80
            ) == false
        )
    }
}

struct SessionListEdgeSwipeBehaviorTests {

    @Test func opensForLeftEdgeSwipeWithStrongHorizontalTravel() {
        #expect(
            SessionListEdgeSwipeBehavior.shouldOpenSessionList(
                startLocation: CGPoint(x: 12, y: 180),
                translation: CGSize(width: 120, height: 18)
            ) == true
        )
    }

    @Test func ignoresSwipeThatStartsAwayFromLeftEdge() {
        #expect(
            SessionListEdgeSwipeBehavior.shouldOpenSessionList(
                startLocation: CGPoint(x: 60, y: 180),
                translation: CGSize(width: 120, height: 12)
            ) == false
        )
    }

    @Test func ignoresMostlyVerticalDrag() {
        #expect(
            SessionListEdgeSwipeBehavior.shouldOpenSessionList(
                startLocation: CGPoint(x: 8, y: 180),
                translation: CGSize(width: 110, height: 90)
            ) == false
        )
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

struct ModelSelectionPersistenceTests {
    @Test @MainActor func legacyGLM51SelectionMapsToCurrentTurboPreset() {
        let sessionID = "session-glm"
        let defaultsKey = "selectedModelBySession"
        let legacySelection = [sessionID: "zai-coding-plan/glm-5.1"]
        let originalData = UserDefaults.standard.data(forKey: defaultsKey)

        defer {
            if let originalData {
                UserDefaults.standard.set(originalData, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }

        let encoded = try! JSONEncoder().encode(legacySelection)
        UserDefaults.standard.set(encoded, forKey: defaultsKey)

        let state = AppState()
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
        #expect(state.modelPresets[state.selectedModelIndex].displayName == "GLM-5-turbo")
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
        state.showArchivedSessions = false
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

    @Test @MainActor func archivedFilteringMatchesBetweenSidebarSessionsAndSessionTree() {
        let state = AppState()
        state.showArchivedSessions = false
        state.sessions = [
            makeSession(id: "active-root", updated: 100),
            makeSession(id: "active-child", parentID: "active-root", updated: 90),
            makeSession(id: "archived-root", updated: 80, archived: 1_000),
            makeSession(id: "archived-child", parentID: "active-root", updated: 70, archived: 2_000),
        ]

        #expect(state.sidebarSessions.map(\.id) == ["active-root"])
        #expect(state.sessionTree.count == 1)
        #expect(state.sessionTree[0].session.id == "active-root")
        #expect(state.sessionTree[0].children.map(\.session.id) == ["active-child"])
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

actor MockAPIClient: APIClientProtocol {
    var configuredBaseURL: String?
    var configuredUsername: String?
    var configuredPassword: String?

    var healthResult = HealthResponse(healthy: true, version: "test-version")
    var healthError: Error?
    var sessionsResult: [Session] = []
    var sessionsByLimit: [Int: [Session]] = [:]
    var sessionLimitRequests: [Int] = []
    var createSessionResult = Session(
        id: "created-session",
        slug: "created-session",
        projectID: "p1",
        directory: "/tmp",
        parentID: nil,
        title: "Created",
        version: "1",
        time: .init(created: 1, updated: 1, archived: nil),
        share: nil,
        summary: nil
    )
    var forkSessionResult = Session(
        id: "forked-session",
        slug: "forked-session",
        projectID: "p1",
        directory: "/tmp",
        parentID: "original-session",
        title: "Original (fork #1)",
        version: "1",
        time: .init(created: 2, updated: 2, archived: nil),
        share: nil,
        summary: nil
    )
    var forkSessionError: Error?
    var forkSessionCalls: [(String, String?)] = []
    var messagesResult: [MessageWithParts] = []
    var messagesCallCount = 0
    var promptError: Error?
    var deletedSessionIDs: [String] = []
    var updateSessionCalls: [(String, String)] = []
    var sessionDiffResult: [FileDiff] = []
    var sessionDiffCallCount = 0

    func setHealthError(_ error: Error?) {
        healthError = error
    }

    func setSessionsResult(_ sessions: [Session]) {
        sessionsResult = sessions
    }

    func setSessionsResult(_ sessions: [Session], forLimit limit: Int) {
        sessionsByLimit[limit] = sessions
    }

    func setCreateSessionResult(_ session: Session) {
        createSessionResult = session
    }

    func setMessagesResult(_ messages: [MessageWithParts]) {
        messagesResult = messages
    }

    func setSessionDiffResult(_ diffs: [FileDiff]) {
        sessionDiffResult = diffs
    }

    func setPromptError(_ error: Error?) {
        promptError = error
    }

    func setForkSessionResult(_ session: Session) {
        forkSessionResult = session
    }

    func setForkSessionError(_ error: Error?) {
        forkSessionError = error
    }

    func configure(baseURL: String, username: String?, password: String?) {
        configuredBaseURL = baseURL
        configuredUsername = username
        configuredPassword = password
    }

    func health() async throws -> HealthResponse {
        if let healthError { throw healthError }
        return healthResult
    }

    func projects() async throws -> [Project] { [] }
    func projectCurrent() async throws -> Project? { nil }
    func sessions(directory: String?, limit: Int) async throws -> [Session] {
        sessionLimitRequests.append(limit)
        return sessionsByLimit[limit] ?? sessionsResult
    }
    func createSession(title: String?) async throws -> Session { createSessionResult }

    func updateSession(sessionID: String, title: String) async throws -> Session {
        updateSessionCalls.append((sessionID, title))
        return Session(
            id: sessionID,
            slug: sessionID,
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: title,
            version: "1",
            time: .init(created: 1, updated: 1, archived: nil),
            share: nil,
            summary: nil
        )
    }

    func deleteSession(sessionID: String) async throws {
        deletedSessionIDs.append(sessionID)
    }

    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] {
        messagesCallCount += 1
        return messagesResult
    }

    func promptAsync(sessionID: String, text: String, agent: String, model: Message.ModelInfo?) async throws {
        if let promptError { throw promptError }
    }

    func abort(sessionID: String) async throws {}
    func sessionStatus() async throws -> [String: SessionStatus] { [:] }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
    func pendingQuestions() async throws -> [QuestionRequest] { [] }
    func replyQuestion(requestID: String, answers: [[String]]) async throws {}
    func rejectQuestion(requestID: String) async throws {}
    func providers() async throws -> ProvidersResponse {
        try JSONDecoder().decode(ProvidersResponse.self, from: Data("{\"providers\":[]}".utf8))
    }
    func agents() async throws -> [AgentInfo] { [] }
    func sessionDiff(sessionID: String) async throws -> [FileDiff] {
        sessionDiffCallCount += 1
        return sessionDiffResult
    }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] { [] }
    func fileList(path: String) async throws -> [FileNode] { [] }
    func fileContent(path: String) async throws -> FileContent { FileContent(type: "text", content: "") }
    func findFile(query: String, limit: Int) async throws -> [String] { [] }
    func fileStatus() async throws -> [FileStatusEntry] { [] }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session {
        forkSessionCalls.append((sessionID, messageID))
        if let forkSessionError { throw forkSessionError }
        return forkSessionResult
    }
}

actor MockSSEClient: SSEClientProtocol {
    var stream = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.finish()
    }

    func connect(baseURL: String, username: String?, password: String?) -> AsyncThrowingStream<SSEEvent, Error> {
        stream
    }
}

struct AppStateFlowTests {
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
        let firstPageChildren = (0..<99).map { index in
            Self.makeSession(id: "child-\(index)", parentID: "root-1", updated: 99 - index)
        }
        let secondPageChildren = (0..<99).map { index in
            Self.makeSession(id: "child-\(index)", parentID: "root-1", updated: 99 - index)
        }

        await apiClient.setSessionsResult([
            Self.makeSession(id: "root-1", updated: 100),
        ] + firstPageChildren, forLimit: 100)
        await apiClient.setSessionsResult([
            Self.makeSession(id: "root-2", updated: 110),
            Self.makeSession(id: "root-1", updated: 100),
        ] + secondPageChildren, forLimit: 200)

        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true

        await state.loadSessions()
        #expect(state.sidebarSessions.map(\.id) == ["root-1"])
        #expect(state.canLoadMoreSessions == true)

        await state.loadMoreSessions()

        #expect(await apiClient.sessionLimitRequests == [100, 200])
        #expect(state.sidebarSessions.map(\.id) == ["root-2", "root-1"])
        #expect(state.canLoadMoreSessions == false)
    }

    @Test @MainActor func loadMoreSessionsPreservesChildHierarchyInCanonicalSessionTree() async {
        let apiClient = MockAPIClient()
        let fillerChildren = (0..<97).map { index in
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
        ] + fillerChildren, forLimit: 100)
        await apiClient.setSessionsResult([
            Self.makeSession(id: "root-2", updated: 110),
            Self.makeSession(id: "root-1", updated: 100),
            Self.makeSession(id: "child-1", parentID: "root-1", updated: 95),
            Self.makeSession(id: "grandchild-1", parentID: "child-1", updated: 90),
        ] + fillerChildren, forLimit: 200)

        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.showArchivedSessions = false

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

    @Test @MainActor func sendMessageRollsBackOptimisticMessageOnFailure() async {
        let apiClient = MockAPIClient()
        await apiClient.setPromptError(APIError.invalidURL)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"

        let succeeded = await state.sendMessage("hello")

        #expect(succeeded == false)
        #expect(state.messages.isEmpty)
        #expect(state.sendError?.isEmpty == false)
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

    @Test @MainActor func loadMessagesDedupesOptimisticUserRowWhenPersistedTextNormalizesWhitespace() async {
        let apiClient = MockAPIClient()
        let now = Int(Date().timeIntervalSince1970 * 1000)
        await apiClient.setMessagesResult([
            Self.makeMessageRow(
                messageID: "m-user",
                sessionID: "s1",
                role: "user",
                text: "hello world",
                created: now,
                completed: now
            ),
            Self.makeMessageRow(messageID: "m-assistant", sessionID: "s1", text: "reply")
        ])
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.currentSessionID = "s1"
        state.sessionStatuses["s1"] = SessionStatus(type: "busy", attempt: nil, message: nil, next: nil)

        let tempMessageID = state.appendOptimisticUserMessage("hello\n\nworld")
        await state.loadMessages()

        #expect(state.messages.map(\.info.id) == ["m-user", "m-assistant"])
        #expect(state.messages.contains(where: { $0.info.id == tempMessageID }) == false)
        #expect(state.partsByMessage[tempMessageID] == nil)
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
}

// MARK: - Design Tokens Tests

@MainActor
struct DesignTokensTests {

    @Test func spacingScaleIsConsistent() {
        #expect(DesignSpacing.xs == 4)
        #expect(DesignSpacing.sm == 8)
        #expect(DesignSpacing.md == 12)
        #expect(DesignSpacing.lg == 16)
        #expect(DesignSpacing.xl == 20)
        #expect(DesignSpacing.xxl == 24)
        #expect(DesignSpacing.messageVertical == 20)
        #expect(DesignSpacing.cardPadding == 12)
        #expect(DesignSpacing.cardGap == 16)
    }

    @Test func spacingIncreasesMonotonically() {
        let values = [DesignSpacing.xs, DesignSpacing.sm, DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xl, DesignSpacing.xxl]
        for i in 0..<(values.count - 1) {
            #expect(values[i] < values[i + 1])
        }
    }

    @Test func cornerRadiiArePositive() {
        #expect(DesignCorners.small > 0)
        #expect(DesignCorners.medium > DesignCorners.small)
        #expect(DesignCorners.large > DesignCorners.medium)
    }

    @Test func brandPrimaryIsSystemBlueTone() {
        let brand = DesignColors.Brand.primary
        let uiColor = UIColor(brand)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r < 0.1)
        #expect(g > 0.3 && g < 0.6)
        #expect(b > 0.8)
    }

    @Test func brandGoldIsWarmTone() {
        let gold = DesignColors.Brand.gold
        let uiColor = UIColor(gold)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.7)
        #expect(g > 0.5 && g < 0.8)
        #expect(b < 0.3)
    }

    @Test func opacityValuesAreInValidRange() {
        #expect(DesignColors.Opacity.surfaceFill > 0 && DesignColors.Opacity.surfaceFill < 0.2)
        #expect(DesignColors.Opacity.surfaceFillDark > 0 && DesignColors.Opacity.surfaceFillDark < 0.2)
        #expect(DesignColors.Opacity.borderStroke > 0 && DesignColors.Opacity.borderStroke < 0.3)
        #expect(DesignColors.Opacity.userMessageFill > 0 && DesignColors.Opacity.userMessageFill < 0.2)
        #expect(DesignColors.Opacity.selectionFill > 0 && DesignColors.Opacity.selectionFill < 0.2)
    }

    @Test func darkModeOpacityHigherThanLight() {
        #expect(DesignColors.Opacity.surfaceFillDark > DesignColors.Opacity.surfaceFill)
        #expect(DesignColors.Opacity.borderStrokeDark > DesignColors.Opacity.borderStroke)
        #expect(DesignColors.Opacity.userMessageFillDark > DesignColors.Opacity.userMessageFill)
    }

    @Test func animationPresetSlotsArePopulated() {
        let all: [String: Animation] = [
            "quick": DesignAnimation.quick,
            "standard": DesignAnimation.standard,
            "spring": DesignAnimation.spring,
            "gentleSpring": DesignAnimation.gentleSpring,
            "snappy": DesignAnimation.snappy,
            "breathing": DesignAnimation.breathing,
        ]
        #expect(all.count == 6)
    }

    @Test func semanticColorsAreDistinct() {
        let error = UIColor(DesignColors.Semantic.error)
        let success = UIColor(DesignColors.Semantic.success)
        let warning = UIColor(DesignColors.Semantic.warning)
        let info = UIColor(DesignColors.Semantic.info)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        error.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        success.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #expect(r1 != r2 || g1 != g2 || b1 != b2)
        warning.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #expect(r1 != r2 || g1 != g2 || b1 != b2)
        info.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #expect(r1 != r2 || g1 != g2 || b1 != b2)
    }
}
