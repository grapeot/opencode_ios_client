//
//  OpenCodeClientTests.swift
//  OpenCodeClientTests
//
//  Created by Yan Wang on 2/12/26.
//

import Foundation
import Testing
@testable import OpenCodeClient

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
