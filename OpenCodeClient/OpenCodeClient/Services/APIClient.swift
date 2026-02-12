//
//  APIClient.swift
//  OpenCodeClient
//

import Foundation

actor APIClient {
    private var baseURL: String
    private var username: String?
    private var password: String?

    static let defaultServer = "192.168.180.128:4096"

    init(baseURL: String = defaultServer, username: String? = nil, password: String? = nil) {
        self.baseURL = baseURL.hasPrefix("http") ? baseURL : "http://\(baseURL)"
        self.username = username
        self.password = password
    }

    func configure(baseURL: String, username: String? = nil, password: String? = nil) {
        self.baseURL = baseURL.hasPrefix("http") ? baseURL : "http://\(baseURL)"
        self.username = username
        self.password = password
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let username, let password {
            let credential = "\(username):\(password)"
            if let data = credential.data(using: .utf8) {
                let encoded = data.base64EncodedString()
                request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
            }
        }

        if let body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }
        return (data, response)
    }

    func health() async throws -> HealthResponse {
        let (data, _) = try await makeRequest(path: "/global/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func sessions() async throws -> [Session] {
        let (data, _) = try await makeRequest(path: "/session")
        return try JSONDecoder().decode([Session].self, from: data)
    }

    func createSession(title: String? = nil) async throws -> Session {
        let body = title.map { ["title": $0] } ?? [:]
        let data = try JSONEncoder().encode(body)
        let (responseData, _) = try await makeRequest(path: "/session", method: "POST", body: data)
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func updateSession(sessionID: String, title: String) async throws -> Session {
        let body = ["title": title]
        let data = try JSONEncoder().encode(body)
        let (responseData, _) = try await makeRequest(path: "/session/\(sessionID)", method: "PATCH", body: data)
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func messages(sessionID: String) async throws -> [MessageWithParts] {
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)/message")
        return try JSONDecoder().decode([MessageWithParts].self, from: data)
    }

    func promptAsync(sessionID: String, text: String, agent: String = "build", model: Message.ModelInfo?) async throws {
        struct PromptBody: Encodable {
            let parts: [PartInput]
            let agent: String
            let model: ModelInput?
            struct PartInput: Encodable {
                let type = "text"
                let text: String
            }
            struct ModelInput: Encodable {
                let providerID: String
                let modelID: String
            }
        }
        let body = PromptBody(
            parts: [.init(text: text)],
            agent: agent,
            model: model.map { .init(providerID: $0.providerID, modelID: $0.modelID) }
        )
        let bodyData = try JSONEncoder().encode(body)
        let (_, response) = try await makeRequest(path: "/session/\(sessionID)/prompt_async", method: "POST", body: bodyData)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }

    func abort(sessionID: String) async throws {
        let (_, response) = try await makeRequest(path: "/session/\(sessionID)/abort", method: "POST")
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }

    func sessionStatus() async throws -> [String: SessionStatus] {
        let (data, _) = try await makeRequest(path: "/session/status")
        return try JSONDecoder().decode([String: SessionStatus].self, from: data)
    }

    func respondPermission(sessionID: String, permissionID: String) async throws {
        let (_, response) = try await makeRequest(path: "/session/\(sessionID)/permissions/\(permissionID)", method: "POST")
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }

    func providers() async throws -> ProvidersResponse {
        let (data, _) = try await makeRequest(path: "/config/providers")
        return try JSONDecoder().decode(ProvidersResponse.self, from: data)
    }

    func summarize(sessionID: String) async throws {
        let (_, response) = try await makeRequest(path: "/session/\(sessionID)/summarize", method: "POST")
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }

    func sessionDiff(sessionID: String) async throws -> [FileDiff] {
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)/diff")
        return try JSONDecoder().decode([FileDiff].self, from: data)
    }
}

struct FileDiff: Codable, Identifiable, Hashable {
    var id: String { file }
    let file: String
    let before: String
    let after: String
    let additions: Int
    let deletions: Int
    let status: String?

    enum CodingKeys: String, CodingKey {
        case file, path, before, after, additions, deletions, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = (try? c.decode(String.self, forKey: .file)) ?? (try? c.decode(String.self, forKey: .path)) ?? ""
        before = (try? c.decode(String.self, forKey: .before)) ?? ""
        after = (try? c.decode(String.self, forKey: .after)) ?? ""
        additions = (try? c.decode(Int.self, forKey: .additions)) ?? 0
        deletions = (try? c.decode(Int.self, forKey: .deletions)) ?? 0
        status = try? c.decode(String.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(file, forKey: .file)
        try c.encode(before, forKey: .before)
        try c.encode(after, forKey: .after)
        try c.encode(additions, forKey: .additions)
        try c.encode(deletions, forKey: .deletions)
        try c.encodeIfPresent(status, forKey: .status)
    }

    init(file: String, before: String, after: String, additions: Int, deletions: Int, status: String?) {
        self.file = file
        self.before = before
        self.after = after
        self.additions = additions
        self.deletions = deletions
        self.status = status
    }

    func hash(into hasher: inout Hasher) { hasher.combine(file) }
    static func == (lhs: FileDiff, rhs: FileDiff) -> Bool { lhs.file == rhs.file }
}

/// OpenCode GET /config/providers 返回 providers 为 array，每个元素含 id, name, models: { modelID: ModelInfo }
struct ProvidersResponse: Codable {
    let providers: [ConfigProvider]?
    let `default`: DefaultProvider?
}

struct ConfigProvider: Codable {
    let id: String
    let name: String?
    let models: [String: ProviderModel]?
}

struct ProviderModel: Codable {
    let id: String
    let name: String?
    let providerID: String?
}

struct DefaultProvider: Codable {
    let providerID: String
    let modelID: String
}

struct HealthResponse: Codable {
    let healthy: Bool
    let version: String?
}

enum APIError: Error {
    case invalidURL
    case httpError(statusCode: Int, data: Data)
}
