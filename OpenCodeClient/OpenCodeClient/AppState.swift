//
//  AppState.swift
//  OpenCodeClient
//

import Foundation
import CryptoKit
import Observation
import os

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
        let isAllowed: Bool
        let warning: String?
    }

    /// LAN allows HTTP; WAN requires HTTPS.
    nonisolated static func serverURLInfo(_ raw: String) -> ServerURLInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .init(raw: raw, normalized: nil, scheme: nil, host: nil, isLocal: true, isAllowed: false, warning: L10n.t(.errorServerAddressEmpty))
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

        if scheme == "http", !isLocal {
            return .init(
                raw: raw,
                normalized: hasScheme ? trimmed : nil,
                scheme: "http",
                host: host,
                isLocal: false,
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
            isAllowed: parsed != nil,
            warning: parsed == nil ? L10n.t(.errorInvalidBaseURL) : (scheme == "http" ? L10n.t(.errorUsingLanHttp) : nil)
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

    init() {
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
    private var draftInputsBySessionID: [String: String] = [:]

    // Selected model (providerID/modelID) per session.
    private var selectedModelIDBySessionID: [String: String] = [:]

    private func persistSelectedModelMap() {
        if selectedModelIDBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.selectedModelBySessionKey)
            return
        }
        if let data = try? JSONEncoder().encode(selectedModelIDBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.selectedModelBySessionKey)
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
    var sortedSessions: [Session] { sessions.sorted { $0.time.updated > $1.time.updated } }
    var currentSessionID: String? { get { sessionStore.currentSessionID } set { sessionStore.currentSessionID = newValue } }
    var sessionStatuses: [String: SessionStatus] { get { sessionStore.sessionStatuses } set { sessionStore.sessionStatuses = newValue } }

    var messages: [MessageWithParts] { get { messageStore.messages } set { messageStore.messages = newValue } }
    var partsByMessage: [String: [Part]] { get { messageStore.partsByMessage } set { messageStore.partsByMessage = newValue } }
    var streamingPartTexts: [String: String] { get { messageStore.streamingPartTexts } set { messageStore.streamingPartTexts = newValue } }

    /// 固定四个模型，不再从 server 导入
    var modelPresets: [ModelPreset] = [
        ModelPreset(displayName: "GPT-5.3 Codex", providerID: "openai", modelID: "gpt-5.3-codex"),
        ModelPreset(displayName: "GPT-5.3 Codex Spark", providerID: "openai", modelID: "gpt-5.3-codex-spark"),
        ModelPreset(displayName: "Opus 4.6", providerID: "poe", modelID: "anthropic/claude-opus-4-6"),
        ModelPreset(displayName: "GLM5", providerID: "zai-coding-plan", modelID: "glm-5"),
    ]
    var selectedModelIndex: Int = 0

    var pendingPermissions: [PendingPermission] = []

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

    private let apiClient = APIClient()
    private let sseClient = SSEClient()
    let sshTunnelManager = SSHTunnelManager()
    private var sseTask: Task<Void, Never>?

    /// Guard against race conditions when rapidly switching sessions.
    /// Each selectSession call generates a new ID; async tasks check if they're still current.
    private var sessionLoadingID = UUID()

    /// Latest streaming reasoning part (for typewriter thinking display)
    var streamingReasoningPart: Part? = nil
    private var streamingDraftMessageIDs: Set<String> = []

    var selectedModel: ModelPreset? {
        guard modelPresets.indices.contains(selectedModelIndex) else { return nil }
        return modelPresets[selectedModelIndex]
    }

    func setSelectedModelIndex(_ index: Int) {
        guard modelPresets.indices.contains(index) else { return }
        selectedModelIndex = index
        guard let sessionID = currentSessionID else { return }
        selectedModelIDBySessionID[sessionID] = modelPresets[index].id
        persistSelectedModelMap()
    }

    private func applySavedModelForCurrentSession() {
        guard let sessionID = currentSessionID else { return }
        guard let saved = selectedModelIDBySessionID[sessionID] else { return }
        guard let idx = modelPresets.firstIndex(where: { $0.id == saved }) else { return }
        selectedModelIndex = idx
    }

    private func inferAndStoreModelForCurrentSessionIfMissing() {
        guard let sessionID = currentSessionID else { return }
        guard selectedModelIDBySessionID[sessionID] == nil else { return }

        guard let info = messages.reversed().compactMap({ $0.info.resolvedModel }).first else { return }
        guard let idx = modelPresets.firstIndex(where: { $0.providerID == info.providerID && $0.modelID == info.modelID }) else { return }

        selectedModelIndex = idx
        selectedModelIDBySessionID[sessionID] = modelPresets[idx].id
        persistSelectedModelMap()
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

    func loadSessions() async {
        guard isConnected else { return }
        do {
            sessions = try await apiClient.sessions()
            if currentSessionID == nil, let first = sessions.first {
                currentSessionID = first.id
                applySavedModelForCurrentSession()
            }
        } catch {
            connectionError = error.localizedDescription
        }
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
        
        streamingReasoningPart = nil
        streamingPartTexts = [:]
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
            
            self.inferAndStoreModelForCurrentSessionIfMissing()
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
            // keep previous value if any
        }
    }

    func createSession() async {
        guard isConnected else { return }
        
        let loadingID = UUID()
        sessionLoadingID = loadingID
        
        do {
            let session = try await apiClient.createSession()
            guard sessionLoadingID == loadingID else { return }
            
            sessions.insert(session, at: 0)
            currentSessionID = session.id
            if let m = selectedModel {
                selectedModelIDBySessionID[session.id] = m.id
                persistSelectedModelMap()
            }
            messages = []
            partsByMessage = [:]
        } catch {
            guard sessionLoadingID == loadingID else { return }
            connectionError = error.localizedDescription
        }
    }

    func loadMessages() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let loaded = try await apiClient.messages(sessionID: sessionID)
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("drop stale loadMessages result requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }

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

                let lastLoadedText = (lastLoadedUser.parts.first(where: { $0.isText })?.text ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let lastLoadedCreated = normalizeEpochMs(lastLoadedUser.info.time.created)

                return pending.filter { m in
                    guard m.info.isUser else { return true }
                    let text = (m.parts.first(where: { $0.isText })?.text ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, text == lastLoadedText else { return true }

                    let created = normalizeEpochMs(m.info.time.created)
                    if created == 0 || lastLoadedCreated == 0 { return false }
                    return abs(lastLoadedCreated - created) > 10 * 60 * 1000
                }
            }()

            let draftMessages = messages.filter {
                streamingDraftMessageIDs.contains($0.info.id) && !loadedMessageIDs.contains($0.info.id)
            }

            var merged: [MessageWithParts] = loaded
            for message in pendingMessages where !loadedMessageIDs.contains(message.info.id) {
                merged.append(message)
            }
            for message in draftMessages where !merged.contains(where: { $0.info.id == message.info.id }) {
                merged.append(message)
            }

            messages = merged
            partsByMessage = Dictionary(uniqueKeysWithValues: messages.map { ($0.info.id, $0.parts) })
            streamingDraftMessageIDs.subtract(loadedMessageIDs)

            if isBusySession(currentSessionStatus) {
                refreshSessionActivityText(sessionID: sessionID)
            }
        } catch let error as DecodingError {
            Self.logger.error("loadMessages decode failed: session=\(sessionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        } catch {
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else {
                Self.logger.debug("ignore stale loadMessages error requested=\(sessionID, privacy: .public) current=\(self.currentSessionID ?? "nil", privacy: .public)")
                return
            }
            connectionError = error.localizedDescription
            Self.logger.error("loadMessages failed: session=\(sessionID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
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
            guard Self.shouldApplySessionScopedResult(requestedSessionID: sessionID, currentSessionID: currentSessionID) else { return }
            sessionDiffs = []
        }
    }

    func loadFileTree() async {
        do {
            fileTreeRoot = try await apiClient.fileList(path: "")
        } catch {
            fileTreeRoot = []
        }
    }

    func loadFileStatus() async {
        do {
            let entries = try await apiClient.fileStatus()
            fileStatusMap = Dictionary(uniqueKeysWithValues: entries.compactMap { e in
                guard let p = e.path else { return nil }
                return (p, e.status ?? "")
            })
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
            fileSearchResults = try await apiClient.findFile(query: query)
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

    func transcribeAudio(audioFileURL: URL, language: String? = nil) async throws -> String {
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AIBuildersAudioError.missingToken }

        let base = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = aiBuilderCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = aiBuilderTerminology.trimmingCharacters(in: .whitespacesAndNewlines)
        let resp = try await AIBuildersAudioClient.transcribe(
            baseURL: base,
            token: token,
            audioFileURL: audioFileURL,
            language: language,
            prompt: prompt.isEmpty ? nil : prompt,
            terms: terms.isEmpty ? nil : terms
        )
        return resp.text
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
        do {
            try await apiClient.promptAsync(sessionID: sessionID, text: text, model: model)
            return true
        } catch {
            sendError = error.localizedDescription
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
                        streamingReasoningPart = nil
                        streamingPartTexts = [:]
                        streamingDraftMessageIDs.removeAll()
                    }
                }
            }
        case "session.updated":
            let infoVal = props["info"]?.value ?? props["session"]?.value
            if let infoObj = infoVal,
               JSONSerialization.isValidJSONObject(infoObj),
               let data = try? JSONSerialization.data(withJSONObject: infoObj),
               let session = try? JSONDecoder().decode(Session.self, from: data) {
                if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[idx] = session
                } else {
                    sessions.insert(session, at: 0)
                }
            }
        case "message.updated":
            let eventSessionID = props["sessionID"]?.value as? String
            if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
                streamingReasoningPart = nil
                streamingPartTexts = [:]
                streamingDraftMessageIDs.removeAll()
                await loadMessages()
                await loadSessionDiff()
            }
        case "message.part.updated":
            if let sessionID = props["sessionID"]?.value as? String,
               sessionID == currentSessionID {
                let partObj = props["part"]?.value as? [String: Any]
                let msgID = partObj?["messageID"] as? String
                let partID = partObj?["id"] as? String
                let partType = (partObj?["type"] as? String) ?? "text"

                if let msgID,
                   let partID {
                    let key = "\(msgID):\(partID)"

                    if let delta = props["delta"]?.value as? String,
                       !delta.isEmpty {
                        let text = (streamingPartTexts[key] ?? "") + delta
                        streamingPartTexts[key] = text
                        if partType == "reasoning" {
                            streamingReasoningPart = Part(
                                id: partID,
                                messageID: msgID,
                                sessionID: sessionID,
                                type: "reasoning",
                                text: nil,
                                tool: nil,
                                callID: nil,
                                state: nil,
                                metadata: nil,
                                files: nil
                            )
                        } else {
                            upsertStreamingMessage(
                                messageID: msgID,
                                partID: partID,
                                sessionID: sessionID,
                                type: partType,
                                text: text
                            )
                        }

                        refreshSessionActivityText(sessionID: sessionID)
                    } else {
                        clearStreamingState(messageID: msgID)
                        await loadMessages()
                        await loadSessionDiff()
                    }
                }
            }
        case "permission.asked":
            if let perm = PermissionController.parseAskedEvent(properties: props),
               !pendingPermissions.contains(where: { $0.id == perm.id }) {
                pendingPermissions.append(perm)
            }
        case "permission.replied":
            PermissionController.applyRepliedEvent(properties: props, to: &pendingPermissions)
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
            hasActiveStreaming: streamingReasoningPart?.sessionID == sessionID
                || !streamingPartTexts.isEmpty
                || !streamingDraftMessageIDs.isEmpty
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
                streamingReasoningPart = nil
                streamingPartTexts = [:]
                streamingDraftMessageIDs.removeAll()
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
                streamingReasoningPart = nil
                streamingPartTexts = [:]
                streamingDraftMessageIDs.removeAll()
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

    private func upsertStreamingMessage(
        messageID: String,
        partID: String,
        sessionID: String,
        type: String,
        text: String
    ) {
        let part = Part(
            id: partID,
            messageID: messageID,
            sessionID: sessionID,
            type: type,
            text: text,
            tool: nil,
            callID: nil,
            state: nil,
            metadata: nil,
            files: nil
        )

        if let idx = messages.firstIndex(where: { $0.info.id == messageID }) {
            let current = messages[idx]
            var updatedParts = current.parts
            if let partIdx = updatedParts.firstIndex(where: { $0.id == partID }) {
                updatedParts[partIdx] = part
            } else {
                updatedParts.append(part)
            }

            messages[idx] = MessageWithParts(info: current.info, parts: updatedParts)
            partsByMessage[messageID] = updatedParts
            streamingDraftMessageIDs.insert(messageID)
            return
        }

        let now = Int(Date().timeIntervalSince1970 * 1000)
        let message = Message(
            id: messageID,
            sessionID: sessionID,
            role: "assistant",
            parentID: messages.last?.info.id,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: Message.TimeInfo(created: now, completed: now),
            finish: nil,
            tokens: nil,
            cost: nil
        )

        messages.append(MessageWithParts(info: message, parts: [part]))
        partsByMessage[messageID] = [part]
        streamingDraftMessageIDs.insert(messageID)
    }

    private func clearStreamingState(messageID: String) {
        for key in streamingPartTexts.keys where key.hasPrefix("\(messageID):") {
            streamingPartTexts.removeValue(forKey: key)
        }

        if streamingReasoningPart?.messageID == messageID {
            streamingReasoningPart = nil
        }
        streamingDraftMessageIDs.remove(messageID)
    }

    func refresh() async {
        await testConnection()
        if isConnected {
            await loadProvidersConfig()
            await loadSessions()
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
