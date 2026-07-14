import Foundation
import Testing
@testable import OpenCodeClient

private final class FluidVoiceMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            var handledRequest = request
            if handledRequest.httpBody == nil, let stream = handledRequest.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var body = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buffer, maxLength: 4_096)
                    guard count > 0 else { break }
                    body.append(buffer, count: count)
                }
                handledRequest.httpBodyStream = nil
                handledRequest.httpBody = body
            }
            let (response, data) = try handler(handledRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class FluidVoiceRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }
}

@Suite(.serialized)
struct FluidVoiceTests {
    @Test func decodesHealthResponse() throws {
        let response = try JSONDecoder().decode(
            FluidVoiceHealthResponse.self,
            from: Data(#"{"status":"ok","version":"1.6.2"}"#.utf8)
        )

        #expect(response.status == "ok")
        #expect(response.version == "1.6.2")
    }

    @Test func decodesTranscriptionResponse() throws {
        let response = try JSONDecoder().decode(
            FluidVoiceTranscriptionResponse.self,
            from: Data(#"{"confidence":1,"provider":"Cohere Transcribe","sampleCount":103595,"text":"Texto reconocido."}"#.utf8)
        )

        #expect(response.confidence == 1)
        #expect(response.provider == "Cohere Transcribe")
        #expect(response.sampleCount == 103595)
        #expect(response.text == "Texto reconocido.")
    }

    @Test func decodesPostprocessResponse() throws {
        let response = try JSONDecoder().decode(
            FluidVoicePostprocessResponse.self,
            from: Data(#"{"model":"fluid-1","provider":"fluid-1","text":"Texto procesado"}"#.utf8)
        )

        #expect(response.model == "fluid-1")
        #expect(response.provider == "fluid-1")
        #expect(response.text == "Texto procesado")
    }

    @Test func normalizesBaseURLAndRemovesTrailingSlashes() throws {
        #expect(try FluidVoiceClient.normalizedBaseURL("  https://voice.example.ts.net///  ").absoluteString == "https://voice.example.ts.net")
        #expect(try FluidVoiceClient.normalizedBaseURL("http://127.0.0.1:47733/").absoluteString == "http://127.0.0.1:47733")
        #expect(try FluidVoiceClient.normalizedBaseURL("https://example.com/proxy///").absoluteString == "https://example.com/proxy")
        #expect(throws: FluidVoiceClientError.invalidBaseURL) {
            try FluidVoiceClient.normalizedBaseURL("voice.example.ts.net")
        }
    }

    @Test func generatedWAVHasValidHeaderAndSize() throws {
        let pcm = Data([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80])
        let wav = try FluidVoiceWAV.makeData(pcmData: pcm)

        #expect(wav.count == FluidVoiceWAV.headerByteCount + pcm.count)
        #expect(String(data: wav[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: wav[8..<12], encoding: .ascii) == "WAVE")
        #expect(String(data: wav[36..<40], encoding: .ascii) == "data")
        #expect(readUInt32LE(wav, at: 4) == UInt32(36 + pcm.count))
        #expect(readUInt16LE(wav, at: 20) == 1)
        #expect(readUInt16LE(wav, at: 22) == 1)
        #expect(readUInt32LE(wav, at: 24) == 24_000)
        #expect(readUInt16LE(wav, at: 34) == 16)
        #expect(readUInt32LE(wav, at: 40) == UInt32(pcm.count))
    }

    @Test func convertsJSONHTTPError() async throws {
        let session = makeMockSession()
        let client = FluidVoiceClient(session: session)
        FluidVoiceMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"error":"Model is loading"}"#.utf8))
        }
        defer { FluidVoiceMockURLProtocol.handler = nil }

        do {
            _ = try await client.health(baseURL: "https://voice.example.ts.net")
            Issue.record("Expected FluidVoice HTTP error")
        } catch let error as FluidVoiceClientError {
            #expect(error == .httpError(statusCode: 503, message: "Model is loading"))
            #expect(error.localizedDescription.contains("Model is loading"))
        }
    }

    @Test func transcribeThenPostprocessUsesExpectedRequests() async throws {
        let session = makeMockSession()
        let client = FluidVoiceClient(session: session)
        let recorder = FluidVoiceRequestRecorder()
        FluidVoiceMockURLProtocol.handler = { request in
            recorder.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            switch request.url?.path {
            case "/v1/transcribe":
                return (response, Data(#"{"confidence":1,"provider":"Cohere Transcribe","sampleCount":2,"text":"raw text"}"#.utf8))
            case "/v1/postprocess":
                return (response, Data(#"{"model":"fluid-1","provider":"fluid-1","text":"processed text"}"#.utf8))
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { FluidVoiceMockURLProtocol.handler = nil }

        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try FluidVoiceWAV.write(pcmData: Data([0, 0, 1, 0]), to: wavURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let text = try await client.transcribeAudio(
            wavFileURL: wavURL,
            baseURL: "https://voice.example.ts.net/",
            postprocessWithFluidIntelligence: true
        )

        #expect(text == "processed text")
        let requests = recorder.requests
        #expect(requests.map { $0.url?.path } == ["/v1/transcribe", "/v1/postprocess"])
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "audio/wav")
        #expect(requests[0].value(forHTTPHeaderField: "X-Filename") == "dictation.wav")
        #expect(requests[1].value(forHTTPHeaderField: "Content-Type") == "application/json")

        let postprocessBody = try #require(requests[1].httpBody)
        let body = try JSONSerialization.jsonObject(with: postprocessBody) as? [String: String]
        #expect(body?["text"] == "raw text")
    }

    @Test @MainActor func providerDefaultsAndPersistence() {
        let keys = [
            AppState.voiceTranscriptionProviderKey,
            AppState.fluidVoiceBaseURLKey,
            AppState.fluidVoicePostprocessKey,
        ]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer {
            keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
            for (key, value) in previous where value != nil {
                UserDefaults.standard.set(value, forKey: key)
            }
        }

        let initial = AppState()
        #expect(initial.voiceTranscriptionProvider == .voiceFlow)
        #expect(initial.fluidVoiceBaseURL.isEmpty)
        #expect(initial.fluidVoicePostprocess == false)

        initial.voiceTranscriptionProvider = .fluidVoice
        initial.fluidVoiceBaseURL = "https://voice.example.ts.net"
        initial.fluidVoicePostprocess = true

        let restored = AppState()
        #expect(restored.voiceTranscriptionProvider == .fluidVoice)
        #expect(restored.fluidVoiceBaseURL == "https://voice.example.ts.net")
        #expect(restored.fluidVoicePostprocess)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FluidVoiceMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
