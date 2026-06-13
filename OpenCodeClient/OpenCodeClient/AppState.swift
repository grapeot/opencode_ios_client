//
//  AppState.swift
//  OpenCodeClient
//

import Foundation
import CryptoKit
import Observation
import os
import VoiceFlowKit

struct SessionNode: Identifiable {
    let session: Session
    let children: [SessionNode]
    var id: String { session.id }
}

@Observable
@MainActor
final class AppState {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "AppState"
    )

    struct ServerURLInfo {
        let raw: String
        let normalized: String?
        let scheme: String?
        let host: String?
        let isLocal: Bool
        /// Tailscale MagicDNS (*.ts.net) — ATS exception, HTTP allowed.
        let isTailscale: Bool
        let isAllowed: Bool
        let warning: String?
    }

    /// Ensures server URL has http:// or https:// prefix. Returns normalized string if missing scheme, nil otherwise.
    /// Call after correctMalformedServerURL. Ensures the stored/displayed value is explicit and avoids URL parsing quirks.
    nonisolated static func ensureServerURLHasScheme(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") else { return nil }
        return "http://\(trimmed)"
    }

    /// Fixes malformed "host://host:port" (e.g. from iOS .textContentType(.URL) autocorrect or paste).
    /// Returns corrected string if malformed, nil otherwise.
    nonisolated static func correctMalformedServerURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = trimmed.range(of: "://") else { return nil }
        let beforeScheme = String(trimmed[..<idx.lowerBound])
        let afterScheme = String(trimmed[idx.upperBound...])
        guard afterScheme.hasPrefix(beforeScheme), beforeScheme != "http", beforeScheme != "https" else { return nil }
        return beforeScheme + afterScheme.dropFirst(beforeScheme.count)
    }

    /// LAN allows HTTP; WAN requires HTTPS.
    nonisolated static func serverURLInfo(_ raw: String) -> ServerURLInfo {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let corrected = Self.correctMalformedServerURL(trimmed) {
            trimmed = corrected
        }
        guard !trimmed.isEmpty else {
            return .init(raw: raw, normalized: nil, scheme: nil, host: nil, isLocal: true, isTailscale: false, isAllowed: false, warning: L10n.t(.errorServerAddressEmpty))
        }

        func parseHost(_ s: String) -> String? {
            if let u = URL(string: s), let h = u.host { return h }
            if let u = URL(string: "http://\(s)"), let h = u.host { return h }
            return nil
        }

        func isPrivateIPv4(_ host: String) -> Bool {
            let parts = host.split(separator: ".")
            guard parts.count == 4,
                  let a = Int(parts[0]), let b = Int(parts[1]) else { return false }
            if a == 10 || a == 127 { return true }
            if a == 192 && b == 168 { return true }
            if a == 172 && (16...31).contains(b) { return true }
            if a == 169 && b == 254 { return true }
            if host == "0.0.0.0" { return true }
            return false
        }

        let hasScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        let host = parseHost(trimmed)
        let isLocal: Bool = {
            guard let host else { return true }
            if host == "localhost" { return true }
            if host.hasSuffix(".local") { return true }
            if isPrivateIPv4(host) { return true }
            return false
        }()

        let scheme: String = {
            if let u = URL(string: trimmed), let s = u.scheme { return s }
            return isLocal ? "http" : "https"
        }()

        let isTailscale = host?.hasSuffix(".ts.net") ?? false
        if scheme == "http", !isLocal, !isTailscale {
            return .init(
                raw: raw,
                normalized: hasScheme ? trimmed : nil,
                scheme: "http",
                host: host,
                isLocal: false,
                isTailscale: false,
                isAllowed: false,
                warning: L10n.t(.errorWanRequiresHttps)
            )
        }

        let normalized = hasScheme ? trimmed : "\(scheme)://\(trimmed)"
        let parsed = URL(string: normalized)
        return .init(
            raw: raw,
            normalized: normalized,
            scheme: parsed?.scheme,
            host: parsed?.host,
            isLocal: isLocal,
            isTailscale: isTailscale,
            isAllowed: parsed != nil,
            warning: parsed == nil ? L10n.t(.errorInvalidBaseURL) : (scheme == "http" && !isTailscale ? L10n.t(.errorUsingLanHttp) : nil)
        )
    }
    var _serverURL: String = APIClient.defaultServer
    var serverURL: String {
        get { _serverURL }
        set {
            _serverURL = newValue
            UserDefaults.standard.set(newValue, forKey: Self.serverURLKey)
        }
    }

    var _username: String = ""
    var username: String {
        get { _username }
        set {
            _username = newValue
            UserDefaults.standard.set(newValue, forKey: Self.usernameKey)
        }
    }

    var _password: String = ""
    var password: String {
        get { _password }
        set {
            _password = newValue
            if newValue.isEmpty {
                KeychainHelper.delete(Self.passwordKeychainKey)
            } else {
                KeychainHelper.save(newValue, forKey: Self.passwordKeychainKey)
            }
        }
    }

    static let serverURLKey = "serverURL"
    static let usernameKey = "username"
    static let passwordKeychainKey = "password"
    static let aiBuilderBaseURLKey = "aiBuilderBaseURL"
    static let aiBuilderTokenKeychainKey = "aiBuilderToken"
    static let aiBuilderCustomPromptKey = "aiBuilderCustomPrompt"
    static let aiBuilderTerminologyKey = "aiBuilderTerminology"
    static let aiBuilderLastOKSignatureKey = "aiBuilderLastOKSignature"
    static let aiBuilderLastOKTestedAtKey = "aiBuilderLastOKTestedAt"
    static let draftInputsBySessionKey = "draftInputsBySession"
    static let selectedModelBySessionKey = "selectedModelBySession"
    static let showArchivedSessionsKey = "showArchivedSessions"
    static let selectedProjectWorktreeKey = "selectedProjectWorktree"
    static let customProjectPathKey = "customProjectPath"

    init(
        apiClient: APIClientProtocol = APIClient(),
        sseClient: SSEClientProtocol = SSEClient(),
        sshTunnelManager: SSHTunnelManager? = nil
    ) {
        self.apiClient = apiClient
        self.sseClient = sseClient
        self.sshTunnelManager = sshTunnelManager ?? SSHTunnelManager()
        if let storedServer = UserDefaults.standard.string(forKey: Self.serverURLKey) {
            if storedServer == APIConstants.legacyDefaultServer {
                _serverURL = APIClient.defaultServer
                UserDefaults.standard.set(APIClient.defaultServer, forKey: Self.serverURLKey)
            } else {
                _serverURL = storedServer
            }
        } else {
            _serverURL = APIClient.defaultServer
        }
        _username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        _password = KeychainHelper.load(forKey: Self.passwordKeychainKey) ?? ""

        _aiBuilderBaseURL = UserDefaults.standard.string(forKey: Self.aiBuilderBaseURLKey) ?? "https://space.ai-builders.com/backend"
        _aiBuilderToken = KeychainHelper.load(forKey: Self.aiBuilderTokenKeychainKey) ?? ""
        _aiBuilderCustomPrompt = UserDefaults.standard.string(forKey: Self.aiBuilderCustomPromptKey) ?? Self.defaultAIBuilderCustomPrompt
        _aiBuilderTerminology = UserDefaults.standard.string(forKey: Self.aiBuilderTerminologyKey) ?? Self.defaultAIBuilderTerminology
        _showArchivedSessions = UserDefaults.standard.bool(forKey: Self.showArchivedSessionsKey)
        _selectedProjectWorktree = UserDefaults.standard.string(forKey: Self.selectedProjectWorktreeKey)
        _customProjectPath = UserDefaults.standard.string(forKey: Self.customProjectPathKey) ?? ""

        // Restore last known-good AI Builder connection state if token/baseURL unchanged.
        let storedSig = UserDefaults.standard.string(forKey: Self.aiBuilderLastOKSignatureKey)
        let currentSig = Self.aiBuilderSignature(baseURL: _aiBuilderBaseURL, token: _aiBuilderToken)
        if let storedSig, storedSig == currentSig, !currentSig.isEmpty {
            aiBuilderConnectionOK = true
            if let ts = UserDefaults.standard.object(forKey: Self.aiBuilderLastOKTestedAtKey) as? Double {
                aiBuilderLastTestedAt = Date(timeIntervalSince1970: ts)
            }
        }

        if let data = UserDefaults.standard.data(forKey: Self.draftInputsBySessionKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            draftInputsBySessionID = decoded
        }

        if let data = UserDefaults.standard.data(forKey: Self.selectedModelBySessionKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            selectedModelIDBySessionID = decoded
        }
    }

    // Unsent composer drafts per session.
    var draftInputsBySessionID: [String: String] = [:]

    // Selected model (providerID/modelID) per session.
    var selectedModelIDBySessionID: [String: String] = [:]

    static func aiBuilderSignature(baseURL: String, token: String) -> String {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !tok.isEmpty else { return "" }
        let input = "\(base)|\(tok)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var _aiBuilderBaseURL: String = "https://space.ai-builders.com/backend"
    var aiBuilderBaseURL: String {
        get { _aiBuilderBaseURL }
        set {
            _aiBuilderBaseURL = newValue
            UserDefaults.standard.set(newValue, forKey: Self.aiBuilderBaseURLKey)
            aiBuilderConnectionOK = false
            aiBuilderConnectionError = nil
            aiBuilderLastTestedAt = nil
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
        }
    }

    var _aiBuilderToken: String = ""
    var aiBuilderToken: String {
        get { _aiBuilderToken }
        set {
            _aiBuilderToken = newValue
            if newValue.isEmpty {
                KeychainHelper.delete(Self.aiBuilderTokenKeychainKey)
            } else {
                KeychainHelper.save(newValue, forKey: Self.aiBuilderTokenKeychainKey)
            }
            aiBuilderConnectionOK = false
            aiBuilderConnectionError = nil
            aiBuilderLastTestedAt = nil
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
        }
    }

    /// Default custom prompt for speech recognition. Instructs engine on filename style.
    static let defaultAIBuilderCustomPrompt = "All file and directory names should use snake_case (lowercase with underscores)."

    /// Default terminology (comma-separated) from workspace routing.
    static let defaultAIBuilderTerminology = "adhoc_jobs, life_consulting, survey_sessions, thought_review"

    var _aiBuilderCustomPrompt: String = ""
    var aiBuilderCustomPrompt: String {
        get { _aiBuilderCustomPrompt }
        set {
            _aiBuilderCustomPrompt = newValue
            UserDefaults.standard.set(newValue, forKey: Self.aiBuilderCustomPromptKey)
        }
    }

    var _aiBuilderTerminology: String = ""
    var aiBuilderTerminology: String {
        get { _aiBuilderTerminology }
        set {
            _aiBuilderTerminology = newValue
            UserDefaults.standard.set(newValue, forKey: Self.aiBuilderTerminologyKey)
        }
    }

    var aiBuilderConnectionError: String? = nil
    var aiBuilderConnectionOK: Bool = false
    var aiBuilderLastTestedAt: Date? = nil
    var isTestingAIBuilderConnection: Bool = false
    var isConnected: Bool = false
    var serverVersion: String?
    var connectionError: String?
    var sendError: String?

    // Session activity (rendered in transcript; session-scoped)
    var sessionActivities: [String: SessionActivity] = [:]

    // Track when a session status was last updated via SSE.
    var sessionStatusUpdatedAt: [String: Date] = [:]

    // Debounce session activity text changes (avoid rapid flipping).
    var activityTextLastChangeAt: [String: Date] = [:]
    var activityTextPendingTask: [String: Task<Void, Never>] = [:]

    var currentSessionActivity: SessionActivity? {
        guard let sid = currentSessionID else { return nil }
        return sessionActivities[sid]
    }

    func activityTextForSession(_ sessionID: String) -> String {
        ActivityTracker.bestSessionActivityText(
            sessionID: sessionID,
            currentSessionID: currentSessionID,
            sessionStatuses: sessionStatuses,
            messages: messages,
            streamingReasoningPart: streamingReasoningPart,
            streamingPartTexts: streamingPartTexts
        )
    }
    
    /// Unified error handling
    var lastAppError: AppError?
    
    func setError(_ error: Error, type: ErrorType = .connection) {
        let appError = AppError.from(error)
        lastAppError = appError
        
        switch type {
        case .connection:
            connectionError = appError.localizedDescription
        case .send:
            sendError = appError.localizedDescription
        }
    }
    
    func clearError() {
        lastAppError = nil
        connectionError = nil
        sendError = nil
    }
    
    enum ErrorType {
        case connection
        case send
    }

    let sessionStore = SessionStore()
    let messageStore = MessageStore()
    let fileStore = FileStore()
    let todoStore = TodoStore()

    var sessions: [Session] { get { sessionStore.sessions } set { sessionStore.sessions = newValue } }
    var sortedSessions: [Session] {
        sessions
            .filter { showArchivedSessions || !$0.isArchived }
            .sorted { $0.time.updated > $1.time.updated }
    }
    var sidebarSessions: [Session] {
        sessions
            .filter { showArchivedSessions || !$0.isArchived }
            .filter { $0.parentID == nil }
            .sorted { $0.time.updated > $1.time.updated }
    }
    var sessionTree: [SessionNode] {
        let filtered = sessions.filter { showArchivedSessions || !$0.isArchived }
        return Self.buildSessionTree(from: filtered)
    }
    var currentSessionID: String? { get { sessionStore.currentSessionID } set { sessionStore.currentSessionID = newValue } }
    var sessionStatuses: [String: SessionStatus] { get { sessionStore.sessionStatuses } set { sessionStore.sessionStatuses = newValue } }

    var messages: [MessageWithParts] { get { messageStore.messages } set { messageStore.messages = newValue } }
    var partsByMessage: [String: [Part]] { get { messageStore.partsByMessage } set { messageStore.partsByMessage = newValue } }
    var streamingPartTexts: [String: String] { get { messageStore.streamingPartTexts } set { messageStore.streamingPartTexts = newValue } }
    var streamingReasoningPart: Part? { get { messageStore.streamingReasoningPart } set { messageStore.streamingReasoningPart = newValue } }

    var modelPresets: [ModelPreset] = [
        ModelPreset(displayName: "GLM-5.1", providerID: "zai-coding-plan", modelID: "glm-5.1"),
        ModelPreset(displayName: "GPT-5.5", providerID: "openai", modelID: "gpt-5.5"),
        ModelPreset(displayName: "DeepSeek V4 Flash", providerID: "deepseek", modelID: "deepseek-v4-flash"),
        ModelPreset(displayName: "DeepSeek Local", providerID: "ds4", modelID: "deepseek-v4-flash"),
        ModelPreset(displayName: "DeepSeek V4 Pro", providerID: "deepseek", modelID: "deepseek-v4-pro"),
        ModelPreset(displayName: "Ollama DeepSeek V4 Pro", providerID: "ollama-cloud", modelID: "deepseek-v4-pro"),
        ModelPreset(displayName: "Ollama Kimi K2.7 Code", providerID: "ollama-cloud", modelID: "kimi-k2.7-code"),
    ]
    var selectedModelIndex: Int = 2
    
    var agents: [AgentInfo] = [
        AgentInfo(name: "OpenCode-Builder", description: "Build agent (OpenCode default)", mode: "all", hidden: false, native: false),
        AgentInfo(name: "Sisyphus (Ultraworker)", description: "Powerful AI orchestrator", mode: "primary", hidden: false, native: false),
        AgentInfo(name: "Hephaestus (Deep Agent)", description: "Autonomous Deep Worker", mode: "primary", hidden: false, native: false),
        AgentInfo(name: "Prometheus (Plan Builder)", description: "Plan agent", mode: "all", hidden: false, native: false),
        AgentInfo(name: "Atlas (Plan Executor)", description: "Plan Executor", mode: "primary", hidden: false, native: false),
    ]
    var selectedAgentIndex: Int = 0
    var isLoadingAgents: Bool = false

    var showArchivedSessions: Bool {
        get { _showArchivedSessions }
        set {
            _showArchivedSessions = newValue
            UserDefaults.standard.set(newValue, forKey: Self.showArchivedSessionsKey)
        }
    }
    var _showArchivedSessions: Bool = false
    var expandedSessionIDs: Set<String> = []

    func filteredSessions(archived: Bool) -> [Session] {
        return sessions
            .filter { $0.isArchived == archived }
            .sorted { $0.time.updated > $1.time.updated }
    }

    func sessionTree(archived: Bool) -> [SessionNode] {
        Self.buildSessionTree(from: filteredSessions(archived: archived))
    }

    var projects: [Project] = []
    var isLoadingProjects: Bool = false
    /// Server's current project worktree (from GET /project/current). Used to detect mismatch with user selection.
    var serverCurrentProjectWorktree: String? = nil

    /// When user selected a project but server's default differs: new sessions will be created in server's project.
    /// User should switch project in Web client first.
    var projectMismatchWarning: String? {
        guard let effective = effectiveProjectDirectory, !effective.isEmpty else { return nil }
        guard let server = serverCurrentProjectWorktree else { return nil }
        guard effective != server else { return nil }
        let effectiveName = (effective as NSString).lastPathComponent
        let serverName = (server as NSString).lastPathComponent
        return L10n.t(.settingsProjectMismatchWarning).replacingOccurrences(of: "{effective}", with: effectiveName).replacingOccurrences(of: "{server}", with: serverName)
    }

    /// Only allow creating sessions when using server default project. When a specific project is selected,
    /// new sessions would go to server default (API limitation), so we disable create and show hint.
    var canCreateSession: Bool {
        effectiveProjectDirectory == nil
    }

    /// Hint shown when create is disabled (user selected a project ≠ server default).
    var createSessionDisabledHint: String {
        L10n.t(.chatCreateDisabledHint)
    }

    var selectedProjectWorktree: String? {
        get { _selectedProjectWorktree }
        set {
            _selectedProjectWorktree = newValue
            UserDefaults.standard.set(newValue, forKey: Self.selectedProjectWorktreeKey)
        }
    }
    var _selectedProjectWorktree: String?

    var customProjectPath: String {
        get { _customProjectPath }
        set {
            _customProjectPath = newValue
            UserDefaults.standard.set(newValue, forKey: Self.customProjectPathKey)
        }
    }
    var _customProjectPath: String = ""

    /// Effective directory for session fetch: selected project or custom path, nil = server default
    var effectiveProjectDirectory: String? {
        guard let sel = selectedProjectWorktree, !sel.isEmpty else { return nil }
        if sel == Self.customProjectSentinel {
            let path = customProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
        return sel
    }
    /// Sentinel value when user selects "Custom path" option
    static let customProjectSentinel = "__custom__"

    var pendingPermissions: [PendingPermission] = []
    var pendingQuestions: [QuestionRequest] = []

    var themePreference: String = "auto"  // "auto" | "light" | "dark"

    var sessionDiffs: [FileDiff] { get { fileStore.sessionDiffs } set { fileStore.sessionDiffs = newValue } }
    var selectedDiffFile: String? { get { fileStore.selectedDiffFile } set { fileStore.selectedDiffFile = newValue } }
    var selectedTab: Int = 0  // 0=Chat, 1=Files, 2=Settings
    var fileToOpenInFilesTab: String?  // 从 Chat 中 tool 点击跳转时设置，Files tab 或 sheet 展示

    /// iPad 三栏布局：中间栏文件预览
    var previewFilePath: String?

    var sessionTodos: [String: [TodoItem]] { get { todoStore.sessionTodos } set { todoStore.sessionTodos = newValue } }

    var fileTreeRoot: [FileNode] { get { fileStore.fileTreeRoot } set { fileStore.fileTreeRoot = newValue } }
    var fileStatusMap: [String: String] { get { fileStore.fileStatusMap } set { fileStore.fileStatusMap = newValue } }
    var expandedPaths: Set<String> { get { fileStore.expandedPaths } set { fileStore.expandedPaths = newValue } }
    var fileChildrenCache: [String: [FileNode]] { get { fileStore.fileChildrenCache } set { fileStore.fileChildrenCache = newValue } }
    var fileSearchQuery: String { get { fileStore.fileSearchQuery } set { fileStore.fileSearchQuery = newValue } }
    var fileSearchResults: [String] { get { fileStore.fileSearchResults } set { fileStore.fileSearchResults = newValue } }

    // Provider config cache (for context usage ring)
    var providersResponse: ProvidersResponse? = nil
    var providerModelsIndex: [String: ProviderModel] = [:]
    var providerConfigError: String? = nil

    @ObservationIgnored var _cachedContextUsage: ContextUsageSnapshot?

    let apiClient: APIClientProtocol
    let sseClient: SSEClientProtocol
    let sshTunnelManager: SSHTunnelManager
    var sseTask: Task<Void, Never>?

    /// Guard against race conditions when rapidly switching sessions.
    /// Each selectSession call generates a new ID; async tasks check if they're still current.
    var sessionLoadingID = UUID()
    nonisolated private static let sessionPageSize = 100
    var loadedSessionLimit = sessionPageSize
    var hasMoreSessions = true
    var isLoadingMoreSessions = false

    var canLoadMoreSessions: Bool {
        hasMoreSessions && !isLoadingMoreSessions
    }

    // WAN optimization: page message history in fixed-size message batches.
    nonisolated private static let messagePageSize = 20
    var loadedMessageLimitBySessionID: [String: Int] = [:]
    var hasMoreHistoryBySessionID: [String: Bool] = [:]
    var loadingOlderMessagesSessionIDs: Set<String> = []

    var selectedModel: ModelPreset? {
        guard modelPresets.indices.contains(selectedModelIndex) else { return nil }
        return modelPresets[selectedModelIndex]
    }
    
    var selectedAgent: AgentInfo? {
        let visibleAgents = agents.filter { $0.isVisible }
        guard visibleAgents.indices.contains(selectedAgentIndex) else { return nil }
        return visibleAgents[selectedAgentIndex]
    }
    
    var visibleAgents: [AgentInfo] {
        agents.filter { $0.isVisible }
    }

    var isCurrentSessionHistoryTruncated: Bool {
        guard let sessionID = currentSessionID else { return false }
        return hasMoreHistoryBySessionID[sessionID] ?? false
    }

    var isLoadingOlderMessagesInCurrentSession: Bool {
        guard let sessionID = currentSessionID else { return false }
        return loadingOlderMessagesSessionIDs.contains(sessionID)
    }

    nonisolated static func normalizedMessageFetchLimit(
        current: Int?,
        pageSize: Int = 20
    ) -> Int {
        let fallback = max(pageSize, 1)
        guard let current else { return fallback }
        return max(current, fallback)
    }

    nonisolated static func nextMessageFetchLimit(
        current: Int?,
        pageSize: Int = 20
    ) -> Int {
        normalizedMessageFetchLimit(current: current, pageSize: pageSize) + max(pageSize, 1)
    }

    nonisolated static func nextSessionIDAfterDeleting(
        deletedSessionID: String,
        currentSessionID: String?,
        remainingSessions: [Session]
    ) -> String? {
        guard currentSessionID == deletedSessionID else { return currentSessionID }
        return remainingSessions
            .sorted { $0.time.updated > $1.time.updated }
            .first?
            .id
    }

    nonisolated static func nextSessionFetchLimit(
        current: Int,
        pageSize: Int = sessionPageSize
    ) -> Int {
        max(current, pageSize) + max(pageSize, 1)
    }

    nonisolated static func buildSessionTree(from sessions: [Session]) -> [SessionNode] {
        let sessionIDs = Set(sessions.map(\.id))
        let childrenMap = Dictionary(grouping: sessions, by: \.parentID)

        func buildNodes(parentID: String?) -> [SessionNode] {
            (childrenMap[parentID] ?? [])
                .sorted { $0.time.updated > $1.time.updated }
                .map { session in
                    SessionNode(session: session, children: buildNodes(parentID: session.id))
                }
        }

        var roots = buildNodes(parentID: nil)

        let orphans = sessions
            .filter { session in
                guard let pid = session.parentID else { return false }
                return !sessionIDs.contains(pid)
            }
            .sorted { $0.time.updated > $1.time.updated }
            .map { session in
                SessionNode(session: session, children: buildNodes(parentID: session.id))
            }

        roots.append(contentsOf: orphans)
        roots.sort { $0.session.time.updated > $1.session.time.updated }
        return roots
    }

    var currentSession: Session? {
        guard let id = currentSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    var currentSessionStatus: SessionStatus? {
        guard let id = currentSessionID else { return nil }
        return sessionStatuses[id]
    }

    var isBusy: Bool {
        isBusySession(currentSessionStatus)
    }

    var currentTodos: [TodoItem] {
        guard let id = currentSessionID else { return [] }
        return sessionTodos[id] ?? []
    }

    /// 是否应处理 message.updated：有 sessionID 时需匹配当前 session，否则保持原行为
    nonisolated static func shouldProcessMessageEvent(eventSessionID: String?, currentSessionID: String?) -> Bool {
        guard currentSessionID != nil else { return false }
        if let sid = eventSessionID { return sid == currentSessionID }
        return true  // 无 sessionID 时保持原行为（向后兼容）
    }

    /// Async request result should only apply when requested session is still current.
    nonisolated static func shouldApplySessionScopedResult(requestedSessionID: String, currentSessionID: String?) -> Bool {
        requestedSessionID == currentSessionID
    }

    func refresh() async {
        await testConnection()
        if isConnected {
            async let agentsResult: Void = loadAgents()
            async let providersResult: Void = loadProvidersConfig()
            async let projectsResult: Void = loadProjects()
            await loadSessions()
            _ = await agentsResult
            _ = await providersResult
            _ = await projectsResult
            await loadMessages()
            await refreshPendingPermissions()
            await loadSessionDiff()
            await loadSessionTodos()
            await loadFileTree()
            await loadFileStatus()
            await syncSessionStatusesFromPoll()
        }
    }

    func loadProvidersConfig() async {
        do {
            let resp = try await apiClient.providers()
            providersResponse = resp
            providerConfigError = nil
            var idx: [String: ProviderModel] = [:]
            for p in resp.providers {
                for (modelID, m) in p.models {
                    let key = "\(p.id)/\(modelID)"
                    idx[key] = m
                }
            }
            providerModelsIndex = idx
        } catch {
            providerConfigError = error.localizedDescription
        }
    }

}

struct PendingPermission: Identifiable {
    var id: String { "\(sessionID)/\(permissionID)" }
    let sessionID: String
    let permissionID: String
    let permission: String?
    let patterns: [String]
    let allowAlways: Bool
    let tool: String?
    let description: String
}

struct SessionActivity: Identifiable {
    enum State {
        case running
        case completed
    }

    var id: String { sessionID }
    let sessionID: String
    var state: State
    var text: String
    let startedAt: Date
    var endedAt: Date?
    var anchorMessageID: String?

    func elapsedSeconds(now: Date = Date()) -> Int {
        let end = endedAt ?? now
        return max(0, Int(end.timeIntervalSince(startedAt)))
    }

    func elapsedString(now: Date = Date()) -> String {
        let secs = elapsedSeconds(now: now)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
