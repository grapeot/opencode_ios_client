import Foundation
import Testing
@testable import OpenCodeClient

struct WireDecodingTests {
    @Test func partSourcePreservesLegalObjectUnion() throws {
        let file = try decodePart(fileSourceJSON(type: "file", extra: #""note":"kept""#))
        #expect(file.source?.preservedObject?["type"] == .string("file"))
        #expect(file.source?.preservedObject?["path"] == .string("note.txt"))
        #expect(file.source?.preservedObject?["note"] == .string("kept"))
        #expect(file.url == "file:///note.txt")

        let symbol = try decodePart("""
        {"id":"p-symbol","messageID":"m1","sessionID":"s1","type":"file","mime":"text/plain","url":"file:///App.swift","source":{"type":"symbol","path":"App.swift","name":"AppState","kind":12,"range":{"start":{"line":3,"character":1},"end":{"line":4,"character":2}},"text":{"value":"struct AppState","start":0,"end":15}}}
        """)
        #expect(symbol.source?.preservedObject?["type"] == .string("symbol"))
        #expect(symbol.source?.preservedObject?["name"] == .string("AppState"))

        let resource = try decodePart("""
        {"id":"p-resource","messageID":"m1","sessionID":"s1","type":"file","mime":"text/plain","url":"file:///res","source":{"type":"resource","clientName":"docs","uri":"file:///res","text":{"value":"body","start":1.5,"end":4}}}
        """)
        #expect(resource.source?.preservedObject?["type"] == .string("resource"))
        #expect(resource.source?.preservedObject?["uri"] == .string("file:///res"))
        #expect(resource.source?.preservedObject?["text"]?["start"] == .double(1.5))

        let agent = try decodePart("""
        {"id":"p-agent","messageID":"m1","sessionID":"s1","type":"agent","name":"build","source":{"value":"@build","start":0,"end":6}}
        """)
        #expect(agent.type == "agent")
        #expect(agent.source?.preservedObject?["start"] == .int(0))
        #expect(agent.source?.preservedObject?["value"] == .string("@build"))
        #expect(agent.source?.preservedObject?["name"] == nil)

        let encoded = try JSONEncoder().encode(file)
        let roundTrip = try JSONDecoder().decode(Part.self, from: encoded)
        #expect(roundTrip.source?.preservedObject?["note"] == .string("kept"))
        #expect(roundTrip.source?.preservedObject?["type"] == .string("file"))
    }

    @Test func partSourceKeepsLegacyStringAndRejectsScalar() throws {
        let legacy = try decodePart(fileSourceJSON(source: #""legacy-path""#))
        #expect(legacy.source == .string("legacy-path"))

        let data = Data(fileSourceJSON(source: "7").utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Part.self, from: data)
        }
    }

    @Test func arbitraryStructuredIsPreservedAndIsNotACarEnvelope() throws {
        let message = try decodeMessage("""
        {"id":"m-answer","sessionID":"s1","role":"assistant","time":{"created":1,"completed":2},"structured":{"answer":42,"ok":true}}
        """)
        #expect(message.structured?["answer"] == .int(42))
        #expect(message.structured?["ok"] == .bool(true))
        #expect(message.carResponseEnvelope == nil)
        #expect(throws: CarModeError.self) {
            try CarResponseEnvelope.accepted(from: message)
        }

        let arrayMessage = try decodeMessage("""
        {"id":"m-array","sessionID":"s1","role":"assistant","time":{"created":1},"structured":[1,"kept"]}
        """)
        #expect(arrayMessage.structured == .array([.int(1), .string("kept")]))
        #expect(arrayMessage.carResponseEnvelope == nil)

        let boolMessage = try decodeMessage("""
        {"id":"m-bool","sessionID":"s1","role":"assistant","time":{"created":1},"structured":false}
        """)
        #expect(boolMessage.structured == .bool(false))
        let boolRoundTrip = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(boolMessage))
        #expect(boolRoundTrip.structured == .bool(false))

        let numberMessage = try decodeMessage("""
        {"id":"m-number","sessionID":"s1","role":"assistant","time":{"created":1},"structured":7}
        """)
        #expect(numberMessage.structured == .int(7))

        let stringMessage = try decodeMessage("""
        {"id":"m-string","sessionID":"s1","role":"assistant","time":{"created":1},"structured":"kept"}
        """)
        #expect(stringMessage.structured == .string("kept"))
    }

    @Test func carEnvelopeConvertsOnlyWhenTypedFieldsMatch() throws {
        let legal = try decodeMessage("""
        {"id":"m-car","sessionID":"s1","role":"assistant","time":{"created":1,"completed":2},"structured":{"version":1,"status":"needs_confirmation","speech":"Open the route?","confirmation":{"id":"confirm-1","prompt":"Confirm or cancel"},"clientActions":[{"id":"nav-1","type":"open_navigation","destination":"Space Needle","waypoints":["Pike Place"]}]}}
        """)
        let envelope = try CarResponseEnvelope.accepted(from: legal)
        #expect(envelope.status == .needsConfirmation)
        #expect(envelope.confirmation?.id == "confirm-1")
        #expect(envelope.clientActions.first == .openNavigation(id: "nav-1", destination: "Space Needle", waypoints: ["Pike Place"]))

        let constructed = try Message(
            id: "m-local",
            sessionID: "s1",
            role: "assistant",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 1, completed: 2),
            finish: nil,
            tokens: nil,
            cost: nil,
            structured: envelope
        )
        #expect(constructed.carResponseEnvelope == envelope)

        let invalid = try decodeMessage("""
        {"id":"m-bad-car","sessionID":"s1","role":"assistant","time":{"created":1,"completed":2},"structured":{"version":1,"status":"not_a_status","speech":"CANARY_INVALID_SPEECH","confirmation":null,"clientActions":[]}}
        """)
        #expect(invalid.id == "m-bad-car")
        #expect(invalid.structured?["speech"] == .string("CANARY_INVALID_SPEECH"))
        #expect(invalid.carResponseEnvelope == nil)
        #expect(throws: CarModeError.self) {
            try CarResponseEnvelope.accepted(from: invalid)
        }
    }

    @Test func toolErrorBodyReachesExistingDisplayPath() throws {
        let part = try decodePart("""
        {"id":"p-tool","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash","callID":"c1","state":{"status":"error","input":{},"error":"permission denied","time":{"start":1,"end":2}}}
        """)
        #expect(part.stateDisplay == "error")
        #expect(part.toolOutput == nil)
        #expect(part.toolError == "permission denied")
        #expect(part.toolOutputForDisplay == "permission denied")
    }

    @Test func mixedTranscriptKeepsLegalRecordsOnRESTAndSSE() throws {
        let transcript = """
        [
          {
            "info": {"id":"m-legal","sessionID":"s1","role":"assistant","time":{"created":1,"completed":2},"structured":{"answer":42}},
            "parts": [
              {"id":"p-text","messageID":"m-legal","sessionID":"s1","type":"text","text":"kept"},
              {"id":"p-file","messageID":"m-legal","sessionID":"s1","type":"file","mime":"text/plain","filename":"note.txt","url":"file:///note.txt","source":{"type":"file","path":"note.txt","text":{"value":"hello","start":0,"end":5},"note":"kept"}},
              {"id":"p-tool","messageID":"m-legal","sessionID":"s1","type":"tool","tool":"bash","callID":"c1","state":{"status":"error","input":{},"error":"permission denied","time":{"start":1,"end":2}}}
            ]
          },
          {
            "info": {"sessionID":"s1","role":"user","time":{"created":1},"text":"CANARY_DROPPED_RECORD"},
            "parts": [{"id":"p-dropped","messageID":"x","sessionID":"s1","type":"text","text":"CANARY_DROPPED_RECORD"}]
          },
          {
            "info": {"id":"m-parts","sessionID":"s1","role":"user","time":{"created":3}},
            "parts": [
              {"id":"p-ok","messageID":"m-parts","sessionID":"s1","type":"text","text":"sibling"},
              {"id":"p-bad","messageID":"m-parts","sessionID":"s1","type":"file","mime":"text/plain","filename":"CANARY_PART","url":"file:///x","source":7}
            ]
          },
          {
            "info": {"id":"m-car","sessionID":"s1","role":"assistant","time":{"created":4,"completed":5},"structured":{"version":1,"status":"completed","speech":"Garage closed.","confirmation":null,"clientActions":[]}},
            "parts": []
          }
        ]
        """
        let decoded = try APIClient.decodeMessageTranscript(Data(transcript.utf8))
        #expect(decoded.messages.map(\.info.id) == ["m-legal", "m-parts", "m-car"])
        let legal = try #require(decoded.messages.first)
        #expect(legal.parts.map(\.id) == ["p-text", "p-file", "p-tool"])
        #expect(legal.parts[1].source?.preservedObject?["type"] == .string("file"))
        #expect(legal.parts[1].source?.preservedObject?["note"] == .string("kept"))
        #expect(legal.info.structured?["answer"] == .int(42))
        #expect(legal.info.carResponseEnvelope == nil)
        #expect(legal.parts[2].toolOutputForDisplay == "permission denied")
        #expect(decoded.messages[1].parts.map(\.id) == ["p-ok"])
        #expect(decoded.messages[2].info.carResponseEnvelope?.speech == "Garage closed.")

        let diagnosticText = decoded.diagnostics.map { "\($0.codingPath) \($0.reason)" }.joined(separator: "\n")
        #expect(decoded.diagnostics.contains { $0.codingPath.contains("messages[1].info") && $0.reason == "keyNotFound" })
        #expect(decoded.diagnostics.contains { $0.codingPath == "messages[2].parts[1].source" && $0.reason == "typeMismatch" })
        #expect(!diagnosticText.contains("CANARY"))
        #expect(!decoded.messages.contains { $0.parts.contains { $0.filename == "CANARY_PART" || $0.text?.contains("CANARY") == true } })

        let ssePart = try decodeSSEPart("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","part":{"id":"p-file","messageID":"m-legal","sessionID":"s1","type":"file","mime":"text/plain","filename":"note.txt","url":"file:///note.txt","source":{"type":"file","path":"note.txt","text":{"value":"hello","start":0,"end":5},"note":"kept"}}}}}
        """)
        #expect(ssePart.source?.preservedObject?["type"] == .string("file"))
        #expect(ssePart.source?.preservedObject?["note"] == .string("kept"))

        let sseInfo = try decodeSSEInfo("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","info":{"id":"m-answer","sessionID":"s1","role":"assistant","time":{"created":1,"completed":2},"structured":{"answer":42}}}}}
        """)
        #expect(sseInfo.structured?["answer"] == .int(42))
        #expect(sseInfo.carResponseEnvelope == nil)

        let sseTool = try decodeSSEPart("""
        {"payload":{"type":"message.part.updated","properties":{"part":{"id":"p-tool","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash","callID":"c1","state":{"status":"error","input":{},"error":"permission denied","time":{"start":1,"end":2}}}}}}
        """)
        #expect(sseTool.toolOutputForDisplay == "permission denied")

        do {
            _ = try decodeSSEPart("""
            {"payload":{"type":"message.part.updated","properties":{"part":{"id":"p-bad","messageID":"m1","sessionID":"s1","type":"file","mime":"text/plain","filename":"CANARY_PART","url":"file:///x","source":7}}}}
            """)
            Issue.record("expected scalar source to fail SSE part decode")
        } catch let error as DecodingError {
            let diagnostic = WireDecodeDiagnostic(error)
            #expect(diagnostic.codingPath.contains("source"))
            #expect(diagnostic.reason == "typeMismatch")
            #expect(!diagnostic.codingPath.contains("CANARY"))
            #expect(!diagnostic.reason.contains("CANARY"))
        }
    }

    @Test func legalTranscriptUsesDirectDecodeWithoutDiagnostics() throws {
        let transcript = """
        [
          {"info":{"id":"m1","sessionID":"s1","role":"user","time":{"created":1}},"parts":[{"id":"p1","messageID":"m1","sessionID":"s1","type":"file","mime":"text/plain","url":"file:///note.txt","source":{"type":"file","path":"note.txt","text":{"value":"hello","start":0,"end":5}}}]},
          {"info":{"id":"m2","sessionID":"s1","role":"assistant","time":{"created":2,"completed":3},"structured":{"answer":42}},"parts":[]},
          {"info":{"id":"m3","sessionID":"s1","role":"assistant","time":{"created":4,"completed":5},"structured":{"version":1,"status":"not_a_status","speech":"nope","confirmation":null,"clientActions":[]}},"parts":[]}
        ]
        """
        let decoded = try APIClient.decodeMessageTranscript(Data(transcript.utf8))
        #expect(decoded.diagnostics.isEmpty)
        #expect(decoded.messages.map(\.info.id) == ["m1", "m2", "m3"])
        #expect(decoded.messages[0].parts.first?.source?.preservedObject?["type"] == .string("file"))
        #expect(decoded.messages[1].info.structured?["answer"] == .int(42))
        #expect(decoded.messages[1].info.carResponseEnvelope == nil)
        #expect(decoded.messages[2].info.structured?["status"] == .string("not_a_status"))
        #expect(decoded.messages[2].info.carResponseEnvelope == nil)
    }

    @Test func fullyCorruptTranscriptThrowsWithoutRecordingBody() throws {
        let transcript = """
        [{"info":{"role":"user","time":{"created":1},"text":"CANARY_ONLY"},"parts":[]}]
        """
        do {
            _ = try APIClient.decodeMessageTranscript(Data(transcript.utf8))
            Issue.record("expected corrupt transcript to fail")
        } catch let error as MessageTranscriptError {
            guard case .noneDecoded(let diagnostics) = error else {
                Issue.record("expected noneDecoded")
                return
            }
            let rendered = diagnostics.map { "\($0.codingPath) \($0.reason)" }.joined(separator: "\n")
            #expect(diagnostics.contains { $0.reason == "keyNotFound" })
            #expect(!rendered.contains("CANARY"))
        }
    }

    @Test func unknownCarActionStaysCompatibleThroughMessageConversion() throws {
        let message = try decodeMessage("""
        {"id":"m-unknown","sessionID":"s1","role":"assistant","time":{"created":1,"completed":2},"structured":{"version":1,"status":"completed","speech":"Ignored future action.","confirmation":null,"clientActions":[{"id":"future-1","type":"future.capability","payload":"kept-extra"}]}}
        """)
        #expect(message.structured?["clientActions"]?.arrayValue?.first?["payload"] == .string("kept-extra"))
        #expect(message.structured?["confirmation"] == .null)
        let envelope = try CarResponseEnvelope.accepted(from: message)
        #expect(envelope.speech == "Ignored future action.")
        #expect(envelope.clientActions == [.unknown(id: "future-1", type: "future.capability")])

        let typed = try WireJSON(encoding: envelope)
        #expect(typed["speech"] == .string("Ignored future action."))
        #expect(typed["clientActions"]?.arrayValue?.first?["type"] == .string("future.capability"))
        #expect(typed["clientActions"]?.arrayValue?.first?["payload"] == nil)
        #expect(typed["confirmation"] == nil)
    }

    @Test func toolErrorDetailKeepsErrorTextAndSuccessOutput() throws {
        let bash = try decodePart("""
        {"id":"p-bash","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash","callID":"c1","state":{"status":"error","input":{},"error":"permission denied","time":{"start":1,"end":2}}}
        """)
        #expect(bash.toolDetailPresentation(isImageFile: false) == .text("permission denied"))

        let todoError = try decodePart("""
        {"id":"p-todo","messageID":"m1","sessionID":"s1","type":"tool","tool":"todowrite","callID":"c1","state":{"status":"error","input":{},"error":"permission denied","time":{"start":1,"end":2}}}
        """)
        #expect(todoError.showsToolErrorBody)
        #expect(todoError.toolDetailPresentation(isImageFile: false) == .text("permission denied"))

        let todoSuccess = try decodePart("""
        {"id":"p-todo-ok","messageID":"m1","sessionID":"s1","type":"tool","tool":"todowrite","callID":"c1","state":{"status":"completed","input":{},"output":"W02_TODO_SUCCESS_OUTPUT","time":{"start":1,"end":2}}}
        """)
        #expect(todoSuccess.toolDetailPresentation(isImageFile: false) == .hidden)

        let imageRead = try decodePart("""
        {"id":"p-read","messageID":"m1","sessionID":"s1","type":"tool","tool":"read","callID":"c1","state":{"status":"error","input":{"filePath":"missing.png"},"error":"permission denied","time":{"start":1,"end":2}}}
        """)
        #expect(imageRead.state?.pathFromInput == "missing.png")
        #expect(imageRead.toolOutput == nil)
        #expect(imageRead.toolDetailPresentation(isImageFile: true) == .text("permission denied"))

        let imageSuccess = try decodePart("""
        {"id":"p-img","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash","callID":"c1","state":{"status":"completed","input":{"filePath":"shot.png"},"output":"ok","time":{"start":1,"end":2}}}
        """)
        #expect(imageSuccess.toolDetailPresentation(isImageFile: true) == .successImage)
    }

    @Test @MainActor func applySSEEventKeepsSourceAndStructuredWithoutREST() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api, sseClient: MockSSEClient())
        state.currentSessionID = "s1"

        await state.applySSEEventForTesting(makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","info":{"id":"m-answer","sessionID":"s1","role":"assistant","time":{"created":1,"completed":2},"structured":{"answer":42,"ok":false,"label":"kept","nested":null}}}}}
        """))
        await state.applySSEEventForTesting(makeSSEEvent("""
        {"payload":{"type":"message.part.updated","properties":{"sessionID":"s1","part":{"id":"p-file","messageID":"m-answer","sessionID":"s1","type":"file","mime":"text/plain","filename":"note.txt","url":"file:///note.txt","source":{"type":"file","path":"note.txt","text":{"value":"hello","start":0,"end":5},"note":"kept"}}}}}
        """))
        await state.applySSEEventForTesting(makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","info":{"id":"m-bool","sessionID":"s1","role":"assistant","time":{"created":3},"structured":false}}}}
        """))
        await state.applySSEEventForTesting(makeSSEEvent("""
        {"payload":{"type":"message.updated","properties":{"sessionID":"s1","info":{"id":"m-array","sessionID":"s1","role":"assistant","time":{"created":4},"structured":[1,"kept"]}}}}
        """))

        let objectRow = try #require(state.messages.first { $0.info.id == "m-answer" })
        #expect(objectRow.info.structured?["answer"] == .int(42))
        #expect(objectRow.info.structured?["ok"] == .bool(false))
        #expect(objectRow.info.structured?["label"] == .string("kept"))
        #expect(objectRow.info.structured?["nested"] == .null)
        #expect(objectRow.parts.first?.source?.preservedObject?["type"] == .string("file"))
        #expect(objectRow.parts.first?.source?.preservedObject?["note"] == .string("kept"))
        #expect(state.messages.first { $0.info.id == "m-bool" }?.info.structured == .bool(false))
        #expect(state.messages.first { $0.info.id == "m-array" }?.info.structured == .array([.int(1), .string("kept")]))
        #expect(await api.messagesCallCount == 0)
        #expect(await api.sessionDiffCallCount == 0)
    }
}

private func decodePart(_ json: String) throws -> Part {
    try JSONDecoder().decode(Part.self, from: Data(json.utf8))
}

private func decodeMessage(_ json: String) throws -> Message {
    try JSONDecoder().decode(Message.self, from: Data(json.utf8))
}

private func fileSourceJSON(type: String, extra: String) -> String {
    let source = #"{"type":"\#(type)","path":"note.txt","text":{"value":"hello","start":0,"end":5},\#(extra)}"#
    return fileSourceJSON(source: source)
}

private func fileSourceJSON(source: String) -> String {
    """
    {"id":"p-file","messageID":"m1","sessionID":"s1","type":"file","mime":"text/plain","filename":"note.txt","url":"file:///note.txt","source":\(source)}
    """
}

private func makeSSEEvent(_ json: String) -> SSEEvent {
    try! JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8))
}

private func decodeSSEPart(_ json: String) throws -> Part {
    let event = try JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8))
    let partObject = try #require(event.payload.properties?["part"]?.value as? [String: Any])
    let data = try JSONSerialization.data(withJSONObject: partObject)
    return try JSONDecoder().decode(Part.self, from: data)
}

private func decodeSSEInfo(_ json: String) throws -> Message {
    let event = try JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8))
    let infoObject = try #require(event.payload.properties?["info"]?.value as? [String: Any])
    let data = try JSONSerialization.data(withJSONObject: infoObject)
    return try JSONDecoder().decode(Message.self, from: data)
}
