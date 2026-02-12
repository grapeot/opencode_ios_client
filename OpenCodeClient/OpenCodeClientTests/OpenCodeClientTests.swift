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
        #expect(APIClient.defaultServer == "192.168.180.128:4096")
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
