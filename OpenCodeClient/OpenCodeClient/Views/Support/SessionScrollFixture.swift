import Foundation

/// Deterministic two-session fixture for the per-session scroll-anchor
/// regression (launch argument `UITEST_SESSION_SCROLL_FIXTURE`).
///
/// A long session (40 short turns, far taller than the viewport) and a short
/// session are served by a stub `APIClientProtocol`, so `selectSession`
/// round-trips work fully offline: the UI test can switch away and back
/// without a live server, and the fixture messages survive the reload.
enum SessionScrollFixture {
    static let longSessionID = "scroll-long-session"
    static let shortSessionID = "scroll-short-session"
    static let longMessageCount = 40

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_SESSION_SCROLL_FIXTURE")
    }

    static func messageLabel(_ index: Int) -> String {
        String(format: "Long message %03d", index)
    }

    /// Last user message of the long session. User text renders as a single
    /// plain Text, so it is a stable on-screen anchor for UI assertions.
    static let bottomAnchorLabel = "Long message 039"
    /// First message of the long session — the top anchor.
    static let topAnchorLabel = "Long message 001"

    static func makeAppState() -> AppState {
        AppState(apiClient: StubClient())
    }

    static func apply(to state: AppState) {
        state.isConnected = true
        state.selectedTab = RootTab.chat.rawValue
        state.sessions = makeSessions()
        state.currentSessionID = longSessionID
        state.expandedSessionIDs = [longSessionID, shortSessionID]
        state.messages = makeLongMessages()
    }

    static func makeSessions() -> [Session] {
        [
            Session(
                id: longSessionID,
                slug: longSessionID,
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Long Scroll Session",
                version: "1",
                time: .init(created: 0, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            ),
            Session(
                id: shortSessionID,
                slug: shortSessionID,
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Short Session",
                version: "1",
                time: .init(created: 0, updated: 1_500, archived: nil),
                share: nil,
                summary: nil
            ),
        ]
    }

    static func makeLongMessages() -> [MessageWithParts] {
        (1...longMessageCount).map { index in
            let isUser = index % 2 == 1
            let info = Message(
                id: isUser ? "scroll-user-\(index)" : "scroll-assistant-\(index)",
                sessionID: longSessionID,
                role: isUser ? "user" : "assistant",
                parentID: isUser ? nil : "scroll-user-\(index - 1)",
                providerID: isUser ? nil : "openai",
                modelID: isUser ? nil : "gpt-5.6-sol",
                model: nil,
                error: nil,
                time: .init(created: 1_000 + index, completed: 1_000 + index),
                finish: isUser ? nil : "stop",
                tokens: nil,
                cost: nil
            )
            let part = UITestFixtures.decodePart([
                "id": "scroll-part-\(index)",
                "messageID": info.id,
                "sessionID": longSessionID,
                "type": "text",
                "text": messageLabel(index),
            ])
            return MessageWithParts(info: info, parts: [part])
        }
    }

    static func makeShortMessages() -> [MessageWithParts] {
        let user = Message(
            id: "scroll-short-user",
            sessionID: shortSessionID,
            role: "user",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 1_000, completed: 1_000),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        let assistant = Message(
            id: "scroll-short-assistant",
            sessionID: shortSessionID,
            role: "assistant",
            parentID: user.id,
            providerID: "openai",
            modelID: "gpt-5.6-sol",
            model: nil,
            error: nil,
            time: .init(created: 1_100, completed: 1_200),
            finish: "stop",
            tokens: nil,
            cost: nil
        )
        return [
            MessageWithParts(info: user, parts: [UITestFixtures.decodePart([
                "id": "scroll-short-user-part",
                "messageID": user.id,
                "sessionID": shortSessionID,
                "type": "text",
                "text": "Short question",
            ])]),
            MessageWithParts(info: assistant, parts: [UITestFixtures.decodePart([
                "id": "scroll-short-assistant-part",
                "messageID": assistant.id,
                "sessionID": shortSessionID,
                "type": "text",
                "text": "Short answer",
            ])]),
        ]
    }

    /// Fully offline `APIClientProtocol` stub. Read paths return the fixture
    /// data so `selectSession` round-trips succeed; write paths throw.
    actor StubClient: APIClientProtocol {
        private let sessions: [Session] = SessionScrollFixture.makeSessions()
        private let longMessages: [MessageWithParts] = SessionScrollFixture.makeLongMessages()
        private let shortMessages: [MessageWithParts] = SessionScrollFixture.makeShortMessages()

        func configure(baseURL: String, username: String?, password: String?) {}

        func health() async throws -> HealthResponse {
            try JSONDecoder().decode(HealthResponse.self, from: Data("{\"healthy\":true,\"version\":\"fixture\"}".utf8))
        }

        func projects() async throws -> [Project] { [] }
        func projectCurrent() async throws -> Project? { nil }

        func sessions(directory: String?, limit: Int) async throws -> [Session] {
            sessions
        }

        func session(sessionID: String) async throws -> Session {
            guard let match = sessions.first(where: { $0.id == sessionID }) else {
                throw APIError.httpError(statusCode: 404, data: Data())
            }
            return match
        }

        func createSession(title: String?, directory: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }

        func updateSession(sessionID: String, title: String) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }

        func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }

        func deleteSession(sessionID: String) async throws {
            throw APIError.httpError(statusCode: 501, data: Data())
        }

        func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] {
            switch sessionID {
            case SessionScrollFixture.longSessionID: return longMessages
            case SessionScrollFixture.shortSessionID: return shortMessages
            default: return []
            }
        }

        func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {
            throw APIError.httpError(statusCode: 501, data: Data())
        }

        func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
            throw APIError.httpError(statusCode: 501, data: Data())
        }

        func abort(sessionID: String) async throws {}

        func sessionStatus() async throws -> [String: SessionStatus] { [:] }
        func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
        func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
        func pendingQuestions() async throws -> [QuestionRequest] { [] }
        func replyQuestion(requestID: String, answers: [[String]]) async throws {}
        func rejectQuestion(requestID: String) async throws {}

        func providers() async throws -> ProvidersResponse {
            try JSONDecoder().decode(ProvidersResponse.self, from: Data("{\"providers\":[]}".utf8))
        }

        func providerRegistry() async throws -> ProviderRegistryResponse {
            ProviderRegistryResponse(providers: [], connectedProviderIDs: [])
        }

        func agents() async throws -> [AgentInfo] { [] }
        func sessionDiff(sessionID: String) async throws -> [FileDiff] { [] }
        func sessionTodos(sessionID: String) async throws -> [TodoItem] { [] }
        func fileList(path: String, directory: String?) async throws -> [FileNode] { [] }

        func fileContent(path: String, directory: String?) async throws -> FileContent {
            FileContent(type: "text", content: "")
        }

        func findFile(query: String, limit: Int) async throws -> [String] { [] }
        func fileStatus() async throws -> [FileStatusEntry] { [] }

        func forkSession(sessionID: String, messageID: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }

        func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
    }
}
