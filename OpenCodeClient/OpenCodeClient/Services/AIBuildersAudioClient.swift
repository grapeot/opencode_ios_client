import AVFoundation
import AudioToolbox
import Foundation
import os

struct TranscriptionResponse: Codable {
    let requestID: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case text
    }
}

private struct RealtimeSessionResponse: Decodable {
    let sessionID: String
    let wsURL: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case wsURL = "ws_url"
    }
}

private struct RealtimeSocketEvent {
    let type: String
    let text: String?
    let code: String?
    let message: String?

    init(data: Data) throws {
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let raw, let type = raw["type"] as? String else {
            throw AIBuildersAudioError.invalidResponse
        }
        self.type = type
        self.text = raw["text"] as? String
        self.code = raw["code"] as? String
        self.message = raw["message"] as? String
    }
}

enum AIBuildersAudioError: Error {
    case invalidBaseURL
    case missingToken
    case invalidResponse
    case httpError(statusCode: Int, body: Data)
    case audioConversionFailed
    case websocketError(String)
}

enum AIBuildersAudioClient {
    private static let targetSampleRate: Double = 24_000
    private static let targetChannels: AVAudioChannelCount = 1
    private static let sendChunkSize = 240_000

    private final class TaskMetricsCollector: NSObject, URLSessionTaskDelegate {
        private(set) var metrics: URLSessionTaskMetrics?

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            self.metrics = metrics
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "SpeechProfile"
    )

    private static func elapsedMs(since start: TimeInterval) -> Int {
        max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
    }

    private static func durationMs(start: Date?, end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return max(0, Int((end.timeIntervalSince(start)) * 1000))
    }

    private static func logNetworkMetrics(_ metrics: URLSessionTaskMetrics?) {
        guard let transaction = metrics?.transactionMetrics.last else {
            logger.notice("[SpeechProfile] transcribe metrics unavailable")
            return
        }

        let dnsMs = durationMs(start: transaction.domainLookupStartDate, end: transaction.domainLookupEndDate) ?? -1
        let connectMs = durationMs(start: transaction.connectStartDate, end: transaction.connectEndDate) ?? -1
        let tlsMs = durationMs(start: transaction.secureConnectionStartDate, end: transaction.secureConnectionEndDate) ?? -1
        let requestSendMs = durationMs(start: transaction.requestStartDate, end: transaction.requestEndDate) ?? -1
        let ttfbMs = durationMs(start: transaction.requestEndDate, end: transaction.responseStartDate) ?? -1
        let responseMs = durationMs(start: transaction.responseStartDate, end: transaction.responseEndDate) ?? -1
        let totalTransactionMs = durationMs(start: transaction.fetchStartDate, end: transaction.responseEndDate) ?? -1

        logger.notice(
            "[SpeechProfile] transcribe metrics dnsMs=\(dnsMs, privacy: .public) connectMs=\(connectMs, privacy: .public) tlsMs=\(tlsMs, privacy: .public) sendMs=\(requestSendMs, privacy: .public) ttfbMs=\(ttfbMs, privacy: .public) responseMs=\(responseMs, privacy: .public) transactionMs=\(totalTransactionMs, privacy: .public) reusedConnection=\(transaction.isReusedConnection, privacy: .public) networkProtocol=\(transaction.networkProtocolName ?? "unknown", privacy: .public)"
        )
    }

    static func transcribe(
        baseURL: String,
        token: String,
        audioFileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        terms: String? = nil
    ) async throws -> TranscriptionResponse {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw AIBuildersAudioError.invalidBaseURL }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIBuildersAudioError.missingToken }
        let transcribeStart = ProcessInfo.processInfo.systemUptime

        let normalizedBase = normalizedBaseURL(from: trimmedBase)
        let fileName = audioFileURL.lastPathComponent.isEmpty ? "audio.m4a" : audioFileURL.lastPathComponent
        let fileBytes = (try? audioFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        logger.notice("[SpeechProfile] realtime transcribe begin host=\(normalizedBase.host ?? "unknown", privacy: .public) file=\(fileName, privacy: .public) fileBytes=\(fileBytes, privacy: .public)")

        let conversionStart = ProcessInfo.processInfo.systemUptime
        let pcmAudio: Data
        do {
            pcmAudio = try convertAudioFileToPCM(audioFileURL)
        } catch {
            logger.error("[SpeechProfile] realtime convertAudio failed error=\(String(describing: error), privacy: .public)")
            throw error
        }
        logger.notice("[SpeechProfile] realtime transcribe convertAudio ms=\(elapsedMs(since: conversionStart), privacy: .public) bytes=\(pcmAudio.count, privacy: .public)")

        let sessionResponse = try await createRealtimeSession(
            baseURL: normalizedBase,
            token: token,
            language: language,
            prompt: prompt,
            terms: terms
        )

        let websocketURL = try realtimeWebSocketURL(baseURL: normalizedBase, relativePath: sessionResponse.wsURL)
        logger.notice("[SpeechProfile] realtime ws_url=\(sessionResponse.wsURL, privacy: .public) resolved=\(websocketURL.absoluteString, privacy: .public)")
        let transcript = try await streamPCMOverRealtimeWebSocket(
            websocketURL: websocketURL,
            pcmAudio: pcmAudio
        )
        logger.notice("[SpeechProfile] realtime transcribe done ms=\(elapsedMs(since: transcribeStart), privacy: .public) textChars=\(transcript.count, privacy: .public) requestID=\(sessionResponse.sessionID, privacy: .public)")
        return TranscriptionResponse(requestID: sessionResponse.sessionID, text: transcript)
    }

    static func testConnection(baseURL: String, token: String) async throws {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw AIBuildersAudioError.invalidBaseURL }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIBuildersAudioError.missingToken }

        let normalizedBase = normalizedBaseURL(from: trimmedBase)
        guard let url = buildAPIURL(base: normalizedBase, path: "/v1/embeddings") else {
            throw AIBuildersAudioError.invalidBaseURL
        }

        let body = try JSONEncoder().encode(["input": "ok"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIBuildersAudioError.invalidResponse
        }
        guard http.statusCode < 400 else {
            throw AIBuildersAudioError.httpError(statusCode: http.statusCode, body: data)
        }
    }

    static func normalizedBaseURL(from rawBaseURL: String) -> URL {
        let normalizedBase = rawBaseURL.hasPrefix("http://") || rawBaseURL.hasPrefix("https://")
            ? rawBaseURL
            : "https://\(rawBaseURL)"
        return URL(string: normalizedBase) ?? URL(string: "https://invalid.example")!
    }

    /// Builds API URL by appending path to base (preserves mount path like /backend).
    /// Ensures base path ends with / so relative path appends instead of replacing (RFC 3986).
    static func buildAPIURL(base: URL, path: String) -> URL? {
        let relPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var basePath = components?.path ?? ""
        if !basePath.isEmpty, !basePath.hasSuffix("/") {
            basePath += "/"
            components?.path = basePath
        }
        let baseForAppend = components?.url ?? base
        return URL(string: relPath, relativeTo: baseForAppend)?.absoluteURL
    }

    static func realtimeWebSocketURL(baseURL: URL, relativePath: String) throws -> URL {
        guard let httpURL = URL(string: relativePath, relativeTo: baseURL)?.absoluteURL else {
            throw AIBuildersAudioError.invalidBaseURL
        }
        var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: true)
        if components?.scheme == "https" {
            components?.scheme = "wss"
        } else if components?.scheme == "http" {
            components?.scheme = "ws"
        }
        guard let websocketURL = components?.url else {
            throw AIBuildersAudioError.invalidBaseURL
        }
        return websocketURL
    }

    private static func createRealtimeSession(
        baseURL: URL,
        token: String,
        language: String?,
        prompt: String?,
        terms: String?
    ) async throws -> RealtimeSessionResponse {
        guard let url = buildAPIURL(base: baseURL, path: "/v1/audio/realtime/sessions") else {
            throw AIBuildersAudioError.invalidBaseURL
        }
        logger.notice("[SpeechProfile] realtime session POST url=\(url.absoluteString, privacy: .public)")

        var payload: [String: Any] = [:]
        if let language, !language.isEmpty {
            payload["language"] = language
        }
        if let prompt, !prompt.isEmpty {
            payload["prompt"] = prompt
        }
        if let terms, !terms.isEmpty {
            payload["terms"] = terms
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        payload["vad"] = false
        payload["silence_duration_ms"] = 1200

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let metricsCollector = TaskMetricsCollector()
        let networkStart = ProcessInfo.processInfo.systemUptime
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request, delegate: metricsCollector)
        } catch {
            logger.error("[SpeechProfile] realtime session POST failed ms=\(elapsedMs(since: networkStart), privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw error
        }
        logger.notice("[SpeechProfile] realtime session create ms=\(elapsedMs(since: networkStart), privacy: .public) responseBytes=\(data.count, privacy: .public)")
        logNetworkMetrics(metricsCollector.metrics)

        guard let http = response as? HTTPURLResponse else {
            throw AIBuildersAudioError.invalidResponse
        }
        guard http.statusCode < 400 else {
            let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
            logger.error("[SpeechProfile] realtime session HTTP \(http.statusCode, privacy: .public) body=\(bodyPreview, privacy: .public)")
            throw AIBuildersAudioError.httpError(statusCode: http.statusCode, body: data)
        }
        do {
            return try JSONDecoder().decode(RealtimeSessionResponse.self, from: data)
        } catch {
            let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
            logger.error("[SpeechProfile] realtime session decode failed body=\(bodyPreview, privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private static func streamPCMOverRealtimeWebSocket(
        websocketURL: URL,
        pcmAudio: Data
    ) async throws -> String {
        logger.notice("[SpeechProfile] realtime websocket connect url=\(websocketURL.absoluteString, privacy: .public)")
        let session = URLSession(configuration: .default)
        let webSocketTask = session.webSocketTask(with: websocketURL)
        webSocketTask.resume()

        do {
            let readyEvent = try await receiveSocketEvent(task: webSocketTask)
            guard readyEvent.type == "session_ready" else {
                throw AIBuildersAudioError.websocketError("Expected session_ready, got \(readyEvent.type)")
            }

            for start in stride(from: 0, to: pcmAudio.count, by: sendChunkSize) {
                let end = min(start + sendChunkSize, pcmAudio.count)
                let chunk = pcmAudio.subdata(in: start..<end)
                try await webSocketTask.send(.data(chunk))
            }
            try await webSocketTask.send(.string("{\"type\":\"commit\"}"))

            var finalTranscript: String?
            while true {
                let event = try await receiveSocketEvent(task: webSocketTask)
                switch event.type {
                case "transcript_delta", "speech_started", "speech_stopped", "usage":
                    continue
                case "transcript_completed":
                    finalTranscript = event.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    try await webSocketTask.send(.string("{\"type\":\"stop\"}"))
                case "session_stopped":
                    return finalTranscript ?? ""
                case "error":
                    let message = event.message ?? event.code ?? "Unknown websocket error"
                    throw AIBuildersAudioError.websocketError(message)
                default:
                    continue
                }
            }
        } catch {
            logger.error("[SpeechProfile] realtime websocket error=\(String(describing: error), privacy: .public)")
            webSocketTask.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw error
        }
    }

    private static func receiveSocketEvent(task: URLSessionWebSocketTask) async throws -> RealtimeSocketEvent {
        let message = try await task.receive()
        switch message {
        case .data(let data):
            return try RealtimeSocketEvent(data: data)
        case .string(let string):
            guard let data = string.data(using: .utf8) else {
                throw AIBuildersAudioError.invalidResponse
            }
            return try RealtimeSocketEvent(data: data)
        @unknown default:
            throw AIBuildersAudioError.invalidResponse
        }
    }

    private static func convertAudioFileToPCM(_ audioFileURL: URL) throws -> Data {
        var extFile: ExtAudioFileRef?
        var err = ExtAudioFileOpenURL(audioFileURL as CFURL, &extFile)
        guard err == noErr, let file = extFile else {
            logger.error("[SpeechProfile] ExtAudioFileOpenURL failed err=\(err, privacy: .public)")
            throw AIBuildersAudioError.audioConversionFailed
        }
        defer { ExtAudioFileDispose(file) }

        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        err = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat)
        guard err == noErr else {
            logger.error("[SpeechProfile] ExtAudioFileSetProperty failed err=\(err, privacy: .public)")
            throw AIBuildersAudioError.audioConversionFailed
        }

        let bufferSize: UInt32 = 32768
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: bufferSize,
                mData: nil
            )
        )
        guard let bufferData = malloc(Int(bufferSize)) else {
            throw AIBuildersAudioError.audioConversionFailed
        }
        defer { free(bufferData) }
        bufferList.mBuffers.mData = bufferData

        var pcmData = Data()
        while true {
            bufferList.mBuffers.mDataByteSize = bufferSize
            var numFrames: UInt32 = bufferSize / 2
            err = ExtAudioFileRead(file, &numFrames, &bufferList)
            guard err == noErr else {
                logger.error("[SpeechProfile] ExtAudioFileRead failed err=\(err, privacy: .public)")
                throw AIBuildersAudioError.audioConversionFailed
            }
            if numFrames == 0 { break }
            let byteCount = Int(numFrames * 2)
            pcmData.append(Data(bytes: bufferData, count: byteCount))
        }

        guard !pcmData.isEmpty else {
            throw AIBuildersAudioError.audioConversionFailed
        }
        return pcmData
    }
}
