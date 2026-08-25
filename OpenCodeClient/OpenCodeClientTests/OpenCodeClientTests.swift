//
//  OpenCodeClientTests.swift
//  OpenCodeClientTests
//

import Foundation
import AVFoundation
import UIKit
import Testing
@testable import OpenCodeClient

// MARK: - Existing Tests

struct OpenCodeClientTests {


    @Test func providerModelCapabilitiesDecodeFromServerShape() throws {
        let json = """
        {"id":"m","name":"M","capabilities":{"reasoning":true,"toolcall":true,"attachment":false,
         "input":{"text":true,"audio":false},"output":{"text":false,"audio":true}}}
        """
        let model = try JSONDecoder().decode(ProviderModel.self, from: Data(json.utf8))
        #expect(model.capabilities?.reasoning == true)
        #expect(model.capabilities?.toolCall == true)
        // TTS-only (no text output) is not chat-capable.
        #expect(model.capabilities?.isChatCapable == false)
        // Missing capabilities entirely -> treated as chat-capable.
        let bare = try JSONDecoder().decode(ProviderModel.self, from: Data("{\"id\":\"m\"}".utf8))
        #expect(bare.capabilities?.isChatCapable ?? true)
    }

    @Test func defaultServerAddress() {
        #expect(APIClient.defaultServer == "127.0.0.1:4096")
    }

    @Test func correctMalformedServerURL() {
        // Malformed "host://host:port" from iOS .textContentType(.URL) autocorrect
        #expect(AppState.correctMalformedServerURL("host.example.ts.net://host.example.ts.net:4096") == "host.example.ts.net:4096")
        #expect(AppState.correctMalformedServerURL("host.example.com://host.example.com:8080") == "host.example.com:8080")
        // Legitimate URLs unchanged
        #expect(AppState.correctMalformedServerURL("http://host.example.ts.net:4096") == nil)
        #expect(AppState.correctMalformedServerURL("host.example.ts.net:4096") == nil)
        #expect(AppState.correctMalformedServerURL("127.0.0.1:4096") == nil)
    }

    @Test func ensureServerURLHasScheme() {
        #expect(AppState.ensureServerURLHasScheme("host.example.ts.net:4096") == "http://host.example.ts.net:4096")
        #expect(AppState.ensureServerURLHasScheme("127.0.0.1:4096") == "http://127.0.0.1:4096")
        #expect(AppState.ensureServerURLHasScheme("http://host.example.ts.net:4096") == nil)
        #expect(AppState.ensureServerURLHasScheme("https://example.com:443") == nil)
    }

    @Test @MainActor func migrateLegacyDefaultServerAddress() {
        let key = "serverURL"
        let previous = UserDefaults.standard.string(forKey: key)
        let previousProfiles = UserDefaults.standard.data(forKey: AppState.hostProfilesKey)
        let previousProfileID = UserDefaults.standard.string(forKey: AppState.currentHostProfileIDKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if let previousProfiles { UserDefaults.standard.set(previousProfiles, forKey: AppState.hostProfilesKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.hostProfilesKey) }
            if let previousProfileID { UserDefaults.standard.set(previousProfileID, forKey: AppState.currentHostProfileIDKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.currentHostProfileIDKey) }
        }

        UserDefaults.standard.removeObject(forKey: AppState.hostProfilesKey)
        UserDefaults.standard.removeObject(forKey: AppState.currentHostProfileIDKey)
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

    @Test func sessionDecodingWithRevert() throws {
        let json = """
        {"id":"s1","slug":"s1","projectID":"p1","directory":"/tmp","parentID":null,"title":"Test","version":"1","time":{"created":0,"updated":0},"share":null,"summary":null,"revert":{"messageID":"msg-2","partID":null,"snapshot":"abc","diff":"def"}}
        """
        let data = json.data(using: .utf8)!
        let session = try JSONDecoder().decode(Session.self, from: data)
        #expect(session.revert?.messageID == "msg-2")
        #expect(session.revert?.snapshot == "abc")
        #expect(session.revert?.diff == "def")
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

    @Test func filePartDecoding() throws {
        let json = """
        {"id":"p-file","messageID":"m1","sessionID":"s1","type":"file","text":null,"tool":null,"callID":null,"state":null,"metadata":null,"files":null,"mime":"image/jpeg","filename":"photo.jpg","url":"data:image/jpeg;base64,AAA","source":null}
        """
        let part = try JSONDecoder().decode(Part.self, from: Data(json.utf8))
        #expect(part.isFile)
        #expect(part.isImageAttachment)
        #expect(part.mime == "image/jpeg")
        #expect(part.filename == "photo.jpg")
        #expect(part.url == "data:image/jpeg;base64,AAA")
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

    @Test func structuredCarMessageDecoding() throws {
        let json = """
        {"id":"a1","sessionID":"car-1","role":"assistant","parentID":"u1","time":{"created":1,"completed":2},"finish":"tool-calls","structured":{"version":1,"status":"needs_confirmation","speech":"Open the route?","confirmation":{"id":"confirm-1","prompt":"Confirm or cancel"},"clientActions":[]}}
        """
        let message = try JSONDecoder().decode(Message.self, from: Data(json.utf8))
        #expect(message.structured?.version == 1)
        #expect(message.structured?.status == .needsConfirmation)
        #expect(message.structured?.confirmation?.id == "confirm-1")
        #expect(message.finish == "tool-calls")
    }

    @Test func carNavigationURLUsesTypedDestination() throws {
        let action = CarClientAction.openNavigation(
            id: "route-1",
            destination: "Space Needle, Seattle",
            waypoints: ["Pike Place Market"]
        )
        let url = try #require(CarClientActionDispatcher.navigationURL(for: action))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components.host == "maps.apple.com")
        #expect(query["daddr"] == "Space Needle, Seattle")
        #expect(query["dirflg"] == "d")
        #expect(query["waypoints"] == "Pike Place Market")

        let rejected = CarClientAction.unknown(id: "bad", type: "open_url")
        #expect(CarClientActionDispatcher.navigationURL(for: rejected) == nil)
    }

    @Test func carSpeechUsesPlaybackAudioPolicy() {
        #expect(CarSpeechAudioPolicy.category == .playback)
        #expect(CarSpeechAudioPolicy.mode == .spokenAudio)
        #expect(CarSpeechAudioPolicy.options.contains(.duckOthers))
        #expect(!CarSpeechAudioPolicy.options.contains(.allowBluetoothHFP))
    }

    @Test func rootTabOrderKeepsCarModeOnIPhoneAfterFiles() {
        #expect(RootTab.chat.rawValue == 0)
        #expect(RootTab.files.rawValue == 1)
        #expect(RootTab.car.rawValue == 2)
        #expect(RootTab.settings.rawValue == 3)
    }

    @Test @MainActor func carModeFeatureFlagDefaultsOffAndPersists() {
        let previous = UserDefaults.standard.object(forKey: AppState.carModeEnabledKey)
        UserDefaults.standard.removeObject(forKey: AppState.carModeEnabledKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.carModeEnabledKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.carModeEnabledKey) }
        }

        let initial = AppState()
        #expect(!initial.isCarModeEnabled)

        initial.isCarModeEnabled = true
        #expect(AppState().isCarModeEnabled)
    }

    @Test @MainActor func structuredSpeechFallsBackWhenAssistantHasNoTextPart() {
        let envelope = CarResponseEnvelope(
            version: 1,
            status: .completed,
            speech: "The garage door is closed.",
            confirmation: nil,
            clientActions: []
        )
        let info = Message(
            id: "assistant-car",
            sessionID: "car-session",
            role: "assistant",
            parentID: "user-car",
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 1, completed: 2),
            finish: "tool-calls",
            tokens: nil,
            cost: nil,
            structured: envelope
        )
        let message = MessageWithParts(info: info, parts: [])
        #expect(MessageRowView.structuredSpeechFallback(for: message) == envelope.speech)

        let textPart = try! JSONDecoder().decode(Part.self, from: Data("""
        {"id":"p1","messageID":"assistant-car","sessionID":"car-session","type":"text","text":"Visible text"}
        """.utf8))
        #expect(MessageRowView.structuredSpeechFallback(for: MessageWithParts(info: info, parts: [textPart])) == nil)
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

    @Test func toolDisplayDecodesJSONUnicodeEscapes() throws {
        let partJson = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"tool","text":null,"tool":"bash","callID":"c1","state":{"status":"completed","input":{"command":"say \\u4f60\\u597d"},"output":"\\u4e2d\\u6587 \\ud83d\\ude00","title":"done","metadata":{},"time":{"start":0,"end":1}},"metadata":null,"files":null}
        """
        let data = partJson.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.toolInputSummaryForDisplay == "say 你好")
        #expect(part.toolOutputForDisplay == "中文 😀")
    }

    @Test func partDecodingAcceptsStringFileEntries() throws {
        let partJson = """
        {"id":"p1","messageID":"m1","sessionID":"s1","type":"patch","text":null,"tool":null,"callID":null,"state":null,"metadata":null,"files":["src/main.swift",{"path":"src/utils.swift"}]}
        """
        let data = partJson.data(using: .utf8)!
        let part = try JSONDecoder().decode(Part.self, from: data)
        #expect(part.filePathsForNavigation == ["src/main.swift", "src/utils.swift"])
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
