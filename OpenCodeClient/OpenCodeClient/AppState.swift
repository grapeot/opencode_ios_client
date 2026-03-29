//
//  AppState.swift
//  OpenCodeClient
//

import Foundation
import CryptoKit
import Observation
import os

struct SessionNode: Identifiable {
    let session: Session
    let children: [SessionNode]
    var id: String { session.id }
}

@Observable
@MainActor
final class AppState {
    private static let logger = Logger(
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
    private var _serverURL: String = APIClient.defaultServer
    var serverURL: String {
        get { _serverURL }
        set {
            _serverURL = newValue
            UserDefaults.standard.set(newValue, forKey: Self.serverURLKey)
        }
    }

    private var _username: String = ""
    var username: String {
        get { _username }
        set {
            _username = newValue
            UserDefaults.standard.set(newValue, forKey: Self.usernameKey)
        }
    }

    private var _password: String = ""
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

    private static let serverURLKey = "serverURL"
    private static let usernameKey = "username"
    private static let passwordKeychainKey = "password"
    private static let aiBuilderBaseURLKey = "aiBuilderBaseURL"
    private static let aiBuilderTokenKeychainKey = "aiBuilderToken"
    private static let aiBuilderCustomPromptKey = "aiBuilderCustomPrompt"
    private static let aiBuilderTerminologyKey = "aiBuilderTerminology"
    private static let aiBuilderLastOKSignatureKey = "aiBuilderLastOKSignature"
    private static let aiBuilderLastOKTestedAtKey = "aiBuilderLastOKTestedAt"
    private static let draftInputsBySessionKey = "draftInputsBySession"
    private static let selectedModelBySessionKey = "selectedModelBySession"
    private static let selectedVariantBySessionKey = "selectedVariantBySession"
    private static let showArchivedSessionsKey = "showArchivedSessions"
    private static let selectedProjectWorktreeKey = "selectedProjectWorktree"
    private static let customProjectPathKey = "customProjectPath"

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

        if let data = UserDefaults.standard.data(forKey: Self.selectedVariantBySessionKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            selectedVariantBySessionID = decoded
        }
    }

    // Unsent composer drafts per session.
    private var draftInputsBySessionID: [String: String] = [:]

    // Selected model (providerID/modelID) per session.
    private var selectedModelIDBySessionID: [String: String] = [:]
    private var selectedVariantBySessionID: [String: String] = [:]

    private func persistSelectedModelMap() {
        if selectedModelIDBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.selectedModelBySessionKey)
            return
        }
        if let data = try? JSONEncoder().encode(selectedModelIDBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.selectedModelBySessionKey)
        }
    }

    private func persistSelectedVariantMap() {
        if selectedVariantBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.selectedVariantBySessionKey)
            return
        }
        if let data = try? JSONEncoder().encode(selectedVariantBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.selectedVariantBySessionKey)
        }
    }

    func draftText(for sessionID: String?) -> String {
        guard let sessionID else { return "" }
        return draftInputsBySessionID[sessionID] ?? ""
    }

    func setDraftText(_ text: String, for sessionID: String?) {
        guard let sessionID else { return }
        let cleaned = text
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftInputsBySessionID[sessionID] = nil
        } else {
            draftInputsBySessionID[sessionID] = cleaned
        }

        if draftInputsBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.draftInputsBySessionKey)
            return
        }
        if let data = try? JSONEncoder().encode(draftInputsBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.draftInputsBySessionKey)
        }
    }

    private static func aiBuilderSignature(baseURL: String, token: String) -> String {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !tok.isEmpty else { return "" }
        let input = "\(base)|\(tok)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var _aiBuilderBaseURL: String = "https://space.ai-builders.com/backend"
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

    private var _aiBuilderToken: String = ""
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
    private static let defaultAIBuilderCustomPrompt = "All file and directory names should use snake_case (lowercase with underscores)."

    /// Default terminology (comma-separated) from workspace routing.
    private static let defaultAIBuilderTerminology = "adhoc_jobs, life_consulting, survey_sessions, thought_review"

    private var _aiBuilderCustomPrompt: String = ""
    var aiBuilderCustomPrompt: String {
        get { _aiBuilderCustomPrompt }
        set {
            _aiBuilderCustomPrompt = newValue
            UserDefaults.standard.set(newValue, forKey: Self.aiBuilderCustomPromptKey)
        }
    }

    private var _aiBuilderTerminology: String = ""
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
    private var sessionStatusUpdatedAt: [String: Date] = [:]

    // Debounce session activity text changes (avoid rapid flipping).
    private var activityTextLastChangeAt: [String: Date] = [:]
    private var activityTextPendingTask: [String: Task<Void, Never>] = [:]

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

    private let sessionStore = SessionStore()
    private let messageStore = MessageStore()
    private let fileStore = FileStore()
    private let todoStore = TodoStore()

    var sessions: [Session] { get { sessionStore.sessions } set { sessionStore.sessions = newValue } }
    var sortedSessions: [Session] {
        sessions
            .filter { showArchivedSessions || $0.time.archived == nil }
            .sorted { $0.time.updated > $1.time.updated }
    }
    var sidebarSessions: [Session] {
        sessions
            .filter { showArchivedSessions || $0.time.archived == nil }
            .filter { $0.parentID == nil }
            .sorted { $0.time.updated > $1.time.updated }
    }
    var sessionTree: [SessionNode] {
        let filtered = sessions.filter { showArchivedSessions || $0.time.archived == nil }
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
        ModelPreset(displayName: "Opus 4.6", providerID: "anthropic", modelID: "claude-opus-4-6"),
        ModelPreset(displayName: "Sonnet 4.6", providerID: "anthropic", modelID: "claude-sonnet-4-6"),
        ModelPreset(displayName: "GPT-5.4", providerID: "openai", modelID: "gpt-5.4"),
        ModelPreset(displayName: "GPT-5.3 Codex", providerID: "openai", modelID: "gpt-5.3-codex"),
    ]
    var selectedModelIndex: Int = 3
    
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
    private var _showArchivedSessions: Bool = false
    var expandedSessionIDs: Set<String> = []

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
    private var _selectedProjectWorktree: String?

    var customProjectPath: String {
        get { _customProjectPath }
        set {
            _customProjectPath = newValue
            UserDefaults.standard.set(newValue, forKey: Self.customProjectPathKey)
        }
    }
    private var _customProjectPath: String = ""

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

    private let apiClient: APIClientProtocol
    private let sseClient: SSEClientProtocol
    let sshTunnelManager: SSHTunnelManager
    private var sseTask: Task<Void, Never>?

    /// Guard against race conditions when rapidly switching sessions.
    /// Each selectSession call generates a new ID; async tasks check if they're still current.
    private var sessionLoadingID = UUID()
    nonisolated private static let sessionPageSize = 100
    private var loadedSessionLimit = sessionPageSize
    private var hasMoreSessions = true
    var isLoadingMoreSessions = false

    var canLoadMoreSessions: Bool {
        hasMoreSessions && !isLoadingMoreSessions
    }

    // WAN optimization: page message history in fixed-size message batches.
    nonisolated private static let messagePageSize = 20
    private var loadedMessageLimitBySessionID: [String: Int] = [:]
    private var hasMoreHistoryBySessionID: [String: Bool] = [:]
    private var loadingOlderMessagesSessionIDs: Set<String> = []

    var selectedModel: ModelPreset? {
        guard modelPresets.indices.contains(selectedModelIndex) else { return nil }
        return modelPresets[selectedModelIndex]
    }

    var selectedModelVariants: [String] {
        guard let model = selectedModel else { return [] }
        let key = "\(model.providerID)/\(model.modelID)"
        return Self.sortedVariants(providerModelsIndex[key]?.variants ?? [])
    }

    var selectedVariant: String? {
        guard let sessionID = currentSessionID else { return nil }
        guard let saved = selectedVariantBySessionID[sessionID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !saved.isEmpty else { return nil }
        let available = selectedModelVariants
        if available.isEmpty { return saved }
        return available.contains(saved) ? saved : nil
    }

    var selectedVariantDisplayName: String {
        Self.displayName(forVariant: selectedVariant)
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

    private func fetchSessions(limit: Int) async throws -> [Session] {
        let directory = effectiveProjectDirectory
        let loaded = try await apiClient.sessions(directory: directory, limit: limit)
        let archivedCount = loaded.filter { $0.time.archived != nil }.count
        Self.logger.debug("loadSessions: directory=\(directory ?? "nil", privacy: .public) limit=\(limit, privacy: .public) count=\(loaded.count, privacy: .public) archived=\(archivedCount, privacy: .public) ids=\(loaded.prefix(5).map(\.id).joined(separator: ","), privacy: .public)")
        return loaded
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

    func toggleSessionExpanded(_ sessionID: String) {
        if expandedSessionIDs.contains(sessionID) {
            expandedSessionIDs.remove(sessionID)
        } else {
            expandedSessionIDs.insert(sessionID)
        }
    }

    private func upsertSession(_ session: Session) {
        let existingIndex = sessions.firstIndex(where: { $0.id == session.id })
        sessions.removeAll { $0.id == session.id }

        let targetIndex: Int
        if let existingIndex {
            targetIndex = min(existingIndex, sessions.count)
        } else {
            targetIndex = 0
        }

        sessions.insert(session, at: targetIndex)
    }

    func setSelectedModelIndex(_ index: Int) {
        guard modelPresets.indices.contains(index) else { return }
        selectedModelIndex = index
        normalizeSelectedVariantForCurrentSession()
        guard let sessionID = currentSessionID else { return }
        selectedModelIDBySessionID[sessionID] = modelPresets[index].id
        persistSelectedModelMap()
    }

    func setSelectedVariant(_ variant: String?) {
        guard let sessionID = currentSessionID else { return }
        let cleaned = variant?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned, !cleaned.isEmpty {
            let available = selectedModelVariants
            guard available.isEmpty || available.contains(cleaned) else { return }
            selectedVariantBySessionID[sessionID] = cleaned
        } else {
            selectedVariantBySessionID[sessionID] = nil
        }
        persistSelectedVariantMap()
    }
    
    func setSelectedAgentIndex(_ index: Int) {
        let visibleAgents = agents.filter { $0.isVisible }
        guard visibleAgents.indices.contains(index) else { return }
        selectedAgentIndex = index
    }

    private func applySavedModelForCurrentSession() {
        guard let sessionID = currentSessionID else { return }
        guard let saved = selectedModelIDBySessionID[sessionID] else { return }
        guard let idx = modelPresets.firstIndex(where: { $0.id == saved }) else { return }
        selectedModelIndex = idx
        normalizeSelectedVariantForCurrentSession()
    }

    private func syncModelFromMessageHistory() {
        guard let sessionID = currentSessionID else { return }
        if let info = messages.reversed().compactMap({ $0.info.resolvedModel }).first,
           let idx = modelPresets.firstIndex(where: { $0.providerID == info.providerID && $0.modelID == info.modelID }) {
            selectedModelIndex = idx
            selectedModelIDBySessionID[sessionID] = modelPresets[idx].id
            persistSelectedModelMap()
        } else if let info = messages.reversed().compactMap({ $0.info.resolvedModel }).first {
            Self.logger.warning("syncModelFromMessageHistory: model \(info.providerID, privacy: .public)/\(info.modelID, privacy: .public) not in presets, keeping current selection")
        }

        if selectedVariantBySessionID[sessionID] == nil,
           let variant = messages.reversed()
            .compactMap({ $0.info.variant?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            selectedVariantBySessionID[sessionID] = variant
            persistSelectedVariantMap()
        }

        normalizeSelectedVariantForCurrentSession()
    }

    private func normalizeSelectedVariantForCurrentSession() {
        guard let sessionID = currentSessionID,
              let saved = selectedVariantBySessionID[sessionID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !saved.isEmpty else { return }
        let available = selectedModelVariants
        if available.isEmpty {
            if selectedVariantBySessionID[sessionID] != saved {
                selectedVariantBySessionID[sessionID] = saved
                persistSelectedVariantMap()
            }
            return
        }
        guard available.contains(saved) else {
            selectedVariantBySessionID[sessionID] = nil
            persistSelectedVariantMap()
            return
        }
        if selectedVariantBySessionID[sessionID] != saved {
            selectedVariantBySessionID[sessionID] = saved
            persistSelectedVariantMap()
        }
    }

    nonisolated private static func sortedVariants(_ values: [String]) -> [String] {
        let order: [String: Int] = [
            "none": 0,
            "minimal": 1,
            "low": 2,
            "medium": 3,
            "high": 4,
            "xhigh": 5,
            "max": 6,
        ]
        return values.sorted {
            let lhs = order[$0.lowercased()] ?? Int.max
            let rhs = order[$1.lowercased()] ?? Int.max
            if lhs == rhs { return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return lhs < rhs
        }
    }

    nonisolated static func displayName(forVariant variant: String?) -> String {
        guard let variant else { return "Auto" }
        switch variant.lowercased() {
        case "none":
            return "None"
        case "minimal":
            return "Minimal"
        case "low":
            return "Low"
        case "medium":
            return "Medium"
        case "high":
            return "High"
        case "xhigh":
            return "Extra High"
        case "max":
            return "Max"
        default:
            return variant
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
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

    func configure(serverURL: String, username: String? = nil, password: String? = nil) {
        // Keep raw user input; security normalization happens at request time.
        self.serverURL = serverURL
        self.username = username ?? ""
        self.password = password ?? ""
    }

    func testConnection() async {
        connectionError = nil

        let info = Self.serverURLInfo(serverURL)
        guard info.isAllowed, let baseURL = info.normalized else {
            isConnected = false
            connectionError = info.warning ?? L10n.t(.errorInvalidBaseURL)
            return
        }

        await apiClient.configure(baseURL: baseURL, username: username.isEmpty ? nil : username, password: password.isEmpty ? nil : password)
        do {
            let health = try await apiClient.health()
            isConnected = health.healthy
            serverVersion = health.version
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
        }
    }

    func loadProjects() async {
        guard isConnected else { return }
        isLoadingProjects = true
        do {
            projects = try await apiClient.projects()
            serverCurrentProjectWorktree = (try? await apiClient.projectCurrent())?.worktree
        } catch {
            Self.logger.warning("loadProjects failed: \(error.localizedDescription)")
            projects = []
        }
        isLoadingProjects = false
    }

    func loadSessions() async {
        guard isConnected else { return }
        do {
            let loaded = try await fetchSessions(limit: loadedSessionLimit)
            sessions = loaded
            hasMoreSessions = loaded.count >= loadedSessionLimit

            // Only auto-select first session if there's no persisted selection at all
            // This handles the case of fresh install or after all sessions are deleted
            if currentSessionID == nil, let first = sessions.first {
                currentSessionID = first.id
                applySavedModelForCurrentSession()
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadMoreSessions() async {
        guard isConnected else { return }
        guard hasMoreSessions else { return }
        guard !isLoadingMoreSessions else { return }

        isLoadingMoreSessions = true
        let nextLimit = Self.nextSessionFetchLimit(current: loadedSessionLimit)
        defer { isLoadingMoreSessions = false }

        do {
            let loaded = try await fetchSessions(limit: nextLimit)
            loadedSessionLimit = nextLimit
            sessions = loaded
            hasMoreSessions = loaded.count >= loadedSessionLimit

            if currentSessionID == nil, let first = sessions.first {
                currentSessionID = first.id
                applySavedModelForCurrentSession()
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }
    
    func loadAgents() async {
        guard isConnected else { return }
        isLoadingAgents = true
        do {
            let loaded = try await apiClient.agents()
            agents = loaded
            if selectedAgentIndex >= visibleAgents.count && !visibleAgents.isEmpty {
                selectedAgentIndex = 0
            }
        } catch {
            Self.logger.warning("loadAgents failed: \(error.localizedDescription)")
        }
        isLoadingAgents = false
    }

    func refreshSessions() async {
        guard isConnected else { return }
        await loadSessions()
        await syncSessionStatusesFromPoll()
    }

    func selectSession(_ session: Session) {
        guard currentSessionID != session.id else { return }
        
        // Generate new loading ID to invalidate any in-flight tasks from previous session
        let loadingID = UUID()
        sessionLoadingID = loadingID
        
        messageStore.resetStreaming()
        messages = []
        partsByMessage = [:]
        currentSessionID = session.id
        applySavedModelForCurrentSession()
        
        Task { [weak self] in
            guard let self else { return }
            // Check if this task is still current before proceeding
            guard self.sessionLoadingID == loadingID else { return }
            
            await self.refreshSessions()
            guard self.sessionLoadingID == loadingID else { return }
            
            await self.loadMessages()
            guard self.sessionLoadingID == loadingID else { return }

            await self.refreshPendingPermissions()
            guard self.sessionLoadingID == loadingID else { return }

            await self.refreshPendingQuestions()
            guard self.sessionLoadingID == loadingID else { return }
            
            self.syncModelFromMessageHistory()
            await self.loadSessionDiff()
            guard self.sessionLoadingID == loadingID else { return }
            
            await self.loadSessionTodos()
            guard self.sessionLoadingID == loadingID else { return }

        }
    }

    private func isBusySession(_ status: SessionStatus?) -> Bool {
        guard let type = status?.type else { return false }
        return type == "busy" || type == "retry"
    }

    func loadSessionTodos() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let todos = try await apiClient.sessionTodos(sessionID: sessionID)
            sessionTodos[sessionID] = todos
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            // keep previous value if any
        }
    }

    func createSession() async {
        guard isConnected else { return }
        
        let loadingID = UUID()
        sessionLoadingID = loadingID
        
        do {
            let session = try await apiClient.createSession(title: nil)
            guard sessionLoadingID == loadingID else { return }
            let variant = selectedVariant
            
            Self.logger.debug("createSession: created id=\(session.id, privacy: .public) directory=\(session.directory, privacy: .public) effectiveProjectDir=\(self.effectiveProjectDirectory ?? "nil", privacy: .public)")
            
            upsertSession(session)
            currentSessionID = session.id
            if let m = selectedModel {
                selectedModelIDBySessionID[session.id] = m.id
                persistSelectedModelMap()
            }
            if let variant {
                selectedVariantBySessionID[session.id] = variant
                persistSelectedVariantMap()
            }
            messageStore.resetStreaming()
            messages = []
            partsByMessage = [:]
        } catch {
            guard sessionLoadingID == loadingID else { return }
            connectionError = error.localizedDescription
        }
    }

    func forkSession(messageID: String?) async {
        guard isConnected else { return }
        guard let sessionID = currentSessionID else { return }

        let loadingID = UUID()
        sessionLoadingID = loadingID

        do {
            let forked = try await apiClient.forkSession(sessionID: sessionID, messageID: messageID)
            guard sessionLoadingID == loadingID else { return }

            Self.logger.debug("forkSession: created id=\(forked.id, privacy: .public) from=\(sessionID, privacy: .public) messageID=\(messageID ?? "nil", privacy: .public)")

            upsertSession(forked)
            currentSessionID = forked.id
            messageStore.resetStreaming()
            messages = []
            partsByMessage = [:]
            await loadMessages()
            guard sessionLoadingID == loadingID else { return }
            syncModelFromMessageHistory()
        } catch {
            guard sessionLoadingID == loadingID else { return }
            connectionError = error.localizedDescription
        }
    }

    func deleteSession(sessionID: String) async throws {
        let previousCurrentSessionID = currentSessionID
        try await apiClient.deleteSession(sessionID: sessionID)

        sessions.removeAll { $0.id == sessionID }
        clearSessionScopedCaches(sessionID: sessionID)

        let nextSessionID = Self.nextSessionIDAfterDeleting(
            deletedSessionID: sessionID,
            currentSessionID: previousCurrentSessionID,
            remainingSessions: sessions
        )

        guard previousCurrentSessionID == sessionID else {
            currentSessionID = nextSessionID
            return
        }

        clearCurrentSessionViewState()
        if let nextSessionID {
            currentSessionID = nextSessionID
            applySavedModelForCurrentSession()
            await loadMessages()
            await refreshPendingPermissions()
            await loadSessionDiff()
            await loadSessionTodos()
            syncModelFromMessageHistory()
        } else {
            currentSessionID = nil
            pendingPermissions = []
        }
    }

    func loadMessages() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let fetchLimit = Self.normalizedMessageFetchLimit(current: loadedMessageLimitBySessionID[sessionID])
            loadedMessageLimitBySessionID[sessionID] = fetchLimit
            let loaded = try await apiClient.messages(sessionID: sessionID, limit: fetchLimit)
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("drop stale loadMessages result requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }

            hasMoreHistoryBySessionID[sessionID] = loaded.count >= fetchLimit

            let loadedMessageIDs = Set(loaded.map { $0.info.id })
            let keepPending = isBusySession(currentSessionStatus)
            let pendingMessages: [MessageWithParts] = {
                guard keepPending else { return [] }
                let pending = messages.filter({ $0.info.id.hasPrefix("temp-user-") })
                guard let lastLoadedUser = loaded.last(where: { $0.info.isUser }) else { return pending }

                func normalizeEpochMs(_ raw: Int) -> Int {
                    // Server timestamps may be seconds or milliseconds.
                    if raw > 0 && raw < 10_000_000_000 { return raw * 1000 }
                    return raw
                }

                func normalizeComparableText(_ raw: String) -> String {
                    raw
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }

                let lastLoadedText = normalizeComparableText(
                    lastLoadedUser.parts.first(where: { $0.isText })?.text ?? ""
                )
                let lastLoadedCreated = normalizeEpochMs(lastLoadedUser.info.time.created)

                return pending.filter { m in
                    guard m.info.isUser else { return true }
                    let text = normalizeComparableText(
                        m.parts.first(where: { $0.isText })?.text ?? ""
                    )
                    guard !text.isEmpty, text == lastLoadedText else { return true }

                    let created = normalizeEpochMs(m.info.time.created)
                    if created == 0 || lastLoadedCreated == 0 { return false }
                    return abs(lastLoadedCreated - created) > 10 * 60 * 1000
                }
            }()

            let draftMessages = messages.filter {
                messageStore.isStreamingDraftMessage($0.info.id) && !loadedMessageIDs.contains($0.info.id)
            }

            var merged: [MessageWithParts] = loaded
            for message in pendingMessages where !loadedMessageIDs.contains(message.info.id) {
                merged.append(message)
            }
            for message in draftMessages where !merged.contains(where: { $0.info.id == message.info.id }) {
                merged.append(message)
            }

            // Defensively dedupe by message id. Keep the latest occurrence.
            var dedupedMessages: [MessageWithParts] = []
            var dedupedIndexByMessageID: [String: Int] = [:]
            for message in merged {
                if let existingIndex = dedupedIndexByMessageID[message.info.id] {
                    dedupedMessages[existingIndex] = message
                } else {
                    dedupedIndexByMessageID[message.info.id] = dedupedMessages.count
                    dedupedMessages.append(message)
                }
            }

            messages = dedupedMessages

            var partsByMessageID: [String: [Part]] = [:]
            for message in messages {
                partsByMessageID[message.info.id] = message.parts
            }
            partsByMessage = partsByMessageID
            messageStore.removeStreamingDraftMessages(loadedMessageIDs)

            if isBusySession(currentSessionStatus) {
                refreshSessionActivityText(sessionID: sessionID)
            }
        } catch let error as DecodingError {
            Self.logger.error("loadMessages decode failed: session=\(sessionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("ignore stale loadMessages error requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }
            connectionError = error.localizedDescription
            Self.logger.error("loadMessages failed: session=\(sessionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func loadOlderMessagesForCurrentSession() async {
        guard let sessionID = currentSessionID else { return }
        guard hasMoreHistoryBySessionID[sessionID] ?? true else { return }
        guard !loadingOlderMessagesSessionIDs.contains(sessionID) else { return }

        loadingOlderMessagesSessionIDs.insert(sessionID)
        loadedMessageLimitBySessionID[sessionID] = Self.nextMessageFetchLimit(current: loadedMessageLimitBySessionID[sessionID])
        await loadMessages()
        loadingOlderMessagesSessionIDs.remove(sessionID)
    }

    func loadSessionDiff() async {
        guard let sessionID = currentSessionID else { sessionDiffs = []; return }
        do {
            let loaded = try await apiClient.sessionDiff(sessionID: sessionID)
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("drop stale loadSessionDiff result requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }
            sessionDiffs = loaded
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else { return }
            sessionDiffs = []
        }
    }

    func loadFileTree() async {
        do {
            fileTreeRoot = try await apiClient.fileList(path: "")
            fileChildrenCache = [:]
        } catch {
            fileTreeRoot = []
        }
    }

    func loadFileStatus() async {
        do {
            let entries = try await apiClient.fileStatus()
            var nextStatusMap: [String: String] = [:]
            for entry in entries {
                guard let path = entry.path else { continue }
                nextStatusMap[path] = entry.status ?? ""
            }
            fileStatusMap = nextStatusMap
        } catch {
            fileStatusMap = [:]
        }
    }

    func loadFileChildren(path: String) async -> [FileNode] {
        do {
            let children = try await apiClient.fileList(path: path)
            fileChildrenCache[path] = children
            return children
        } catch {
            fileChildrenCache[path] = []
            return []
        }
    }

    func cachedChildren(for path: String) -> [FileNode]? {
        fileChildrenCache[path]
    }

    func searchFiles(query: String) async {
        guard !query.isEmpty else { fileSearchResults = []; return }
        do {
            fileSearchResults = try await apiClient.findFile(query: query, limit: 50)
        } catch {
            fileSearchResults = []
        }
    }

    func loadFileContent(path: String) async throws -> FileContent {
        let resolved = PathNormalizer.resolveWorkspaceRelativePath(path, workspaceDirectory: currentSession?.directory)
        let fc = try await apiClient.fileContent(path: resolved)
        if fc.type == "text" {
            let text = fc.content ?? ""
            if text.isEmpty {
                let base = Self.serverURLInfo(serverURL).normalized ?? "nil"
                Self.logger.warning(
                    "Empty file content. base=\(base, privacy: .public) raw=\(path, privacy: .public) resolved=\(resolved, privacy: .public) session=\(self.currentSessionID ?? "nil", privacy: .public)"
                )
            }
        }
        return fc
    }

    func transcribeAudio(audioFileURL: URL, language: String? = nil, onPartialTranscript: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AIBuildersAudioError.missingToken }

        let base = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = aiBuilderCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = aiBuilderTerminology.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = ProcessInfo.processInfo.systemUptime
        let fileName = audioFileURL.lastPathComponent.isEmpty ? "audio.m4a" : audioFileURL.lastPathComponent
        Self.logger.notice("[SpeechProfile] appState.transcribe begin file=\(fileName, privacy: .public)")
        do {
            let resp = try await AIBuildersAudioClient.transcribe(
                baseURL: base,
                token: token,
                audioFileURL: audioFileURL,
                language: language,
                prompt: prompt.isEmpty ? nil : prompt,
                terms: terms.isEmpty ? nil : terms,
                onPartialTranscript: onPartialTranscript
            )
            let elapsedMs = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.notice("[SpeechProfile] appState.transcribe done ms=\(elapsedMs, privacy: .public) textChars=\(resp.text.count, privacy: .public) requestID=\(resp.requestID, privacy: .public)")
            return resp.text
        } catch {
            let elapsedMs = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.error("[SpeechProfile] appState.transcribe failed ms=\(elapsedMs, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func testAIBuilderConnection() async {
        guard !isTestingAIBuilderConnection else { return }
        isTestingAIBuilderConnection = true
        defer { isTestingAIBuilderConnection = false }

        aiBuilderConnectionError = nil
        aiBuilderConnectionOK = false
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            aiBuilderConnectionError = L10n.t(.errorAiBuilderTokenEmpty)
            aiBuilderLastTestedAt = Date()
            return
        }
        let base = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await AIBuildersAudioClient.testConnection(baseURL: base, token: token)
            aiBuilderConnectionOK = true
            aiBuilderLastTestedAt = Date()

            let sig = Self.aiBuilderSignature(baseURL: base, token: token)
            UserDefaults.standard.set(sig, forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.set(aiBuilderLastTestedAt?.timeIntervalSince1970, forKey: Self.aiBuilderLastOKTestedAtKey)
        } catch {
            aiBuilderLastTestedAt = Date()
            aiBuilderConnectionOK = false
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
            switch error {
            case AIBuildersAudioError.missingToken:
                aiBuilderConnectionError = L10n.t(.errorAiBuilderTokenEmpty)
            case AIBuildersAudioError.invalidBaseURL:
                aiBuilderConnectionError = L10n.t(.errorInvalidBaseURL)
            case AIBuildersAudioError.httpError(let statusCode, _):
                aiBuilderConnectionError = L10n.errorMessage(.errorServerError, String(statusCode))
            default:
                aiBuilderConnectionError = error.localizedDescription
            }
        }
    }

    func toggleFileExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func isFileExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }

    func sendMessage(_ text: String) async -> Bool {
        sendError = nil
        guard let sessionID = currentSessionID else {
            sendError = L10n.t(.chatSelectSessionFirst)
            return false
        }
        let tempMessageID = appendOptimisticUserMessage(text)
        let model = selectedModel.map { Message.ModelInfo(providerID: $0.providerID, modelID: $0.modelID) }
        let variant = selectedVariant
        let agentName = selectedAgent?.name ?? "build"
        do {
            try await apiClient.promptAsync(sessionID: sessionID, text: text, agent: agentName, model: model, variant: variant)
            return true
        } catch {
            let recovered = await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID)
            sendError = recovered ? L10n.t(.errorSessionNotFound) : error.localizedDescription
            removeMessage(id: tempMessageID)
            return false
        }
    }

    @discardableResult
    func appendOptimisticUserMessage(_ text: String) -> String {
        guard let sessionID = currentSessionID else { return "" }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let messageID = "temp-user-\(UUID().uuidString)"
        let partID = "temp-part-\(messageID)"
        let message = Message(
            id: messageID,
            sessionID: sessionID,
            role: "user",
            parentID: messages.last?.info.id,
            providerID: nil,
            modelID: nil,
            model: nil,
            variant: nil,
            error: nil,
            time: Message.TimeInfo(created: now, completed: now),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        let part = Part(
            id: partID,
            messageID: messageID,
            sessionID: sessionID,
            type: "text",
            text: text,
            tool: nil,
            callID: nil,
            state: nil,
            metadata: nil,
            files: nil
        )
        let row = MessageWithParts(info: message, parts: [part])
        messages.append(row)
        partsByMessage[messageID] = [part]
        return messageID
    }

    func removeMessage(id: String) {
        messages.removeAll { $0.info.id == id }
        partsByMessage[id] = nil
    }

    private func bootstrapSyncCurrentSession(reason: String) async {
        guard currentSessionID != nil else { return }
        let start = Date()
        await loadMessages()
        await refreshPendingPermissions()
        await refreshPendingQuestions()
        await syncSessionStatusesFromPoll()
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        Self.logger.debug("bootstrapSync reason=\(reason, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) messages=\(self.messages.count, privacy: .public) permissions=\(self.pendingPermissions.count, privacy: .public)")
    }

    private func syncSessionStatusesFromPoll(markMissingBusyAsIdle: Bool = true) async {
        guard isConnected else { return }
        guard let statuses = try? await apiClient.sessionStatus() else { return }
        mergePolledSessionStatuses(statuses, markMissingBusyAsIdle: markMissingBusyAsIdle)
    }

    func abortSession() async {
        guard let sessionID = currentSessionID else { return }
        do {
            try await apiClient.abort(sessionID: sessionID)
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            connectionError = error.localizedDescription
        }

        await syncSessionStatusesFromPoll(markMissingBusyAsIdle: true)
        await loadMessages()
        await loadSessionDiff()
    }

    func updateSessionTitle(sessionID: String, title: String) async {
        do {
            _ = try await apiClient.updateSession(sessionID: sessionID, title: title)
            await refreshSessions()
        } catch {
            if await recoverFromMissingCurrentSessionIfNeeded(error: error, requestedSessionID: sessionID) {
                return
            }
            connectionError = error.localizedDescription
        }
    }

    func respondPermission(_ perm: PendingPermission, response: APIClient.PermissionResponse) async {
        do {
            try await apiClient.respondPermission(sessionID: perm.sessionID, permissionID: perm.permissionID, response: response)
            pendingPermissions.removeAll { $0.id == perm.id }
            await refreshPendingPermissions()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    /// SSE permission events are not replayed; poll pending permissions so users can enter
    /// an in-progress session and still see the warning.
    func refreshPendingPermissions() async {
        guard isConnected else { return }
        do {
            let requests = try await apiClient.pendingPermissions()
            pendingPermissions = PermissionController.fromPendingRequests(requests)
        } catch {
            // Keep the current list on errors.
        }
    }

    func respondQuestion(_ request: QuestionRequest, answers: [[String]]) async {
        do {
            try await apiClient.replyQuestion(requestID: request.id, answers: answers)
            pendingQuestions.removeAll { $0.id == request.id }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func rejectQuestion(_ request: QuestionRequest) async {
        do {
            try await apiClient.rejectQuestion(requestID: request.id)
            pendingQuestions.removeAll { $0.id == request.id }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func refreshPendingQuestions() async {
        guard isConnected else { return }
        do {
            pendingQuestions = try await apiClient.pendingQuestions()
        } catch {}
    }

    func connectSSE() {
        sseTask?.cancel()
        sseTask = Task {
            var attempt = 0
            while !Task.isCancelled {
                let info = Self.serverURLInfo(serverURL)
                guard info.isAllowed, let baseURL = info.normalized else {
                    return
                }

                let stream = await sseClient.connect(
                    baseURL: baseURL,
                    username: username.isEmpty ? nil : username,
                    password: password.isEmpty ? nil : password
                )

                do {
                    await bootstrapSyncCurrentSession(reason: "sse.reconnect")
                    for try await event in stream {
                        attempt = 0
                        await handleSSEEvent(event)
                    }
                } catch {
                    // Reconnect with exponential backoff
                    attempt += 1
                    let base = min(30.0, pow(2.0, Double(attempt)))
                    try? await Task.sleep(for: .seconds(base))
                }
            }
        }
    }

    func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }
    
    // Note: AppState is typically held for the app's lifetime (as @State in root view),
    // so deinit-based cleanup is not critical. The disconnectSSE() method above
    // should be called explicitly when needed (e.g., on background/terminate).

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

    private func handleSSEEvent(_ event: SSEEvent) async {
        let type = event.payload.type
        let props = event.payload.properties ?? [:]

        switch type {
        case "server.connected":
            await syncSessionStatusesFromPoll(markMissingBusyAsIdle: true)
        case "session.status":
            if let sessionID = props["sessionID"]?.value as? String,
                let statusObj = props["status"]?.value as? [String: Any] {
                if let status = try? JSONSerialization.data(withJSONObject: statusObj),
                    let decoded = try? JSONDecoder().decode(SessionStatus.self, from: status) {
                    let prev = sessionStatuses[sessionID]

                    sessionStatuses[sessionID] = decoded
                    sessionStatusUpdatedAt[sessionID] = Date()

                    if prev?.type != decoded.type || prev?.message != decoded.message {
                        Self.logger.debug(
                            "session.status(sse) session=\(sessionID, privacy: .public) prev=\(prev?.type ?? "nil", privacy: .public) next=\(decoded.type, privacy: .public)"
                        )
                    }

                    updateSessionActivity(sessionID: sessionID, previous: prev, current: decoded)

                    if sessionID == currentSessionID, !isBusySession(decoded) {
                        messageStore.resetStreaming()
                    }
                }
            }
        case "session.updated":
            let infoVal = props["info"]?.value ?? props["session"]?.value
            if let infoObj = infoVal,
               JSONSerialization.isValidJSONObject(infoObj),
               let data = try? JSONSerialization.data(withJSONObject: infoObj),
               let session = try? JSONDecoder().decode(Session.self, from: data) {
                let dir = effectiveProjectDirectory
                let isCurrent = (session.id == currentSessionID)
                let matchesProject = dir == nil || session.directory == dir
                let shouldApply = matchesProject || isCurrent
                if shouldApply {
                    let wasUpdate = sessions.contains(where: { $0.id == session.id })
                    Self.logger.debug("session.updated id=\(session.id, privacy: .public) archived=\(session.time.archived.map { String($0) } ?? "nil", privacy: .public) dir=\(session.directory, privacy: .public) op=\(wasUpdate ? "replace" : "insert", privacy: .public)")
                    upsertSession(session)
                } else {
                    Self.logger.debug("session.updated skip id=\(session.id, privacy: .public) dir=\(session.directory, privacy: .public) effectiveDir=\(dir ?? "nil", privacy: .public)")
                }
            }
        case "session.deleted":
            if let sessionID = (props["sessionID"]?.value as? String) ?? (props["id"]?.value as? String) {
                Self.logger.debug("session.deleted id=\(sessionID, privacy: .public)")
                await handleRemoteSessionDeleted(sessionID: sessionID)
            } else {
                await loadSessions()
            }
        case "message.updated":
            let eventSessionID = props["sessionID"]?.value as? String
            if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
                messageStore.resetStreaming()
                await loadMessages()
                await loadSessionDiff()
            }
        case "message.part.updated":
            switch messageStore.applyMessagePartUpdate(properties: props, currentSessionID: currentSessionID) {
            case .ignored:
                break
            case .appended(let sessionID):
                refreshSessionActivityText(sessionID: sessionID)
            case .finalized:
                await loadMessages()
                await loadSessionDiff()
            }
        case "permission.asked":
            if let perm = PermissionController.parseAskedEvent(properties: props),
               !pendingPermissions.contains(where: { $0.id == perm.id }) {
                pendingPermissions.append(perm)
            }
        case "permission.replied":
            PermissionController.applyRepliedEvent(properties: props, to: &pendingPermissions)
        case "question.asked":
            if let question = QuestionController.parseAskedEvent(properties: props),
               !pendingQuestions.contains(where: { $0.id == question.id }) {
                pendingQuestions.append(question)
            }
        case "question.replied", "question.rejected":
            QuestionController.applyResolvedEvent(properties: props, to: &pendingQuestions)
        case "todo.updated":
            if let sessionID = props["sessionID"]?.value as? String,
               let todosObj = props["todos"]?.value,
               JSONSerialization.isValidJSONObject(todosObj),
               let todosData = try? JSONSerialization.data(withJSONObject: todosObj),
               let decoded = try? JSONDecoder().decode([TodoItem].self, from: todosData) {
                sessionTodos[sessionID] = decoded
            }
        default:
            break
        }
    }

    private func updateSessionActivity(sessionID: String, previous: SessionStatus?, current: SessionStatus) {
        sessionActivities[sessionID] = ActivityTracker.updateSessionActivity(
            sessionID: sessionID,
            previous: previous,
            current: current,
            existing: sessionActivities[sessionID],
            messages: messages,
            currentSessionID: currentSessionID,
            hasActiveStreaming: streamingReasoningPart?.sessionID == sessionID || messageStore.hasActiveStreaming
        )
    }

    private func mergePolledSessionStatuses(_ statuses: [String: SessionStatus]) {
        mergePolledSessionStatuses(statuses, markMissingBusyAsIdle: true)
    }

    private func mergePolledSessionStatuses(
        _ statuses: [String: SessionStatus],
        markMissingBusyAsIdle: Bool
    ) {
        let now = Date()
        for (sid, st) in statuses {
            if let updatedAt = sessionStatusUpdatedAt[sid], now.timeIntervalSince(updatedAt) < 5 {
                continue
            }
            let prev = sessionStatuses[sid]
            sessionStatuses[sid] = st
            updateSessionActivity(sessionID: sid, previous: prev, current: st)
            if sid == currentSessionID, !isBusySession(st) {
                messageStore.resetStreaming()
            }
            if prev?.type != st.type {
                Self.logger.debug(
                    "session.status(poll) session=\(sid, privacy: .public) prev=\(prev?.type ?? "nil", privacy: .public) next=\(st.type, privacy: .public)"
                )
            }
        }

        guard markMissingBusyAsIdle else { return }

        let existingSnapshot = sessionStatuses
        for (sid, prev) in existingSnapshot {
            guard statuses[sid] == nil else { continue }
            guard prev.type == "busy" || prev.type == "retry" else { continue }
            if let updatedAt = sessionStatusUpdatedAt[sid], now.timeIntervalSince(updatedAt) < 5 {
                continue
            }

            let idle = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)
            sessionStatuses[sid] = idle
            updateSessionActivity(sessionID: sid, previous: prev, current: idle)
            if sid == currentSessionID {
                messageStore.resetStreaming()
            }

            Self.logger.debug(
                "session.status(poll) session=\(sid, privacy: .public) prev=\(prev.type, privacy: .public) next=idle (missing from poll)"
            )
        }
    }

    private func refreshSessionActivityText(sessionID: String) {
        guard isBusySession(sessionStatuses[sessionID]) else { return }
        guard sessionActivities[sessionID]?.state == .running else { return }
        let next = ActivityTracker.bestSessionActivityText(
            sessionID: sessionID,
            currentSessionID: currentSessionID,
            sessionStatuses: sessionStatuses,
            messages: messages,
            streamingReasoningPart: streamingReasoningPart,
            streamingPartTexts: streamingPartTexts
        )
        setSessionActivityText(sessionID: sessionID, next)
    }

    private func setSessionActivityText(sessionID: String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var a = sessionActivities[sessionID], a.state == .running else { return }
        if a.text == trimmed { return }

        let now = Date()
        let delay = ActivityTracker.debounceDelay(lastChangeAt: activityTextLastChangeAt[sessionID], now: now)
        if delay == 0 {
            a.text = trimmed
            sessionActivities[sessionID] = a
            activityTextLastChangeAt[sessionID] = now
            activityTextPendingTask[sessionID]?.cancel()
            activityTextPendingTask[sessionID] = nil
            return
        }

        activityTextPendingTask[sessionID]?.cancel()
        activityTextPendingTask[sessionID] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard self.isBusySession(self.sessionStatuses[sessionID]) else { return }
            let best = ActivityTracker.bestSessionActivityText(
                sessionID: sessionID,
                currentSessionID: self.currentSessionID,
                sessionStatuses: self.sessionStatuses,
                messages: self.messages,
                streamingReasoningPart: self.streamingReasoningPart,
                streamingPartTexts: self.streamingPartTexts
            )
            self.setSessionActivityText(sessionID: sessionID, best)
        }
    }

    private func clearCurrentSessionViewState() {
        sessionLoadingID = UUID()
        messageStore.resetStreaming()
        messages = []
        partsByMessage = [:]
        sessionDiffs = []
    }

    private func clearSessionScopedCaches(sessionID: String) {
        sessionStatuses[sessionID] = nil
        sessionTodos[sessionID] = nil
        sessionActivities[sessionID] = nil
        sessionStatusUpdatedAt[sessionID] = nil
        activityTextLastChangeAt[sessionID] = nil
        activityTextPendingTask[sessionID]?.cancel()
        activityTextPendingTask[sessionID] = nil
        loadedMessageLimitBySessionID[sessionID] = nil
        hasMoreHistoryBySessionID[sessionID] = nil
        loadingOlderMessagesSessionIDs.remove(sessionID)
        pendingPermissions.removeAll { $0.sessionID == sessionID }

        if streamingReasoningPart?.sessionID == sessionID {
            messageStore.streamingReasoningPart = nil
        }

        draftInputsBySessionID[sessionID] = nil
        if draftInputsBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.draftInputsBySessionKey)
        } else if let data = try? JSONEncoder().encode(draftInputsBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.draftInputsBySessionKey)
        }

        selectedModelIDBySessionID[sessionID] = nil
        persistSelectedModelMap()

        selectedVariantBySessionID[sessionID] = nil
        persistSelectedVariantMap()
    }

    private func isSessionNotFoundError(_ error: Error) -> Bool {
        guard case APIError.httpError(let statusCode, _) = error else { return false }
        return statusCode == 404
    }

    private func recoverFromMissingCurrentSessionIfNeeded(
        error: Error,
        requestedSessionID: String
    ) async -> Bool {
        guard requestedSessionID == currentSessionID else { return false }
        guard isSessionNotFoundError(error) else { return false }

        await loadSessions()

        guard currentSessionID != nil else {
            pendingPermissions = []
            return true
        }

        await loadMessages()
        await refreshPendingPermissions()
        await loadSessionDiff()
        await loadSessionTodos()
        syncModelFromMessageHistory()
        return true
    }

    private func handleRemoteSessionDeleted(sessionID: String) async {
        let deletedCurrentSession = (sessionID == currentSessionID)

        sessions.removeAll { $0.id == sessionID }
        clearSessionScopedCaches(sessionID: sessionID)

        if deletedCurrentSession {
            clearCurrentSessionViewState()
        }

        await loadSessions()

        if deletedCurrentSession, currentSessionID != nil {
            await loadMessages()
            await refreshPendingPermissions()
            await loadSessionDiff()
            await loadSessionTodos()
            syncModelFromMessageHistory()
        } else if currentSessionID == nil {
            pendingPermissions = []
        } else {
            let validSessionIDs = Set(sessions.map(\.id))
            pendingPermissions.removeAll { !validSessionIDs.contains($0.sessionID) }
        }
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
            normalizeSelectedVariantForCurrentSession()
        } catch {
            providerConfigError = error.localizedDescription
        }
    }

    func applySSEEventForTesting(_ event: SSEEvent) async {
        await handleSSEEvent(event)
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
