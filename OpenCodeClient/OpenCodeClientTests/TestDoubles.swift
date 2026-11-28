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
func makeIsolatedUserDefaults() -> UserDefaults {
    let name = "opencode.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
func makeIsolatedAppState(
    apiClient: APIClientProtocol = MockAPIClient(),
    sseClient: SSEClientProtocol = MockSSEClient(),
    sshTunnelManager: SSHTunnelManager? = nil,
    aiUsageQuotaClient: AIUsageQuotaClientProtocol? = nil,
    carSpeechOutput: CarSpeechOutputProviding? = nil,
    deepLinkSessionResolver: ((String) async throws -> Session)? = nil,
    deepLinkHydratesSelection: Bool = true,
    clientCapabilityStore: ClientCapabilityCallbackStore = .applicationSupport(),
    clientCapabilityURLOpener: (@MainActor (URL) async -> Bool)? = nil,
    userDefaults: UserDefaults? = nil,
    hostCredentialAccess: HostCredentialAccess = .noExternal
) -> AppState {
    let defaults = userDefaults ?? makeIsolatedUserDefaults()
    return AppState(
        apiClient: apiClient,
        sseClient: sseClient,
        sshTunnelManager: sshTunnelManager ?? SSHTunnelManager(defaults: defaults),
        aiUsageQuotaClient: aiUsageQuotaClient ?? AIUsageQuotaClient(),
        carSpeechOutput: carSpeechOutput,
        deepLinkSessionResolver: deepLinkSessionResolver,
        deepLinkHydratesSelection: deepLinkHydratesSelection,
        clientCapabilityStore: clientCapabilityStore,
        clientCapabilityURLOpener: clientCapabilityURLOpener,
        userDefaults: defaults,
        hostCredentialAccess: hostCredentialAccess
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
    /// nil keeps `/experimental/session` unsupported, as on legacy hosts.
    var activeSessionPages: [Int?: SessionPage]?
    var archivedSessionPages: [Int?: SessionPage] = [:]
    /// `archived=true&roots=true` pages, the restored-root scan.
    var restoredRootPages: [Int?: SessionPage] = [:]
    var sessionPageError: Error?
    /// nil makes `GET /path` unsupported, as on the DSH shim.
    var instanceDirectoryResult: String?
    var sessionChildrenError: Error?
    var sessionPageRequests: [SessionPageRequest] = []
    /// Restored-root scans (`archived=true&roots=true`), kept apart from active and archived paging.
    var restoredScanRequests: [SessionPageRequest] = []

    struct SessionPageRequest: Equatable {
        var directory: String?
        var includeArchived: Bool
        var rootsOnly: Bool
        var cursor: Int?
    }
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
    var createSessionCalls: [(title: String?, directory: String?)] = []
    private var suspendCreateSession = false
    private var createSessionWaiters: [CheckedContinuation<Void, Never>] = []
    private var createSessionObservers: [CheckedContinuation<Void, Never>] = []
    private var suspendPromptStructured = false
    private var promptStructuredWaiters: [CheckedContinuation<Void, Never>] = []
    private var promptStructuredObservers: [CheckedContinuation<Void, Never>] = []
    var projectCurrentResult: Project?
    var projectCurrentError: Error?
    private var suspendProjectCurrent = false
    private var projectCurrentWaiters: [CheckedContinuation<Void, Never>] = []
    private var projectCurrentObservers: [CheckedContinuation<Void, Never>] = []
    var sessionResult: Session?
    var sessionError: Error?
    var sessionRequests: [String] = []
    var deletedSessionIDs: [String] = []
    var deleteSessionError: Error?
    var agentsResult: [AgentInfo] = []
    var agentsError: Error?
    var updateSessionCalls: [(String, String)] = []
    var updateSessionArchivedCalls: [(String, Int)] = []
    var archiveFailureIDs: Set<String> = []
    func setArchiveFailureIDs(_ ids: Set<String>) { archiveFailureIDs = ids }
    private var archiveMissingIDs: Set<String> = []
    func setArchiveMissingIDs(_ ids: Set<String>) { archiveMissingIDs = ids }
    private var archiveChildren: [Session] = []
    func setArchiveChildren(_ children: [Session]) { archiveChildren = children }
    func setActiveSessionPages(_ pages: [Int?: SessionPage]?) { activeSessionPages = pages }
    func setArchivedSessionPages(_ pages: [Int?: SessionPage]) { archivedSessionPages = pages }
    func setRestoredRootPages(_ pages: [Int?: SessionPage]) { restoredRootPages = pages }
    func setSessionPageError(_ error: Error?) { sessionPageError = error }
    func setInstanceDirectoryResult(_ directory: String?) { instanceDirectoryResult = directory }
    func setSessionChildrenError(_ error: Error?) { sessionChildrenError = error }
    private var onArchiveChildren: (@Sendable () async -> Void)?
    func setOnArchiveChildren(_ hook: @escaping @Sendable () async -> Void) { onArchiveChildren = hook }
    var sessionDiffResult: [FileDiff] = []
    var sessionDiffCallCount = 0
    var fileListResults: [String: [FileNode]] = [:]
    var fileListRequests: [(path: String, directory: String?)] = []
    var fileContentRequests: [(path: String, directory: String?)] = []
    var abortSessionIDs: [String] = []
    var indicatorStatuses: [String: SessionStatus] = [:]
    var indicatorPermissions: [APIClient.PermissionRequest] = []
    var indicatorQuestions: [QuestionRequest] = []
    var suspendIndicatorRequests = false
    var indicatorRequestCount = 0
    var indicatorWaiters: [CheckedContinuation<Void, Never>] = []
    var indicatorRequestsFail = false
    func setIndicatorRequestsFail(_ fail: Bool) { indicatorRequestsFail = fail }

    func configureIndicators(statuses: [String: SessionStatus] = [:], permissions: [APIClient.PermissionRequest] = [], questions: [QuestionRequest] = [], suspended: Bool = false) {
        indicatorStatuses = statuses
        indicatorPermissions = permissions
        indicatorQuestions = questions
        suspendIndicatorRequests = suspended
    }

    func resumeIndicatorRequests() {
        suspendIndicatorRequests = false
        let waiters = indicatorWaiters
        indicatorWaiters = []
        waiters.forEach { $0.resume() }
    }

    func resumeFirstIndicatorRequest() {
        guard !indicatorWaiters.isEmpty else { return }
        indicatorWaiters.removeFirst().resume()
    }

    private func indicatorGate() async {
        indicatorRequestCount += 1
        if suspendIndicatorRequests {
            await withCheckedContinuation { indicatorWaiters.append($0) }
        }
    }

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

    func setSuspendCreateSession(_ value: Bool) {
        suspendCreateSession = value
    }

    func setSuspendPromptStructured(_ value: Bool) {
        suspendPromptStructured = value
    }

    func waitUntilCreateSessionPending(_ count: Int) async {
        while createSessionWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                createSessionObservers.append(cont)
            }
        }
    }

    func waitUntilPromptStructuredPending(_ count: Int) async {
        while promptStructuredWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                promptStructuredObservers.append(cont)
            }
        }
    }

    func releaseCreateSession() {
        suspendCreateSession = false
        let pending = createSessionWaiters
        createSessionWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func releasePromptStructured() {
        suspendPromptStructured = false
        let pending = promptStructuredWaiters
        promptStructuredWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func setProjectCurrentResult(_ project: Project?) {
        projectCurrentResult = project
    }

    func setProjectCurrentError(_ error: Error?) {
        projectCurrentError = error
    }

    func setSuspendProjectCurrent(_ value: Bool) {
        suspendProjectCurrent = value
    }

    func waitUntilProjectCurrentPending(_ count: Int) async {
        while projectCurrentWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                projectCurrentObservers.append(cont)
            }
        }
    }

    func releaseProjectCurrent() {
        suspendProjectCurrent = false
        let pending = projectCurrentWaiters
        projectCurrentWaiters.removeAll()
        pending.forEach { $0.resume() }
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

    var healthCallCount = 0

    func health() async throws -> HealthResponse {
        healthCallCount += 1
        if let healthError { throw healthError }
        return healthResult
    }

    func projects() async throws -> [Project] { [] }
    func projectCurrent() async throws -> Project? {
        if suspendProjectCurrent {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                projectCurrentWaiters.append(cont)
                let pending = projectCurrentObservers
                projectCurrentObservers.removeAll()
                pending.forEach { $0.resume() }
            }
        }
        if let projectCurrentError { throw projectCurrentError }
        return projectCurrentResult
    }
    func sessions(directory: String?, limit: Int) async throws -> [Session] {
        sessionLimitRequests.append(limit)
        return sessionsByLimit[limit] ?? sessionsResult
    }
    func sessionPage(directory: String?, includeArchived: Bool, rootsOnly: Bool, limit: Int, cursor: Int?) async throws -> SessionPage {
        let request = SessionPageRequest(directory: directory, includeArchived: includeArchived, rootsOnly: rootsOnly, cursor: cursor)
        if includeArchived && rootsOnly { restoredScanRequests.append(request) } else { sessionPageRequests.append(request) }
        if let sessionPageError { throw sessionPageError }
        guard let activeSessionPages else { throw URLError(.unsupportedURL) }
        let pages = includeArchived ? (rootsOnly ? restoredRootPages : archivedSessionPages) : activeSessionPages
        return pages[cursor] ?? SessionPage(rows: [], nextCursor: nil)
    }
    func session(sessionID: String) async throws -> Session {
        sessionRequests.append(sessionID)
        if let sessionError { throw sessionError }
        return sessionResult ?? createSessionResult
    }
    func createSession(title: String?, directory: String?) async throws -> Session {
        createSessionCalls.append((title, directory))
        if suspendCreateSession {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                createSessionWaiters.append(cont)
                let pending = createSessionObservers
                createSessionObservers.removeAll()
                pending.forEach { $0.resume() }
            }
        }
        return createSessionResult
    }

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
        if archiveMissingIDs.contains(sessionID) { throw APIError.httpError(statusCode: 404, data: Data()) }
        if archiveFailureIDs.contains(sessionID) { throw URLError(.networkConnectionLost) }
        archiveChildren.removeAll { $0.id == sessionID }
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

    func instanceDirectory() async throws -> String? {
        guard let instanceDirectoryResult else { throw URLError(.unsupportedURL) }
        return instanceDirectoryResult
    }

    func sessionChildren(sessionID: String) async throws -> [Session] {
        if let sessionChildrenError { throw sessionChildrenError }
        await onArchiveChildren?()
        return archiveChildren.filter { $0.parentID == sessionID }
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
        if suspendPromptStructured {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                promptStructuredWaiters.append(cont)
                let pending = promptStructuredObservers
                promptStructuredObservers.removeAll()
                pending.forEach { $0.resume() }
            }
        }
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
    func sessionStatus() async throws -> [String: SessionStatus] {
        let snapshot = indicatorStatuses
        await indicatorGate()
        if indicatorRequestsFail { throw URLError(.cannotConnectToHost) }
        return snapshot
    }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] {
        let snapshot = indicatorPermissions
        await indicatorGate()
        if indicatorRequestsFail { throw URLError(.cannotConnectToHost) }
        return snapshot
    }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {
        if indicatorRequestsFail { throw URLError(.cannotConnectToHost) }
        indicatorPermissions.removeAll { $0.id == permissionID && $0.sessionID == sessionID }
    }
    func pendingQuestions() async throws -> [QuestionRequest] {
        let snapshot = indicatorQuestions
        await indicatorGate()
        if indicatorRequestsFail { throw URLError(.cannotConnectToHost) }
        return snapshot
    }
    func replyQuestion(requestID: String, answers: [[String]]) async throws {
        if indicatorRequestsFail { throw URLError(.cannotConnectToHost) }
        indicatorQuestions.removeAll { $0.id == requestID }
    }
    func rejectQuestion(requestID: String) async throws {
        if indicatorRequestsFail { throw URLError(.cannotConnectToHost) }
        indicatorQuestions.removeAll { $0.id == requestID }
    }
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
    private var suspendSpeak = false
    private var speakWaiters: [CheckedContinuation<Void, Never>] = []
    private var speakObservers: [CheckedContinuation<Void, Never>] = []

    func setSuspendSpeak(_ value: Bool) {
        suspendSpeak = value
    }

    func waitUntilSpeakPending(_ count: Int) async {
        while speakWaiters.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                speakObservers.append(cont)
            }
        }
    }

    func releaseSpeak() {
        suspendSpeak = false
        resumeSpeakWaiters()
    }

    func speak(_ text: String) async {
        spokenTexts.append(text)
        if suspendSpeak {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                speakWaiters.append(cont)
                let pending = speakObservers
                speakObservers.removeAll()
                pending.forEach { $0.resume() }
            }
        }
    }

    func stop() {
        stopCount += 1
        resumeSpeakWaiters()
    }

    private func resumeSpeakWaiters() {
        let pending = speakWaiters
        speakWaiters.removeAll()
        pending.forEach { $0.resume() }
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
