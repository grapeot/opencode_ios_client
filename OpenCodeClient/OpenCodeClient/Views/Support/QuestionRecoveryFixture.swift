import Foundation

@MainActor
@Observable
final class QuestionRecoveryProbe {
    static let shared = QuestionRecoveryProbe()
    var recorded = ""
}

enum QuestionRecoveryFixture {
    static let argument = "UITEST_QUESTION_RECOVERY_FIXTURE"
    static let sessionID = "question-recovery-session"
    static let targetID = "q-target"
    static let otherID = "q-other"
    static let optionLabel = "Build"
    static let customAnswer = "kept-answer"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func makeAppState() -> AppState {
        L10n.languagePreference = .en
        return AppState(
            apiClient: StubClient(),
            userDefaults: UserDefaults(suiteName: "opencode.uitest.question-recovery.\(UUID().uuidString)")!
        )
    }

    static func apply(to state: AppState) {
        state.isConnected = true
        state.selectedTab = RootTab.chat.rawValue
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp/question-recovery",
                parentID: nil,
                title: "Question Recovery",
                version: "1",
                time: .init(created: 1, updated: 2, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        let user = Message(
            id: "q-user",
            sessionID: sessionID,
            role: "user",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 1, completed: nil),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        let part = UITestFixtures.decodePart([
            "id": "q-user-text",
            "messageID": user.id,
            "sessionID": sessionID,
            "type": "text",
            "text": "Q",
        ])
        state.messages = [MessageWithParts(info: user, parts: [part])]
        state.pendingQuestions = [targetRequest, otherRequest]
    }

    static var targetRequest: QuestionRequest {
        QuestionRequest(
            id: targetID,
            sessionID: sessionID,
            questions: [
                QuestionInfo(
                    question: "Color?",
                    header: "Color",
                    options: [QuestionOption(label: optionLabel, description: "B")],
                    multiple: true,
                    custom: true
                )
            ],
            tool: nil
        )
    }

    static var otherRequest: QuestionRequest {
        QuestionRequest(
            id: otherID,
            sessionID: sessionID,
            questions: [
                QuestionInfo(
                    question: "Leave this card",
                    header: "Other",
                    options: [QuestionOption(label: "Stay", description: "S")],
                    multiple: false,
                    custom: false
                )
            ],
            tool: nil
        )
    }

    actor StubClient: APIClientProtocol {
        private var remainingFailures = 1

        func replyQuestion(requestID: String, answers: [[String]]) async throws {
            let recorded = answers.map { $0.joined(separator: "+") }.joined(separator: "/")
            await MainActor.run { QuestionRecoveryProbe.shared.recorded = recorded }
            try await Task.sleep(nanoseconds: 3_000_000_000)
            if remainingFailures > 0 {
                remainingFailures -= 1
                throw APIError.httpError(statusCode: 503, data: Data("unavailable".utf8))
            }
        }

        func configure(baseURL: String, username: String?, password: String?) {}
        func health() async throws -> HealthResponse {
            HealthResponse(healthy: true, version: "fixture")
        }
        func projects() async throws -> [Project] { [] }
        func projectCurrent() async throws -> Project? { nil }
        func sessions(directory: String?, limit: Int) async throws -> [Session] { [] }
        func session(sessionID: String) async throws -> Session {
            throw APIError.httpError(statusCode: 404, data: Data())
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
        func deleteSession(sessionID: String) async throws {}
        func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] { [] }
        func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {}
        func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func abort(sessionID: String) async throws {}
        func sessionStatus() async throws -> [String: SessionStatus] { [:] }
        func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
        func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
        func pendingQuestions() async throws -> [QuestionRequest] { [] }
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
