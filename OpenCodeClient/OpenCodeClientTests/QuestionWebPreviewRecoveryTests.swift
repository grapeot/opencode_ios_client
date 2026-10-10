import Foundation
import Testing
@testable import OpenCodeClient

struct QuestionWebPreviewRecoveryTests {
    @Test @MainActor func questionSubmitFailureThenSuccessKeepsRequestUntilSuccess() async {
        let api = QuestionReplyScript(failuresBeforeSuccess: 1)
        let state = makeIsolatedAppState(apiClient: api)
        let request = QuestionRequest(
            id: "q-multi",
            sessionID: "s1",
            questions: [
                QuestionInfo(
                    question: "Color?",
                    header: "Color",
                    options: [QuestionOption(label: "Red", description: "R")],
                    multiple: false,
                    custom: false
                )
            ],
            tool: nil
        )
        let other = QuestionRequest(id: "q-other", sessionID: "s1", questions: [], tool: nil)
        state.pendingQuestions = [request, other]
        let answers = [["Red"], ["kept-answer"]]

        let first = await state.respondQuestion(request, answers: answers)
        #expect(first == false)
        #expect(state.connectionError == "HTTP 503: unavailable")
        #expect(state.pendingQuestions.map(\.id) == ["q-multi", "q-other"])
        #expect(await api.recordedAnswers() == [answers])

        let second = await state.respondQuestion(request, answers: answers)
        #expect(second == true)
        #expect(state.pendingQuestions.map(\.id) == ["q-other"])
        #expect(await api.recordedAnswers() == [answers, answers])
    }
}

private actor QuestionReplyScript: APIClientProtocol {
    private var remainingFailures: Int
    private var sent: [[[String]]] = []

    init(failuresBeforeSuccess: Int) {
        remainingFailures = failuresBeforeSuccess
    }

    func recordedAnswers() -> [[[String]]] { sent }

    func replyQuestion(requestID: String, answers: [[String]]) async throws {
        sent.append(answers)
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw APIError.httpError(statusCode: 503, data: Data("unavailable".utf8))
        }
    }

    func configure(baseURL: String, username: String?, password: String?) {}
    func health() async throws -> HealthResponse { fatalError("unused") }
    func projects() async throws -> [Project] { fatalError("unused") }
    func projectCurrent() async throws -> Project? { fatalError("unused") }
    func sessions(directory: String?, limit: Int) async throws -> [Session] { fatalError("unused") }
    func session(sessionID: String) async throws -> Session { fatalError("unused") }
    func createSession(title: String?, directory: String?) async throws -> Session { fatalError("unused") }
    func updateSession(sessionID: String, title: String) async throws -> Session { fatalError("unused") }
    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session { fatalError("unused") }
    func deleteSession(sessionID: String) async throws { fatalError("unused") }
    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] { fatalError("unused") }
    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws { fatalError("unused") }
    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts { fatalError("unused") }
    func abort(sessionID: String) async throws { fatalError("unused") }
    func sessionStatus() async throws -> [String: SessionStatus] { fatalError("unused") }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { fatalError("unused") }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws { fatalError("unused") }
    func pendingQuestions() async throws -> [QuestionRequest] { fatalError("unused") }
    func rejectQuestion(requestID: String) async throws { fatalError("unused") }
    func providers() async throws -> ProvidersResponse { fatalError("unused") }
    func providerRegistry() async throws -> ProviderRegistryResponse { fatalError("unused") }
    func agents() async throws -> [AgentInfo] { fatalError("unused") }
    func sessionDiff(sessionID: String) async throws -> [FileDiff] { fatalError("unused") }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] { fatalError("unused") }
    func fileList(path: String, directory: String?) async throws -> [FileNode] { fatalError("unused") }
    func fileContent(path: String, directory: String?) async throws -> FileContent { fatalError("unused") }
    func findFile(query: String, limit: Int) async throws -> [String] { fatalError("unused") }
    func fileStatus() async throws -> [FileStatusEntry] { fatalError("unused") }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session { fatalError("unused") }
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session { fatalError("unused") }
}
