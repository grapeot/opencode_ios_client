//
//  SSEClient.swift
//  OpenCodeClient
//

import Foundation

struct SSEEvent: Codable {
    let directory: String?
    let payload: SSEPayload
}

struct SSEPayload: Codable {
    let type: String
    let properties: [String: AnyCodable]?
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let string = try? container.decode(String.self) { value = string }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let array = try? container.decode([AnyCodable].self) { value = array.map { $0.value } }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value } }
        else if container.decodeNil() { value = NSNull() }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let bool as Bool: try container.encode(bool)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

actor SSEClient {
    func connect(
        baseURL: String,
        username: String? = nil,
        password: String? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let urlString = baseURL.hasPrefix("http") ? baseURL : "http://\(baseURL)"
        guard let url = URL(string: "\(urlString)/global/event") else {
            return AsyncThrowingStream { $0.finish(throwing: APIError.invalidURL) }
        }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let username, let password {
            let credential = "\(username):\(password)"
            if let data = credential.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    var lineBuffer = Data()
                    var eventDataLines: [String] = []

                    func flushEventIfNeeded() {
                        guard !eventDataLines.isEmpty else { return }
                        let json = eventDataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        eventDataLines.removeAll(keepingCapacity: true)

                        guard !json.isEmpty, json != "[DONE]" else { return }
                        let data = Data(json.utf8)
                        if let event = try? JSONDecoder().decode(SSEEvent.self, from: data) {
                            continuation.yield(event)
                        }
                    }

                    for try await byte in bytes {
                        try Task.checkCancellation()

                        if byte == 0x0A {  // \n
                            // Process a single SSE line (UTF-8)
                            if lineBuffer.last == 0x0D { lineBuffer.removeLast() }  // \r
                            let line = String(decoding: lineBuffer, as: UTF8.self)
                            lineBuffer.removeAll(keepingCapacity: true)

                            if line.isEmpty {
                                // Empty line = event delimiter
                                flushEventIfNeeded()
                                continue
                            }

                            if line.hasPrefix(":") {
                                // Comment/keep-alive; ignore
                                continue
                            }

                            if line.hasPrefix("data:") {
                                var payload = String(line.dropFirst(5))
                                if payload.hasPrefix(" ") { payload.removeFirst() }
                                eventDataLines.append(payload)
                            }

                            continue
                        }

                        lineBuffer.append(byte)
                    }

                    // Stream ended; flush any pending event
                    flushEventIfNeeded()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
