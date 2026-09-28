//
//  TestDoubles.swift
//  OpenCodeClientTests
//

import Foundation
@testable import OpenCodeClient

/// Realistic model list used to seed the device-local shortlist in tests.
/// Mirrors the historical default preset set. The app no longer ships a
/// hardcoded default list — the chat picker is the user-managed `modelShortlist`
/// and the settings catalog is pulled live from the `/provider` registry — so
/// this lives only in the test target as a seeding fixture.
let testSeedPresets: [ModelPreset] = [
    ModelPreset(displayName: "GLM-5.3", providerID: "zai-coding-plan", modelID: "glm-5.3"),
    ModelPreset(displayName: "GPT-5.6 Sol", providerID: "openai", modelID: "gpt-5.6-sol"),
    ModelPreset(displayName: "Gemini 3.7 Flash", providerID: "google", modelID: "gemini-3.7-flash"),
    ModelPreset(displayName: "DeepSeek Local", providerID: "ds4", modelID: "deepseek-v4-flash"),
    ModelPreset(displayName: "Ollama GLM 5.2", providerID: "ollama-cloud", modelID: "glm-5.2"),
    ModelPreset(displayName: "GPT-5.6 Terra Fast", providerID: "openai", modelID: "gpt-5.6-terra-fast"),
    ModelPreset(displayName: "GPT-5.6 Luna", providerID: "openai", modelID: "gpt-5.6-luna"),
    ModelPreset(displayName: "Grok 4.7", providerID: "xai", modelID: "grok-4.7"),
    ModelPreset(displayName: "Qwen 3.8 27B", providerID: "qwen38", modelID: "qwen3.8-27b"),
]

@MainActor
func makeIsolatedAppState(
    apiClient: APIClientProtocol = MockAPIClient(),
    sseClient: SSEClientProtocol = MockSSEClient(),
    sshTunnelManager: SSHTunnelManager? = nil,
    aiUsageQuotaClient: AIUsageQuotaClientProtocol? = nil,
    carSpeechOutput: CarSpeechOutputProviding? = nil
) -> AppState {
    let defaults = UserDefaults(suiteName: "opencode.tests.\(UUID().uuidString)")!
    return AppState(
        apiClient: apiClient,
        sseClient: sseClient,
        sshTunnelManager: sshTunnelManager ?? SSHTunnelManager(),
        aiUsageQuotaClient: aiUsageQuotaClient ?? AIUsageQuotaClient(),
        carSpeechOutput: carSpeechOutput,
        userDefaults: defaults
    )
}

actor MockAPIClient: APIClientProtocol {
    var configuredBaseURL: String?
    var configuredUsername: String?
    var configuredPassword: String?

    var healthResult = HealthResponse(healthy: true, version: "test-version")
    var healthError: Error?
    var sessionsResult: [Session] = []
    var sessionsByLimit: [Int: [Session]] = [:]
    var sessionLimitRequests: [Int] = []
    var createSessionResult = Session(
        id: "created-session",
        slug: "created-session",
        projectID: "p1",
        directory: "/tmp",
        parentID: nil,
        title: "Created",
        version: "1",
        time: .init(created: 1, updated: 1, archived: nil),
        share: nil,
        summary: nil
    )
    var forkSessionResult = Session(
        id: "forked-session",
        slug: "forked-session",
        projectID: "p1",
        directory: "/tmp",
        parentID: "original-session",
        title: "Original (fork #1)",
        version: "1",
        time: .init(created: 2, updated: 2, archived: nil),
        share: nil,
        summary: nil
    )
    var forkSessionError: Error?
    var forkSessionCalls: [(String, String?)] = []
    var revertSessionResult = Session(
        id: "s1",
        slug: "s1",
        projectID: "p1",
        directory: "/tmp",
        parentID: nil,
        title: "Session",
        version: "1",
        time: .init(created: 2, updated: 3, archived: nil),
        share: nil,
        summary: nil
    )
    var revertSessionError: Error?
    var revertSessionCalls: [(String, String, String?)] = []
    var messagesResult: [MessageWithParts] = []
    var messagesByLimit: [Int: [MessageWithParts]] = [:]
    var messageLimitRequests: [Int?] = []
    var messagesCallCount = 0
    var promptError: Error?
        var promptAsyncCalls: [(String, String, [ComposerImageAttachment])] = []
        var promptAsyncMessageIDs: [String] = []
        var promptAsyncAgents: [String] = []
    var promptStructuredCalls: [(sessionID: String, messageID: String?, text: String, system: String, agent: String, providerID: String, modelID: String)] = []
    var promptStructuredResult: MessageWithParts?
    var promptStructuredDelayNanoseconds: UInt64 = 0
    var sessionResult: Session?
    var sessionError: Error?
    var sessionRequests: [String] = []
    var deletedSessionIDs: [String] = []
    var deleteSessionError: Error?
    var agentsResult: [AgentInfo] = []
    var agentsError: Error?
    var updateSessionCalls: [(String, String)] = []
    var updateSessionArchivedCalls: [(String, Int)] = []
    var sessionDiffResult: [FileDiff] = []
    var sessionDiffCallCount = 0
    var fileListResults: [String: [FileNode]] = [:]
    var fileListRequests: [(path: String, directory: String?)] = []
    var fileContentRequests: [(path: String, directory: String?)] = []
    var abortSessionIDs: [String] = []

    func setHealthError(_ error: Error?) {
        healthError = error
    }

    func setSessionsResult(_ sessions: [Session]) {
        sessionsResult = sessions
    }

    func setSessionsResult(_ sessions: [Session], forLimit limit: Int) {
        sessionsByLimit[limit] = sessions
    }

    func setCreateSessionResult(_ session: Session) {
        createSessionResult = session
    }

    func setSessionResult(_ session: Session) {
        sessionResult = session
    }

    func setMessagesResult(_ messages: [MessageWithParts]) {
        messagesResult = messages
    }

    func setMessagesResult(_ messages: [MessageWithParts], forLimit limit: Int) {
        messagesByLimit[limit] = messages
    }

    func setSessionDiffResult(_ diffs: [FileDiff]) {
        sessionDiffResult = diffs
    }

    func setFileListResult(_ nodes: [FileNode], forPath path: String) {
        fileListResults[path] = nodes
    }

    func setPromptError(_ error: Error?) {
        promptError = error
    }

    func setDeleteSessionError(_ error: Error?) {
        deleteSessionError = error
    }

    func setAgentsResult(_ agents: [AgentInfo]) {
        agentsResult = agents
    }

    func setAgentsError(_ error: Error?) {
        agentsError = error
    }

    func setPromptStructuredResult(_ result: MessageWithParts) {
        promptStructuredResult = result
    }

    func setPromptStructuredDelayNanoseconds(_ value: UInt64) {
        promptStructuredDelayNanoseconds = value
    }

    func setSessionError(_ error: Error?) {
        sessionError = error
    }

    func setForkSessionResult(_ session: Session) {
        forkSessionResult = session
    }

    func setForkSessionError(_ error: Error?) {
        forkSessionError = error
    }

    func setRevertSessionResult(_ session: Session) {
        revertSessionResult = session
    }

    func setRevertSessionError(_ error: Error?) {
        revertSessionError = error
    }

    func configure(baseURL: String, username: String?, password: String?) {
        configuredBaseURL = baseURL
        configuredUsername = username
        configuredPassword = password
    }

    func health() async throws -> HealthResponse {
        if let healthError { throw healthError }
        return healthResult
    }

    func projects() async throws -> [Project] { [] }
    func projectCurrent() async throws -> Project? { nil }
    func sessions(directory: String?, limit: Int) async throws -> [Session] {
        sessionLimitRequests.append(limit)
        return sessionsByLimit[limit] ?? sessionsResult
    }
    func session(sessionID: String) async throws -> Session {
        sessionRequests.append(sessionID)
        if let sessionError { throw sessionError }
        return sessionResult ?? createSessionResult
    }
    func createSession(title: String?, directory: String?) async throws -> Session { createSessionResult }

    func updateSession(sessionID: String, title: String) async throws -> Session {
        updateSessionCalls.append((sessionID, title))
        return Session(
            id: sessionID,
            slug: sessionID,
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: title,
            version: "1",
            time: .init(created: 1, updated: 1, archived: nil),
            share: nil,
            summary: nil
        )
    }

    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
        updateSessionArchivedCalls.append((sessionID, archived))
        return Session(
            id: sessionID,
            slug: sessionID,
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: sessionID,
            version: "1",
            time: .init(created: 1, updated: 1, archived: archived),
            share: nil,
            summary: nil
        )
    }

    func deleteSession(sessionID: String) async throws {
        if let deleteSessionError { throw deleteSessionError }
        deletedSessionIDs.append(sessionID)
    }

    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] {
        messagesCallCount += 1
        messageLimitRequests.append(limit)
        if let limit, let messages = messagesByLimit[limit] { return messages }
        return messagesResult
    }

    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {
        promptAsyncCalls.append((sessionID, text, attachments))
        promptAsyncMessageIDs.append(messageID)
        promptAsyncAgents.append(agent)
        if let promptError { throw promptError }
    }

    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
        promptStructuredCalls.append((sessionID, messageID, text, system, agent, model.providerID, model.modelID))
        if promptStructuredDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: promptStructuredDelayNanoseconds)
        }
        if let promptError { throw promptError }
        guard let promptStructuredResult else { throw CarModeError.invalidResponse }
        return promptStructuredResult
    }

    func abort(sessionID: String) async throws {
        abortSessionIDs.append(sessionID)
    }
    func sessionStatus() async throws -> [String: SessionStatus] { [:] }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
    func pendingQuestions() async throws -> [QuestionRequest] { [] }
    func replyQuestion(requestID: String, answers: [[String]]) async throws {}
    func rejectQuestion(requestID: String) async throws {}
    func providers() async throws -> ProvidersResponse {
        try JSONDecoder().decode(ProvidersResponse.self, from: Data("{\"providers\":[]}".utf8))
    }
    var providerRegistryResult: ProviderRegistryResponse?
    func providerRegistry() async throws -> ProviderRegistryResponse {
        providerRegistryResult ?? ProviderRegistryResponse(providers: [], connectedProviderIDs: [])
    }
    func agents() async throws -> [AgentInfo] {
        if let agentsError { throw agentsError }
        return agentsResult
    }
    func sessionDiff(sessionID: String) async throws -> [FileDiff] {
        sessionDiffCallCount += 1
        return sessionDiffResult
    }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] { [] }
    func fileList(path: String, directory: String?) async throws -> [FileNode] {
        fileListRequests.append((path, directory))
        return fileListResults[path] ?? []
    }
    func fileContent(path: String, directory: String?) async throws -> FileContent {
        fileContentRequests.append((path, directory))
        return FileContent(type: "text", content: "")
    }
    func findFile(query: String, limit: Int) async throws -> [String] { [] }
    func fileStatus() async throws -> [FileStatusEntry] { [] }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session {
        forkSessionCalls.append((sessionID, messageID))
        if let forkSessionError { throw forkSessionError }
        return forkSessionResult
    }

    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
        revertSessionCalls.append((sessionID, messageID, partID))
        if let revertSessionError { throw revertSessionError }
        return revertSessionResult
    }
}

@MainActor
final class MockCarSpeechOutput: CarSpeechOutputProviding {
    var spokenTexts: [String] = []
    var stopCount = 0

    func speak(_ text: String) async {
        spokenTexts.append(text)
    }

    func stop() {
        stopCount += 1
    }
}

actor MockSSEClient: SSEClientProtocol {
    var stream = AsyncThrowingStream<SSEEvent, Error> { continuation in
        continuation.finish()
    }

    func connect(baseURL: String, username: String?, password: String?) -> AsyncThrowingStream<SSEEvent, Error> {
        stream
    }
}
