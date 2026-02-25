//
//  APIClient.swift
//  OpenCodeClient
//

import Foundation

actor APIClient {
    private var baseURL: String
    private var username: String?
    private var password: String?

    // Default to localhost to avoid leaking a personal LAN IP in open source repos.
    static let defaultServer = APIConstants.defaultServer

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
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        let url: URL
        if let queryItems {
            guard var components = URLComponents(string: "\(baseURL)\(path)") else {
                throw APIError.invalidURL
            }
            components.queryItems = queryItems
            guard let built = components.url else {
                throw APIError.invalidURL
            }
            url = built
        } else {
            guard let built = URL(string: "\(baseURL)\(path)") else {
                throw APIError.invalidURL
            }
            url = built
        }

        guard url.scheme != nil else {
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

    func projects() async throws -> [Project] {
        let (data, _) = try await makeRequest(path: "/project")
        return try JSONDecoder().decode([Project].self, from: data)
    }

    func sessions(directory: String? = nil, limit: Int = 100) async throws -> [Session] {
        var queryItems: [URLQueryItem] = []
        if let directory, !directory.isEmpty {
            queryItems.append(URLQueryItem(name: "directory", value: directory))
        }
        if limit > 0 {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        let (data, _) = try await makeRequest(
            path: "/session",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
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

    func deleteSession(sessionID: String) async throws {
        _ = try await makeRequest(path: "/session/\(sessionID)", method: "DELETE")
    }

    func messages(sessionID: String, limit: Int? = nil) async throws -> [MessageWithParts] {
        let queryItems: [URLQueryItem]? = {
            guard let limit, limit > 0 else { return nil }
            return [URLQueryItem(name: "limit", value: String(limit))]
        }()
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)/message", queryItems: queryItems)
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return []
        }
        let payloadData = text.data(using: .utf8) ?? data
        return try decodeMessagesPayload(payloadData)
    }

    private func decodeMessagesPayload(_ data: Data) throws -> [MessageWithParts] {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode([MessageWithParts].self, from: data) {
            return direct
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid JSON for messages payload"
                )
            )
        }

        if let direct = decodeMessagesFallback(from: obj, decoder: decoder), !direct.isEmpty {
            return direct
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Unsupported messages payload shape"
            )
        )
    }

    private func decodeMessagesFallback(from obj: Any, decoder: JSONDecoder) -> [MessageWithParts]? {
        let containers = extractMessageContainers(from: obj)
        guard !containers.isEmpty else { return nil }

        let messages = containers.compactMap { decodeMessageRecord(from: $0, decoder: decoder) }
        return messages.isEmpty ? nil : messages
    }

    private func extractMessageContainers(from obj: Any) -> [[String: Any]] {
        if let arr = obj as? [[String: Any]] {
            return arr
        }

        guard let dict = obj as? [String: Any] else { return [] }

        if let arr = dict["messages"] as? [[String: Any]] { return arr }
        if let arr = dict["data"] as? [[String: Any]] { return arr }
        if let arr = dict["result"] as? [[String: Any]] { return arr }

        if dict["info"] is [String: Any] || dict["message"] is [String: Any] {
            return [dict]
        }

        if dict["role"] is String && dict["id"] is String {
            return [dict]
        }

        return []
    }

    private func decodeMessageRecord(from container: [String: Any], decoder: JSONDecoder) -> MessageWithParts? {
        if let direct = decodeJSON(container, as: MessageWithParts.self, decoder: decoder) {
            return direct
        }

        let infoObject = container["info"] ?? container["message"] ?? container
        let partsObject = container["parts"]

        guard let info = decodeJSON(infoObject, as: Message.self, decoder: decoder) else {
            return nil
        }

        let parts = decodeParts(from: partsObject, decoder: decoder)
        return MessageWithParts(info: info, parts: parts)
    }

    private func decodeParts(from value: Any?, decoder: JSONDecoder) -> [Part] {
        guard let value else { return [] }

        if let arr = value as? [[String: Any]] {
            return arr.compactMap { decodeJSON($0, as: Part.self, decoder: decoder) }
        }

        return []
    }

    private func decodeJSON<T: Decodable>(_ value: Any, as type: T.Type, decoder: JSONDecoder) -> T? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
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

    enum PermissionResponse: String, Encodable {
        case once
        case always
        case reject
    }

    struct PermissionRequest: Codable, Identifiable {
        struct ToolRef: Codable {
            let messageID: String?
            let callID: String?
        }

        struct Metadata: Codable {
            let filepath: String?
            let parentDir: String?
        }

        let id: String
        let sessionID: String
        let permission: String?
        let patterns: [String]?
        let metadata: Metadata?
        let always: [String]?
        let tool: ToolRef?
    }

    func pendingPermissions() async throws -> [PermissionRequest] {
        let (data, _) = try await makeRequest(path: "/permission")
        return try JSONDecoder().decode([PermissionRequest].self, from: data)
    }

    func respondPermission(sessionID: String, permissionID: String, response: PermissionResponse) async throws {
        struct Body: Encodable {
            let response: PermissionResponse
        }
        let data = try JSONEncoder().encode(Body(response: response))
        let (_, httpResponse) = try await makeRequest(
            path: "/session/\(sessionID)/permissions/\(permissionID)",
            method: "POST",
            body: data
        )
        if let http = httpResponse as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }

    func providers() async throws -> ProvidersResponse {
        let (data, _) = try await makeRequest(path: "/config/providers")
        return try JSONDecoder().decode(ProvidersResponse.self, from: data)
    }

    func agents() async throws -> [AgentInfo] {
        let (data, _) = try await makeRequest(path: "/agent")
        return try JSONDecoder().decode([AgentInfo].self, from: data)
    }

    func sessionDiff(sessionID: String) async throws -> [FileDiff] {
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)/diff")
        return try JSONDecoder().decode([FileDiff].self, from: data)
    }

    func sessionTodos(sessionID: String) async throws -> [TodoItem] {
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)/todo")
        return try JSONDecoder().decode([TodoItem].self, from: data)
    }

    func fileList(path: String = "") async throws -> [FileNode] {
        let (data, _) = try await makeRequest(path: "/file", queryItems: [URLQueryItem(name: "path", value: path)])
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    func fileContent(path: String) async throws -> FileContent {
        let (data, _) = try await makeRequest(path: "/file/content", queryItems: [URLQueryItem(name: "path", value: path)])
        return try JSONDecoder().decode(FileContent.self, from: data)
    }

    func findFile(query: String, limit: Int = 50) async throws -> [String] {
        let (data, _) = try await makeRequest(
            path: "/find/file",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return try JSONDecoder().decode([String].self, from: data)
    }

    func fileStatus() async throws -> [FileStatusEntry] {
        let (data, _) = try await makeRequest(path: "/file/status")
        return try JSONDecoder().decode([FileStatusEntry].self, from: data)
    }
}

struct FileNode: Codable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let absolute: String?
    let type: String  // "directory" | "file"
    let ignored: Bool?
}

struct FileContent: Codable {
    let type: String  // "text" | "binary"
    let content: String?
    var text: String? { type == "text" ? content : nil }
}

struct FileStatusEntry: Codable {
    let path: String?
    let status: String?  // "added" | "modified" | "deleted" | "untracked"
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

/// OpenCode GET /config/providers
///
/// Server responses vary across versions:
/// - `providers` may be an array (`[{id, name, models}]`) or a dictionary (`{ providerID: ProviderInfo }`)
/// - `models` may be a dictionary (`{ modelID: ModelInfo }`) or an array (`[{id, ...}]`)
/// - `ProviderModel.id` / `ConfigProvider.id` may be missing when encoded as dictionary values
struct ProvidersResponse: Decodable {
    let providers: [ConfigProvider]
    let `default`: DefaultProvider?

    private enum CodingKeys: String, CodingKey {
        case providers
        case `default`
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        `default` = try? c.decode(DefaultProvider.self, forKey: .default)

        if let arr = try? c.decode([ConfigProvider].self, forKey: .providers) {
            providers = arr
            return
        }

        if let dict = try? c.decode([String: ConfigProvider].self, forKey: .providers) {
            providers = dict
                .map { (key, value) in
                    if !value.id.isEmpty { return value }
                    return ConfigProvider(id: key, name: value.name, models: value.models)
                }
                .sorted { $0.id < $1.id }
            return
        }

        providers = []
    }
}

struct ConfigProvider: Decodable {
    let id: String
    let name: String?
    let models: [String: ProviderModel]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case models
    }

    init(id: String, name: String?, models: [String: ProviderModel]) {
        self.id = id
        self.name = name
        self.models = models
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        if let dict = try? c.decode([String: ProviderModel].self, forKey: .models) {
            var fixed: [String: ProviderModel] = [:]
            fixed.reserveCapacity(dict.count)
            for (key, value) in dict {
                if value.id.isEmpty {
                    fixed[key] = ProviderModel(id: key, name: value.name, providerID: value.providerID, limit: value.limit)
                } else {
                    fixed[key] = value
                }
            }
            models = fixed
            return
        }

        if let arr = try? c.decode([ProviderModel].self, forKey: .models) {
            var fixed: [String: ProviderModel] = [:]
            fixed.reserveCapacity(arr.count)
            for m in arr {
                let key = m.id
                if key.isEmpty { continue }
                fixed[key] = m
            }
            models = fixed
            return
        }

        models = [:]
    }
}

struct ProviderModel: Decodable {
    let id: String
    let name: String?
    let providerID: String?
    let limit: ProviderModelLimit?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case providerID
        case providerId
        case limit
    }

    init(id: String, name: String?, providerID: String?, limit: ProviderModelLimit?) {
        self.id = id
        self.name = name
        self.providerID = providerID
        self.limit = limit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        providerID = (try? c.decode(String.self, forKey: .providerID)) ?? (try? c.decode(String.self, forKey: .providerId))
        limit = try? c.decode(ProviderModelLimit.self, forKey: .limit)
    }
}

struct ProviderModelLimit: Codable {
    let context: Int?
    let input: Int?
    let output: Int?
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
