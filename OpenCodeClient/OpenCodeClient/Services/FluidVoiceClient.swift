import Foundation

nonisolated struct FluidVoiceHealthResponse: Codable, Equatable, Sendable {
    let status: String
    let version: String
}

nonisolated struct FluidVoiceTranscriptionResponse: Codable, Equatable, Sendable {
    let confidence: Double
    let provider: String
    let sampleCount: Int
    let text: String
}

nonisolated struct FluidVoicePostprocessResponse: Codable, Equatable, Sendable {
    let model: String
    let provider: String
    let text: String
}

nonisolated private struct FluidVoicePostprocessRequest: Encodable {
    let text: String
}

nonisolated private struct FluidVoiceErrorResponse: Decodable {
    let error: String
}

nonisolated enum FluidVoiceClientError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case audioTooLarge
    case timedOut
    case cancelled
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid FluidVoice base URL using http:// or https://."
        case .invalidResponse:
            return "FluidVoice returned an invalid response."
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "FluidVoice returned HTTP \(statusCode): \(message)"
            }
            return "FluidVoice returned HTTP \(statusCode)."
        case .audioTooLarge:
            return "The recording exceeds FluidVoice's 25 MB limit."
        case .timedOut:
            return "FluidVoice timed out while loading or transcribing. Try again."
        case .cancelled:
            return "FluidVoice transcription was cancelled."
        case .connectionFailed(let detail):
            return "Could not connect to FluidVoice: \(detail)"
        }
    }
}

actor FluidVoiceClient {
    static let requestTimeout: TimeInterval = 180
    static let maximumAudioByteCount = 25 * 1024 * 1024

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated static func normalizedBaseURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              components.query == nil,
              components.fragment == nil else {
            throw FluidVoiceClientError.invalidBaseURL
        }

        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path
        guard let normalized = components.url else { throw FluidVoiceClientError.invalidBaseURL }
        return normalized
    }

    func health(baseURL: String) async throws -> FluidVoiceHealthResponse {
        let request = try makeRequest(baseURL: baseURL, path: "/v1/health")
        let data = try await performDataRequest(request)
        return try decode(FluidVoiceHealthResponse.self, from: data)
    }

    func transcribe(wavFileURL: URL, baseURL: String) async throws -> FluidVoiceTranscriptionResponse {
        let fileSize = try wavFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= Self.maximumAudioByteCount else { throw FluidVoiceClientError.audioTooLarge }
        _ = try FluidVoiceWAV.validate(fileURL: wavFileURL)

        var request = try makeRequest(baseURL: baseURL, path: "/v1/transcribe", method: "POST")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("dictation.wav", forHTTPHeaderField: "X-Filename")

        let data = try await performUpload(request, fromFile: wavFileURL)
        return try decode(FluidVoiceTranscriptionResponse.self, from: data)
    }

    func postprocess(text: String, baseURL: String) async throws -> FluidVoicePostprocessResponse {
        var request = try makeRequest(baseURL: baseURL, path: "/v1/postprocess", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(FluidVoicePostprocessRequest(text: text))

        let data = try await performDataRequest(request)
        return try decode(FluidVoicePostprocessResponse.self, from: data)
    }

    func transcribeAudio(wavFileURL: URL, baseURL: String, postprocessWithFluidIntelligence: Bool) async throws -> String {
        let transcription = try await transcribe(wavFileURL: wavFileURL, baseURL: baseURL)
        guard postprocessWithFluidIntelligence else { return transcription.text }
        return try await postprocess(text: transcription.text, baseURL: baseURL).text
    }

    private func makeRequest(baseURL: String, path: String, method: String = "GET") throws -> URLRequest {
        let base = try Self.normalizedBaseURL(baseURL)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw FluidVoiceClientError.invalidBaseURL
        }
        components.percentEncodedPath += path
        guard let url = components.url else { throw FluidVoiceClientError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.requestTimeout
        return request
    }

    private func performDataRequest(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            return try validatedData(data, response: response)
        } catch {
            throw mapTransportError(error)
        }
    }

    private func performUpload(_ request: URLRequest, fromFile fileURL: URL) async throws -> Data {
        do {
            let (data, response) = try await session.upload(for: request, fromFile: fileURL)
            return try validatedData(data, response: response)
        } catch {
            throw mapTransportError(error)
        }
    }

    private func validatedData(_ data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw FluidVoiceClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = try? decoder.decode(FluidVoiceErrorResponse.self, from: data).error
            throw FluidVoiceClientError.httpError(statusCode: http.statusCode, message: message)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let error as FluidVoiceClientError {
            throw error
        } catch {
            throw FluidVoiceClientError.invalidResponse
        }
    }

    private func mapTransportError(_ error: Error) -> Error {
        if let fluidError = error as? FluidVoiceClientError { return fluidError }
        if error is CancellationError { return FluidVoiceClientError.cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return FluidVoiceClientError.cancelled
            case .timedOut:
                return FluidVoiceClientError.timedOut
            default:
                return FluidVoiceClientError.connectionFailed(urlError.localizedDescription)
            }
        }
        return FluidVoiceClientError.connectionFailed(error.localizedDescription)
    }
}
