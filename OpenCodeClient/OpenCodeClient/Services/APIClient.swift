//
//  APIClient.swift
//  OpenCodeClient
//

import Foundation
import os

nonisolated struct MessageTranscriptDecode: Sendable {
    let messages: [MessageWithParts]
    let diagnostics: [WireDecodeDiagnostic]
}

nonisolated enum MessageTranscriptError: Error, Equatable {
    case invalidJSON
    case unsupportedShape
    case noneDecoded(diagnostics: [WireDecodeDiagnostic])
}

actor APIClient {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "APIClient"
    )

    private var baseURL: String
    private var username: String?
    private var password: String?
    private let session: URLSession
    private var liveLease = CarLiveTransportLease()

    // Default to localhost to avoid leaking a personal LAN IP in open source repos.
    nonisolated static let defaultServer = "127.0.0.1:4096"

    init(
        baseURL: String = APIClient.defaultServer,
        username: String? = nil,
        password: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = Self.normalizeBaseURL(baseURL)
        self.username = username
        self.password = password
        self.session = session
    }

    func configure(baseURL: String, username: String? = nil, password: String? = nil) {
        self.baseURL = Self.normalizeBaseURL(baseURL)
        self.username = username
        self.password = password
        liveLease = CarLiveTransportGate.invalidate(liveLease)
    }

    /// A separate gate and cancellable session, using the same phone-only route.
    func makeWatchClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return APIClient(baseURL: baseURL, username: username, password: password,
                         session: URLSession(configuration: config))
    }

    nonisolated func cancelWatchRequests() {
        session.invalidateAndCancel()
    }

    /// Adds http:// when no scheme is present and strips trailing slashes so
    /// appended paths (e.g. "/global/health") never produce double slashes.
    nonisolated static func normalizeBaseURL(_ raw: String) -> String {
        var base = raw.hasPrefix("http") ? raw : "http://\(raw)"
        while base.hasSuffix("/"), base.count > 8 {
            base.removeLast()
        }
        return base
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        liveToken: UInt64? = nil
    ) async throws -> (Data, HTTPURLResponse) {
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
        if let liveToken {
            try ensureLiveTransport(liveToken)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpError(statusCode: 0, data: data)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }
        return (data, http)
    }

    private func acceptEmptyOrJSONBoolean(_ data: Data) throws {
        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        _ = try JSONDecoder().decode(Bool.self, from: data)
    }

    func health() async throws -> HealthResponse {
        let (data, _) = try await makeRequest(path: "/global/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func projects() async throws -> [Project] {
        let (data, _) = try await makeRequest(path: "/project")
        return try JSONDecoder().decode([Project].self, from: data)
    }

    func projectCurrent() async throws -> Project? {
        let (data, _) = try await makeRequest(path: "/project/current")
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    /// The server's instance directory, which sessions record as `directory`.
    func instanceDirectory() async throws -> String? {
        struct PathInfo: Decodable { let directory: String? }
        let (data, _) = try await makeRequest(path: "/path")
        return try JSONDecoder().decode(PathInfo.self, from: data).directory
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

    /// `/experimental/session` filters archive state on the server: without
    /// `archived` it returns only unarchived rows; with `archived=true` it
    /// returns both. `cursor` is the previous page's `x-next-cursor`.
    func sessionPage(
        directory: String?,
        includeArchived: Bool,
        rootsOnly: Bool,
        limit: Int,
        cursor: Int?
    ) async throws -> SessionPage {
        var queryItems = [URLQueryItem(name: "limit", value: String(max(limit, 1)))]
        if let directory, !directory.isEmpty {
            queryItems.append(URLQueryItem(name: "directory", value: directory))
        }
        if includeArchived { queryItems.append(URLQueryItem(name: "archived", value: "true")) }
        if rootsOnly { queryItems.append(URLQueryItem(name: "roots", value: "true")) }
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: String(cursor))) }
        let (data, http) = try await makeRequest(path: "/experimental/session", queryItems: queryItems)
        let rows = try JSONDecoder().decode([Session].self, from: data)
        let next = http.value(forHTTPHeaderField: "x-next-cursor").flatMap(Int.init)
        return SessionPage(rows: rows, nextCursor: next)
    }

    func session(sessionID: String) async throws -> Session {
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)")
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func promptStructured(
        sessionID: String,
        messageID: String? = nil,
        text: String,
        system: String,
        format: StructuredOutputFormat,
        agent: String = "build",
        model: Message.ModelInfo
    ) async throws -> MessageWithParts {
        struct PromptBody: Encodable {
            struct PartInput: Encodable {
                let type: String
                let text: String
            }

            struct ModelInput: Encodable {
                let providerID: String
                let modelID: String
            }

            let parts: [PartInput]
            let messageID: String?
            let system: String
            let format: StructuredOutputFormat
            let agent: String
            let model: ModelInput
        }

        let body = PromptBody(
            parts: [.init(type: "text", text: text)],
            messageID: messageID,
            system: system,
            format: format,
            agent: agent,
            model: .init(providerID: model.providerID, modelID: model.modelID)
        )
        let bodyData = try JSONEncoder().encode(body)
        let (responseData, _) = try await makeRequest(
            path: "/session/\(sessionID)/message",
            method: "POST",
            body: bodyData
        )
        return try JSONDecoder().decode(MessageWithParts.self, from: responseData)
    }

    func createSession(title: String? = nil, directory: String? = nil) async throws -> Session {
        let data = try CarLivePromptWire.sessionCreateData(title: title)
        let queryItems = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let (responseData, _) = try await makeRequest(
            path: "/session",
            method: "POST",
            queryItems: queryItems,
            body: data
        )
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func updateSession(sessionID: String, title: String) async throws -> Session {
        let body = ["title": title]
        let data = try JSONEncoder().encode(body)
        let (responseData, _) = try await makeRequest(path: "/session/\(sessionID)", method: "PATCH", body: data)
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
        try Task.checkCancellation()
        let data = try CarLiveArchiveWire.body(archived: archived)
        let (responseData, _) = try await makeRequest(path: "/session/\(sessionID)", method: "PATCH", body: data)
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func sessionChildren(sessionID: String) async throws -> [Session] {
        try Task.checkCancellation()
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)/children")
        return try JSONDecoder().decode([Session].self, from: data)
    }

    func updateSessionArchivedForLive(sessionID: String, archived: Int, transportToken: UInt64) async throws -> Int {
        let data = try CarLiveArchiveWire.body(archived: archived)
        let (_, http) = try await makeRequest(path: "/session/\(sessionID)", method: "PATCH", body: data, liveToken: transportToken)
        return http.statusCode
    }

    func deleteSession(sessionID: String) async throws {
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)", method: "DELETE")
        try acceptEmptyOrJSONBoolean(data)
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
        let decoded = try Self.decodeMessageTranscript(payloadData)
        Self.logMessageDecodeDiagnostics(decoded.diagnostics)
        return decoded.messages
    }

    nonisolated static func decodeMessageTranscript(_ data: Data) throws -> MessageTranscriptDecode {
        if let direct = try? JSONDecoder().decode([MessageWithParts].self, from: data) {
            return MessageTranscriptDecode(messages: direct, diagnostics: [])
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MessageTranscriptError.invalidJSON
        }

        if let rows = object as? [Any] {
            return try decodeMessageContainers(rows, prefix: "messages")
        }

        guard let dict = object as? [String: Any] else {
            throw MessageTranscriptError.unsupportedShape
        }
        if let rows = dict["messages"] as? [Any] ?? dict["data"] as? [Any] ?? dict["result"] as? [Any] {
            return try decodeMessageContainers(rows, prefix: "messages")
        }
        if dict["info"] is [String: Any] || dict["message"] is [String: Any] || (dict["role"] is String && dict["id"] is String) {
            return try decodeMessageContainers([dict], prefix: "messages")
        }
        throw MessageTranscriptError.unsupportedShape
    }

    private nonisolated static func decodeMessageContainers(_ rows: [Any], prefix: String) throws -> MessageTranscriptDecode {
        if rows.isEmpty {
            return MessageTranscriptDecode(messages: [], diagnostics: [])
        }
        var messages: [MessageWithParts] = []
        var diagnostics: [WireDecodeDiagnostic] = []
        for (index, row) in rows.enumerated() {
            let path = "\(prefix)[\(index)]"
            guard let container = row as? [String: Any] else {
                diagnostics.append(WireDecodeDiagnostic(codingPath: path, reason: "typeMismatch"))
                continue
            }
            let decoded = decodeMessageRecord(container, path: path)
            if let record = decoded.record {
                messages.append(record)
                diagnostics.append(contentsOf: decoded.diagnostics)
            } else {
                diagnostics.append(contentsOf: decoded.diagnostics)
            }
        }
        if messages.isEmpty {
            logMessageDecodeDiagnostics(diagnostics)
            throw MessageTranscriptError.noneDecoded(diagnostics: diagnostics)
        }
        return MessageTranscriptDecode(messages: messages, diagnostics: diagnostics)
    }

    private nonisolated static func decodeMessageRecord(
        _ container: [String: Any],
        path: String
    ) -> (record: MessageWithParts?, diagnostics: [WireDecodeDiagnostic]) {
        if let direct = try? decodeModel(container, as: MessageWithParts.self) {
            return (direct, [])
        }

        let infoObject = (container["info"] as? [String: Any]) ?? (container["message"] as? [String: Any]) ?? container
        let infoPath: String
        if container["info"] is [String: Any] {
            infoPath = path + ".info"
        } else if container["message"] is [String: Any] {
            infoPath = path + ".message"
        } else {
            infoPath = path
        }
        let info: Message
        do {
            info = try decodeModel(infoObject, as: Message.self)
        } catch {
            return (nil, [diagnostic(error, prefix: infoPath)])
        }

        let partsValue = container["parts"]
        if partsValue == nil {
            return (MessageWithParts(info: info, parts: []), [])
        }
        guard let partRows = partsValue as? [Any] else {
            return (
                MessageWithParts(info: info, parts: []),
                [WireDecodeDiagnostic(codingPath: path + ".parts", reason: "typeMismatch")]
            )
        }

        var parts: [Part] = []
        var diagnostics: [WireDecodeDiagnostic] = []
        for (index, partRow) in partRows.enumerated() {
            let partPath = path + ".parts[\(index)]"
            guard let partObject = partRow as? [String: Any] else {
                diagnostics.append(WireDecodeDiagnostic(codingPath: partPath, reason: "typeMismatch"))
                continue
            }
            do {
                parts.append(try decodeModel(partObject, as: Part.self))
            } catch {
                diagnostics.append(diagnostic(error, prefix: partPath))
            }
        }
        return (MessageWithParts(info: info, parts: parts), diagnostics)
    }

    private nonisolated static func decodeModel<T: Decodable>(_ value: Any, as type: T.Type) throws -> T {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid JSON object"))
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private nonisolated static func diagnostic(_ error: Error, prefix: String) -> WireDecodeDiagnostic {
        if let decoding = error as? DecodingError {
            return WireDecodeDiagnostic(decoding, prefix: prefix)
        }
        return WireDecodeDiagnostic(codingPath: prefix, reason: "dataCorrupted")
    }

    private nonisolated static func logMessageDecodeDiagnostics(_ diagnostics: [WireDecodeDiagnostic]) {
        for item in diagnostics {
            logger.warning("messages decode path=\(item.codingPath, privacy: .public) reason=\(item.reason, privacy: .public)")
        }
    }

    func promptAsync(
        sessionID: String,
        messageID: String,
        text: String,
        attachments: [ComposerImageAttachment] = [],
        agent: String = "build",
        model: Message.ModelInfo?,
        directory: String?
    ) async throws {
        struct PromptBody: Encodable {
            let messageID: String
            let parts: [PartInput]
            let agent: String
            let model: ModelInput?
            struct PartInput: Encodable {
                let type: String
                let text: String?
                let mime: String?
                let filename: String?
                let url: String?

                static func text(_ text: String) -> PartInput {
                    PartInput(type: "text", text: text, mime: nil, filename: nil, url: nil)
                }

                static func file(_ attachment: ComposerImageAttachment) -> PartInput {
                    PartInput(type: "file", text: nil, mime: attachment.mime, filename: attachment.filename, url: attachment.dataURL)
                }
            }
            struct ModelInput: Encodable {
                let providerID: String
                let modelID: String
            }
        }
        var parts: [PromptBody.PartInput] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(.text(text))
        }
        parts.append(contentsOf: attachments.map { .file($0) })
        let body = PromptBody(
            messageID: messageID,
            parts: parts,
            agent: agent,
            model: model.map { .init(providerID: $0.providerID, modelID: $0.modelID) }
        )
        let bodyData = try JSONEncoder().encode(body)
        let queryItems = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let (data, http) = try await makeRequest(
            path: "/session/\(sessionID)/prompt_async",
            method: "POST",
            queryItems: queryItems,
            body: bodyData
        )
        if http.statusCode != 204 {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }
    }

    func abort(sessionID: String) async throws {
        let (data, http) = try await makeRequest(path: "/session/\(sessionID)/abort", method: "POST")
        if http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }
    }

    func sessionStatus() async throws -> [String: SessionStatus] {
        try await sessionStatus(directory: nil)
    }

    func sessionStatus(directory: String?) async throws -> [String: SessionStatus] {
        let query = directory.map { [URLQueryItem(name: "directory", value: $0)] } ?? []
        let (data, _) = try await makeRequest(path: "/session/status", queryItems: query)
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
        let (responseData, http) = try await makeRequest(
            path: "/session/\(sessionID)/permissions/\(permissionID)",
            method: "POST",
            body: data
        )
        if http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: responseData)
        }
    }

    func pendingQuestions() async throws -> [QuestionRequest] {
        let (data, _) = try await makeRequest(path: "/question")
        return try JSONDecoder().decode([QuestionRequest].self, from: data)
    }

    func replyQuestion(requestID: String, answers: [[String]]) async throws {
        struct Body: Encodable {
            let answers: [[String]]
        }
        let data = try JSONEncoder().encode(Body(answers: answers))
        let (responseData, _) = try await makeRequest(path: "/question/\(requestID)/reply", method: "POST", body: data)
        try acceptEmptyOrJSONBoolean(responseData)
    }

    func rejectQuestion(requestID: String) async throws {
        let (responseData, _) = try await makeRequest(path: "/question/\(requestID)/reject", method: "POST")
        try acceptEmptyOrJSONBoolean(responseData)
    }

    func providers() async throws -> ProvidersResponse {
        let (data, _) = try await makeRequest(path: "/config/providers")
        return try JSONDecoder().decode(ProvidersResponse.self, from: data)
    }

    /// `/provider`: full provider registry including which providers are
    /// connected (authenticated or keyless-local), used to scope the model
    /// picker to models the user can actually run.
    func providerRegistry() async throws -> ProviderRegistryResponse {
        let (data, _) = try await makeRequest(path: "/provider")
        return try JSONDecoder().decode(ProviderRegistryResponse.self, from: data)
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

    func fileList(path: String = "", directory: String? = nil) async throws -> [FileNode] {
        var queryItems = [URLQueryItem(name: "path", value: path)]
        if let directory, !directory.isEmpty {
            queryItems.append(URLQueryItem(name: "directory", value: directory))
        }
        let (data, _) = try await makeRequest(path: "/file", queryItems: queryItems)
        return try JSONDecoder().decode([FileNode].self, from: data)
    }

    func fileContent(path: String, directory: String? = nil) async throws -> FileContent {
        var queryItems = [URLQueryItem(name: "path", value: path)]
        if let directory, !directory.isEmpty {
            queryItems.append(URLQueryItem(name: "directory", value: directory))
        }
        let (data, _) = try await makeRequest(path: "/file/content", queryItems: queryItems)
        return try JSONDecoder().decode(FileContent.self, from: data)
    }

    func findFile(query: String, limit: Int = 50) async throws -> [String] {
        try await findFile(query: query, limit: limit, directory: nil)
    }

    func findFile(query: String, limit: Int, directory: String?) async throws -> [String] {
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let directory, !directory.isEmpty {
            queryItems.append(URLQueryItem(name: "directory", value: directory))
        }
        let (data, _) = try await makeRequest(path: "/find/file", queryItems: queryItems)
        return try JSONDecoder().decode([String].self, from: data)
    }

    func fileStatus() async throws -> [FileStatusEntry] {
        let (data, _) = try await makeRequest(path: "/file/status")
        return try JSONDecoder().decode([FileStatusEntry].self, from: data)
    }

    func forkSession(sessionID: String, messageID: String? = nil) async throws -> Session {
        struct ForkBody: Encodable {
            let messageID: String?
        }
        let body = ForkBody(messageID: messageID)
        let data = try JSONEncoder().encode(body)
        let (responseData, _) = try await makeRequest(
            path: "/session/\(sessionID)/fork",
            method: "POST",
            body: data
        )
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func revertSession(sessionID: String, messageID: String, partID: String? = nil) async throws -> Session {
        struct RevertBody: Encodable {
            let messageID: String
            let partID: String?
        }

        let data = try JSONEncoder().encode(RevertBody(messageID: messageID, partID: partID))
        let (responseData, _) = try await makeRequest(
            path: "/session/\(sessionID)/revert",
            method: "POST",
            body: data
        )
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func armLiveTransport() -> UInt64 {
        let armed = CarLiveTransportGate.arm(liveLease)
        liveLease = armed.lease
        return armed.token
    }

    func retireLiveTransport(token: UInt64) {
        liveLease = CarLiveTransportGate.retire(liveLease, token: token)
    }

    func experimentalRootSessionPage(cursor: Int?, transportToken: UInt64) async throws -> CarLiveSessionPage {
        let (data, http) = try await makeRequest(
            path: "/experimental/session",
            queryItems: CarLivePromptWire.sessionPageQuery(cursor: cursor),
            liveToken: transportToken
        )
        let rows = try JSONDecoder().decode([Session].self, from: data)
        let header = http.value(forHTTPHeaderField: "x-next-cursor")
        Self.logger.debug("live session page status=\(http.statusCode, privacy: .public) rows=\(rows.count, privacy: .public)")
        return CarLiveSessionPage(rows: rows, nextCursor: header.flatMap(Int.init))
    }

    func sessionForLive(sessionID: String, directory: String?, transportToken: UInt64) async throws -> Session {
        let query = directory.flatMap { value -> [URLQueryItem]? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : [URLQueryItem(name: "directory", value: trimmed)]
        }
        let (data, http) = try await makeRequest(path: "/session/\(sessionID)", queryItems: query, liveToken: transportToken)
        Self.logger.debug("live session lookup status=\(http.statusCode, privacy: .public)")
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func messagePageForLive(sessionID: String, limit: Int, transportToken: UInt64) async throws -> CarLiveMessagePage {
        try await messagePageForLive(sessionID: sessionID, limit: limit, before: nil, directory: nil, transportToken: transportToken)
    }

    func messagePageForLive(
        sessionID: String,
        limit: Int,
        before: String?,
        directory: String?,
        transportToken: UInt64
    ) async throws -> CarLiveMessagePage {
        let capped = min(max(limit, 1), CarLiveHistory.bound)
        let (data, http) = try await makeRequest(
            path: "/session/\(sessionID)/message",
            queryItems: Self.liveMessageQuery(limit: capped, before: before, directory: directory),
            liveToken: transportToken
        )
        return try Self.liveMessagePage(data: data, response: http, requestedLimit: capped)
    }

    func sessionChildrenForLive(sessionID: String, transportToken: UInt64) async throws -> [Session] {
        let (data, http) = try await makeRequest(path: "/session/\(sessionID)/children", liveToken: transportToken)
        let rows = try JSONDecoder().decode([Session].self, from: data)
        Self.logger.debug("live children status=\(http.statusCode, privacy: .public) rows=\(rows.count, privacy: .public)")
        return rows
    }

    func createSessionForLive(directory: String?, transportToken: UInt64) async throws -> Session {
        let data = try CarLivePromptWire.sessionCreateData(title: nil)
        let queryItems = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let (responseData, _) = try await makeRequest(
            path: "/session",
            method: "POST",
            queryItems: queryItems,
            body: data,
            liveToken: transportToken
        )
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func promptAsyncForLive(
        sessionID: String,
        messageID: String,
        text: String,
        agent: String,
        model: Message.ModelInfo,
        directory: String?,
        transportToken: UInt64
    ) async throws {
        let body = try CarLivePromptWire.startData(messageID: messageID, text: text, agent: agent, model: model)
        try await postLivePrompt(sessionID: sessionID, directory: directory, body: body, transportToken: transportToken)
    }

    func promptAsyncInherited(
        sessionID: String,
        messageID: String,
        text: String,
        agent: String?,
        variant: String?,
        directory: String?,
        transportToken: UInt64
    ) async throws {
        let body = try CarLivePromptWire.continueData(messageID: messageID, text: text, agent: agent, variant: variant)
        try await postLivePrompt(sessionID: sessionID, directory: directory, body: body, transportToken: transportToken)
    }

    func abortForLive(sessionID: String, transportToken: UInt64) async throws {
        let (data, http) = try await makeRequest(path: "/session/\(sessionID)/abort", method: "POST", liveToken: transportToken)
        if http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }
    }

    func sessionStatusForLive(transportToken: UInt64) async throws -> [String: SessionStatus] {
        try await sessionStatusForLive(directory: nil, transportToken: transportToken)
    }

    func sessionStatusForLive(directory: String?, transportToken: UInt64) async throws -> [String: SessionStatus] {
        let query = Self.liveDirectoryQuery(directory)
        let (data, _) = try await makeRequest(
            path: "/session/status",
            queryItems: query,
            liveToken: transportToken
        )
        return try JSONDecoder().decode([String: SessionStatus].self, from: data)
    }

    func providerRegistryForLive(transportToken: UInt64) async throws -> ProviderRegistryResponse {
        let (data, _) = try await makeRequest(path: "/provider", liveToken: transportToken)
        return try JSONDecoder().decode(ProviderRegistryResponse.self, from: data)
    }

    func pendingPermissionsForLive(transportToken: UInt64) async throws -> [PermissionRequest] {
        let (data, _) = try await makeRequest(path: "/permission", liveToken: transportToken)
        return try JSONDecoder().decode([PermissionRequest].self, from: data)
    }

    func pendingQuestionsForLive(transportToken: UInt64) async throws -> [QuestionRequest] {
        let (data, _) = try await makeRequest(path: "/question", liveToken: transportToken)
        return try JSONDecoder().decode([QuestionRequest].self, from: data)
    }

    func replyQuestionForLive(requestID: String, answers: [[String]], transportToken: UInt64) async throws {
        let data = try JSONEncoder().encode(["answers": answers])
        let (responseData, _) = try await makeRequest(path: "/question/\(requestID)/reply", method: "POST", body: data, liveToken: transportToken)
        try acceptEmptyOrJSONBoolean(responseData)
    }

    func respondPermissionForLive(sessionID: String, permissionID: String, response: PermissionResponse, transportToken: UInt64) async throws {
        let data = try JSONEncoder().encode(["response": response.rawValue])
        let (responseData, http) = try await makeRequest(
            path: "/session/\(sessionID)/permissions/\(permissionID)",
            method: "POST",
            body: data,
            liveToken: transportToken
        )
        if http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: responseData)
        }
    }

    private func ensureLiveTransport(_ token: UInt64) throws {
        guard CarLiveTransportGate.allows(liveLease, token: token) else {
            throw CarLiveAPIUnsupported.closed
        }
    }

    private func postLivePrompt(sessionID: String, directory: String?, body: Data, transportToken: UInt64) async throws {
        let queryItems = directory.flatMap { value -> [URLQueryItem]? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : [URLQueryItem(name: "directory", value: trimmed)]
        }
        let (data, http) = try await makeRequest(
            path: "/session/\(sessionID)/prompt_async",
            method: "POST",
            queryItems: queryItems,
            body: body,
            liveToken: transportToken
        )
        Self.logger.debug("live prompt status=\(http.statusCode, privacy: .public)")
        if http.statusCode != 204 {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }
    }

    private nonisolated static func historyHasOlder(_ response: HTTPURLResponse) -> Bool {
        if response.value(forHTTPHeaderField: "X-Next-Cursor") != nil { return true }
        return linkDeclaresNext(response.value(forHTTPHeaderField: "Link"))
    }

    private nonisolated static func liveMessageQuery(limit: Int, before: String?, directory: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            items.append(URLQueryItem(name: "before", value: before))
        }
        if let directory {
            items.append(URLQueryItem(name: "directory", value: directory))
        }
        return items
    }

    private nonisolated static func liveDirectoryQuery(_ directory: String?) -> [URLQueryItem]? {
        guard let directory else { return nil }
        return [URLQueryItem(name: "directory", value: directory)]
    }

    private nonisolated static func liveMessagePage(data: Data, response: HTTPURLResponse, requestedLimit: Int) throws -> CarLiveMessagePage {
        let decoded = try decodeMessageTranscript(data)
        logMessageDecodeDiagnostics(decoded.diagnostics)
        logger.debug("live history status=\(response.statusCode, privacy: .public) rows=\(decoded.messages.count, privacy: .public)")
        return CarLiveMessagePage(
            messages: decoded.messages,
            hasOlder: historyHasOlder(response),
            requestedLimit: requestedLimit,
            nextCursor: historyNextCursor(response),
            hasDecodeGaps: !decoded.diagnostics.isEmpty
        )
    }

    nonisolated static func historyNextCursor(_ response: HTTPURLResponse) -> String? {
        if let cursor = response.value(forHTTPHeaderField: "X-Next-Cursor") {
            return cursor
        }
        return linkBeforeCursor(response.value(forHTTPHeaderField: "Link"))
    }

    nonisolated static func linkBeforeCursor(_ header: String?) -> String? {
        guard let header else { return nil }
        var search = header[...]
        while let open = search.firstIndex(of: "<") {
            let afterOpen = search.index(after: open)
            guard let close = search[afterOpen...].firstIndex(of: ">") else { return nil }
            let target = String(search[afterOpen..<close])
            let afterClose = search.index(after: close)
            let nextOpen = search[afterClose...].firstIndex(of: "<") ?? search.endIndex
            if relationIsNext(String(search[afterClose..<nextOpen])), let before = opaqueBefore(in: target) {
                return before
            }
            search = search[nextOpen...]
        }
        return nil
    }

    private nonisolated static func linkDeclaresNext(_ header: String?) -> Bool {
        guard let header else { return false }
        var search = header[...]
        while let open = search.firstIndex(of: "<") {
            guard let close = search[search.index(after: open)...].firstIndex(of: ">") else { return false }
            let afterClose = search.index(after: close)
            let nextOpen = search[afterClose...].firstIndex(of: "<") ?? search.endIndex
            if relationIsNext(String(search[afterClose..<nextOpen])) { return true }
            search = search[nextOpen...]
        }
        return false
    }

    private nonisolated static func relationIsNext(_ params: String) -> Bool {
        for part in params.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = piece.firstIndex(of: "=") else { continue }
            guard piece[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("rel") == .orderedSame else { continue }
            var value = piece[piece.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return value.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { $0.caseInsensitiveCompare("next") == .orderedSame }
        }
        return false
    }

    private nonisolated static func opaqueBefore(in target: String) -> String? {
        guard let queryStart = target.firstIndex(of: "?") else { return nil }
        var query = target[target.index(after: queryStart)...]
        if let hash = query.firstIndex(of: "#") { query = query[..<hash] }
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.first == "before" else { continue }
            let raw = parts.count > 1 ? parts[1] : ""
            return raw.removingPercentEncoding ?? raw
        }
        return nil
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

nonisolated struct FileContent: Codable {
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
nonisolated struct ProvidersResponse: Decodable {
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

/// Response of `/provider`: every known provider plus the subset that is
/// connected (authenticated, or local/keyless providers like a custom
/// Ollama endpoint, which count as connected without credentials).
nonisolated struct ProviderRegistryResponse: Decodable {
    let providers: [ConfigProvider]
    let connectedProviderIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case all
        case connected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = (try? c.decode([ConfigProvider].self, forKey: .all)) ?? []
        connectedProviderIDs = (try? c.decode([String].self, forKey: .connected)) ?? []
    }

    init(providers: [ConfigProvider], connectedProviderIDs: [String]) {
        self.providers = providers
        self.connectedProviderIDs = connectedProviderIDs
    }
}

nonisolated struct ConfigProvider: Decodable {
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
                    fixed[key] = ProviderModel(
                        id: key,
                        name: value.name,
                        providerID: value.providerID,
                        limit: value.limit,
                        capabilities: value.capabilities,
                        family: value.family,
                        releaseDate: value.releaseDate
                    )
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

nonisolated struct ProviderModel: Decodable {
    let id: String
    let name: String?
    let providerID: String?
    let limit: ProviderModelLimit?
    let capabilities: ProviderModelCapabilities?
    let family: String?
    let releaseDate: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case providerID
        case providerId
        case limit
        case capabilities
        case family
        case releaseDate = "release_date"
    }

    init(
        id: String,
        name: String?,
        providerID: String?,
        limit: ProviderModelLimit?,
        capabilities: ProviderModelCapabilities? = nil,
        family: String? = nil,
        releaseDate: String? = nil
    ) {
        self.id = id
        self.name = name
        self.providerID = providerID
        self.limit = limit
        self.capabilities = capabilities
        self.family = family
        self.releaseDate = releaseDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = try? c.decode(String.self, forKey: .name)
        providerID = (try? c.decode(String.self, forKey: .providerID)) ?? (try? c.decode(String.self, forKey: .providerId))
        limit = try? c.decode(ProviderModelLimit.self, forKey: .limit)
        capabilities = try? c.decode(ProviderModelCapabilities.self, forKey: .capabilities)
        family = try? c.decode(String.self, forKey: .family)
        releaseDate = try? c.decode(String.self, forKey: .releaseDate)
    }
}

nonisolated struct ProviderModelCapabilities: Codable {
    let reasoning: Bool?
    let toolCall: Bool?
    let attachment: Bool?
    let input: ProviderModelIO?
    let output: ProviderModelIO?

    private enum CodingKeys: String, CodingKey {
        case reasoning
        case toolCall = "toolcall"
        case attachment
        case input
        case output
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reasoning = try? c.decode(Bool.self, forKey: .reasoning)
        toolCall = try? c.decode(Bool.self, forKey: .toolCall)
        attachment = try? c.decode(Bool.self, forKey: .attachment)
        input = try? c.decode(ProviderModelIO.self, forKey: .input)
        output = try? c.decode(ProviderModelIO.self, forKey: .output)
    }

    init(reasoning: Bool?, toolCall: Bool?, attachment: Bool?, input: ProviderModelIO?, output: ProviderModelIO?) {
        self.reasoning = reasoning
        self.toolCall = toolCall
        self.attachment = attachment
        self.input = input
        self.output = output
    }

    /// Chat-capable means the model can produce text output. Filters out
    /// embedding/TTS/image-generation-only models from the picker.
    var isChatCapable: Bool {
        // Missing capability info is treated as capable: older servers may
        // not report it, and a false negative would hide working models.
        guard let output else { return true }
        return output.text ?? true
    }
}

nonisolated struct ProviderModelIO: Codable {
    let text: Bool?
    let audio: Bool?
    let image: Bool?
    let video: Bool?
    let pdf: Bool?
}

nonisolated struct ProviderModelLimit: Codable {
    let context: Int?
    let input: Int?
    let output: Int?
}

nonisolated struct DefaultProvider: Codable {
    let providerID: String
    let modelID: String
}

nonisolated struct HealthResponse: Codable {
    let healthy: Bool
    let version: String?
}

enum APIError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, data: Data)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let statusCode, let data):
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if body.isEmpty {
                return "HTTP \(statusCode)"
            }
            return "HTTP \(statusCode): \(body)"
        }
    }
}

protocol APIClientProtocol: Actor {
    func configure(baseURL: String, username: String?, password: String?)
    func health() async throws -> HealthResponse
    func projects() async throws -> [Project]
    func projectCurrent() async throws -> Project?
    func instanceDirectory() async throws -> String?
    func sessions(directory: String?, limit: Int) async throws -> [Session]
    func sessionPage(directory: String?, includeArchived: Bool, rootsOnly: Bool, limit: Int, cursor: Int?) async throws -> SessionPage
    func session(sessionID: String) async throws -> Session
    func createSession(title: String?, directory: String?) async throws -> Session
    func updateSession(sessionID: String, title: String) async throws -> Session
    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session
    func sessionChildren(sessionID: String) async throws -> [Session]
    func updateSessionArchivedForLive(sessionID: String, archived: Int, transportToken: UInt64) async throws -> Int
    func deleteSession(sessionID: String) async throws
    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts]
    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws
    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts
    func abort(sessionID: String) async throws
    func sessionStatus() async throws -> [String: SessionStatus]
    func sessionStatus(directory: String?) async throws -> [String: SessionStatus]
    func pendingPermissions() async throws -> [APIClient.PermissionRequest]
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws
    func pendingQuestions() async throws -> [QuestionRequest]
    func replyQuestion(requestID: String, answers: [[String]]) async throws
    func rejectQuestion(requestID: String) async throws
    func providers() async throws -> ProvidersResponse
    func providerRegistry() async throws -> ProviderRegistryResponse
    func agents() async throws -> [AgentInfo]
    func sessionDiff(sessionID: String) async throws -> [FileDiff]
    func sessionTodos(sessionID: String) async throws -> [TodoItem]
    func fileList(path: String, directory: String?) async throws -> [FileNode]
    func fileContent(path: String, directory: String?) async throws -> FileContent
    func findFile(query: String, limit: Int) async throws -> [String]
    func fileStatus() async throws -> [FileStatusEntry]
    func forkSession(sessionID: String, messageID: String?) async throws -> Session
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session
    func armLiveTransport() -> UInt64
    func retireLiveTransport(token: UInt64)
    func experimentalRootSessionPage(cursor: Int?, transportToken: UInt64) async throws -> CarLiveSessionPage
    func sessionForLive(sessionID: String, directory: String?, transportToken: UInt64) async throws -> Session
    func messagePageForLive(sessionID: String, limit: Int, transportToken: UInt64) async throws -> CarLiveMessagePage
    func messagePageForLive(sessionID: String, limit: Int, before: String?, directory: String?, transportToken: UInt64) async throws -> CarLiveMessagePage
    func sessionChildrenForLive(sessionID: String, transportToken: UInt64) async throws -> [Session]
    func createSessionForLive(directory: String?, transportToken: UInt64) async throws -> Session
    func promptAsyncForLive(sessionID: String, messageID: String, text: String, agent: String, model: Message.ModelInfo, directory: String?, transportToken: UInt64) async throws
    func promptAsyncInherited(sessionID: String, messageID: String, text: String, agent: String?, variant: String?, directory: String?, transportToken: UInt64) async throws
    func abortForLive(sessionID: String, transportToken: UInt64) async throws
    func sessionStatusForLive(transportToken: UInt64) async throws -> [String: SessionStatus]
    func sessionStatusForLive(directory: String?, transportToken: UInt64) async throws -> [String: SessionStatus]
    func providerRegistryForLive(transportToken: UInt64) async throws -> ProviderRegistryResponse
    func pendingPermissionsForLive(transportToken: UInt64) async throws -> [APIClient.PermissionRequest]
    func pendingQuestionsForLive(transportToken: UInt64) async throws -> [QuestionRequest]
    func replyQuestionForLive(requestID: String, answers: [[String]], transportToken: UInt64) async throws
    func respondPermissionForLive(sessionID: String, permissionID: String, response: APIClient.PermissionResponse, transportToken: UInt64) async throws
}

extension APIClient: APIClientProtocol {}

protocol FileDirectorySearching: APIClientProtocol {
    func findFile(query: String, limit: Int, directory: String?) async throws -> [String]
}

extension APIClient: FileDirectorySearching {}

struct SessionPage: Equatable, Sendable {
    var rows: [Session]
    var nextCursor: Int?
}

extension APIClientProtocol {
    func sessionChildren(sessionID: String) async throws -> [Session] {
        throw URLError(.unsupportedURL)
    }

    func sessionPage(directory: String?, includeArchived: Bool, rootsOnly: Bool, limit: Int, cursor: Int?) async throws -> SessionPage {
        throw URLError(.unsupportedURL)
    }

    func instanceDirectory() async throws -> String? {
        throw URLError(.unsupportedURL)
    }

    func sessionStatus(directory: String?) async throws -> [String: SessionStatus] {
        try await sessionStatus()
    }
    func armLiveTransport() -> UInt64 { 0 }
    func retireLiveTransport(token: UInt64) {}
    func experimentalRootSessionPage(cursor: Int?, transportToken: UInt64) async throws -> CarLiveSessionPage {
        throw CarLiveAPIUnsupported.experimentalSessionPage
    }
    func sessionForLive(sessionID: String, directory: String?, transportToken: UInt64) async throws -> Session {
        throw CarLiveAPIUnsupported.sessionLookup
    }
    func messagePageForLive(sessionID: String, limit: Int, transportToken: UInt64) async throws -> CarLiveMessagePage {
        throw CarLiveAPIUnsupported.history
    }
    func messagePageForLive(sessionID: String, limit: Int, before: String?, directory: String?, transportToken: UInt64) async throws -> CarLiveMessagePage {
        if before != nil || directory != nil {
            throw CarLiveAPIUnsupported.history
        }
        return try await messagePageForLive(sessionID: sessionID, limit: limit, transportToken: transportToken)
    }
    func sessionChildrenForLive(sessionID: String, transportToken: UInt64) async throws -> [Session] {
        throw CarLiveAPIUnsupported.children
    }
    func createSessionForLive(directory: String?, transportToken: UInt64) async throws -> Session {
        throw CarLiveAPIUnsupported.createSession
    }
    func promptAsyncForLive(sessionID: String, messageID: String, text: String, agent: String, model: Message.ModelInfo, directory: String?, transportToken: UInt64) async throws {
        throw CarLiveAPIUnsupported.prompt
    }
    func promptAsyncInherited(sessionID: String, messageID: String, text: String, agent: String?, variant: String?, directory: String?, transportToken: UInt64) async throws {
        throw CarLiveAPIUnsupported.prompt
    }
    func abortForLive(sessionID: String, transportToken: UInt64) async throws {
        throw CarLiveAPIUnsupported.abort
    }
    func sessionStatusForLive(transportToken: UInt64) async throws -> [String: SessionStatus] {
        throw CarLiveAPIUnsupported.status
    }
    func sessionStatusForLive(directory: String?, transportToken: UInt64) async throws -> [String: SessionStatus] {
        if directory != nil {
            throw CarLiveAPIUnsupported.status
        }
        return try await sessionStatusForLive(transportToken: transportToken)
    }
    func providerRegistryForLive(transportToken: UInt64) async throws -> ProviderRegistryResponse {
        throw CarLiveAPIUnsupported.providerRegistry
    }
    func pendingPermissionsForLive(transportToken: UInt64) async throws -> [APIClient.PermissionRequest] {
        throw CarLiveAPIUnsupported.pending
    }
    func pendingQuestionsForLive(transportToken: UInt64) async throws -> [QuestionRequest] {
        throw CarLiveAPIUnsupported.pending
    }
    func replyQuestionForLive(requestID: String, answers: [[String]], transportToken: UInt64) async throws {
        throw CarLiveAPIUnsupported.answer
    }
    func respondPermissionForLive(sessionID: String, permissionID: String, response: APIClient.PermissionResponse, transportToken: UInt64) async throws {
        throw CarLiveAPIUnsupported.answer
    }
    func updateSessionArchivedForLive(sessionID: String, archived: Int, transportToken: UInt64) async throws -> Int {
        throw CarLiveAPIUnsupported.archive
    }
    func promptStructured(
        sessionID: String,
        text: String,
        system: String,
        format: StructuredOutputFormat,
        agent: String,
        model: Message.ModelInfo
    ) async throws -> MessageWithParts {
        try await promptStructured(
            sessionID: sessionID,
            messageID: nil,
            text: text,
            system: system,
            format: format,
            agent: agent,
            model: model
        )
    }
}
