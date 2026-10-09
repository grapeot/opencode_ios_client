//
//  AppState.swift
//  OpenCodeClient
//

import Foundation
import CryptoKit
import Observation
import os
import VoiceFlowKit
#if os(iOS)
import UIKit
#endif

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

        var normalized = hasScheme ? trimmed : "\(scheme)://\(trimmed)"
        while normalized.hasSuffix("/"), normalized.count > 8 {
            normalized.removeLast()
        }
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
            defaults.set(newValue, forKey: Self.serverURLKey)
        }
    }

    var _username: String = ""
    var username: String {
        get { _username }
        set {
            _username = newValue
            defaults.set(newValue, forKey: Self.usernameKey)
        }
    }

    var _password: String = ""
    var password: String {
        get { _password }
        set {
            _password = newValue
            if newValue.isEmpty {
                try? KeychainHelper.delete(Self.passwordKeychainKey)
            } else {
                try? KeychainHelper.save(newValue, forKey: Self.passwordKeychainKey)
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
    static let aiBuilderRecordingStrategyKey = "aiBuilderRecordingStrategy"
    static let aiBuilderLastOKSignatureKey = "aiBuilderLastOKSignature"
    static let aiBuilderLastOKTestedAtKey = "aiBuilderLastOKTestedAt"
    static let draftInputsBySessionKey = "draftInputsBySession"
    static let selectedModelBySessionKey = "selectedModelBySession"
    static let selectedProjectWorktreeKey = "selectedProjectWorktree"
    static let customProjectPathKey = "customProjectPath"
    static let hostProfilesKey = "hostProfiles.v1"
    static let currentHostProfileIDKey = "currentHostProfileID.v1"
    static let aiUsageDashboardURLKey = "aiUsageDashboardURL"
    static let carModeEnabledKey = "carModeEnabled"
    static let languagePreferenceKey = L10n.languagePreferenceUserDefaultsKey
    static let carSessionsByContextKey = "carSessionsByContext.v1"
    static let healthExportPermissionKey = "clientCapability.healthExportAll.permission.v1"
    static let modelShortlistKey = "modelShortlist.v1"

    init(
        apiClient: APIClientProtocol = APIClient(),
        sseClient: SSEClientProtocol = SSEClient(),
        sshTunnelManager: SSHTunnelManager? = nil,
        aiUsageQuotaClient: AIUsageQuotaClientProtocol = AIUsageQuotaClient(),
        carSpeechOutput: CarSpeechOutputProviding? = nil,
        deepLinkSessionResolver: ((String) async throws -> Session)? = nil,
        deepLinkHydratesSelection: Bool = true,
        clientCapabilityStore: ClientCapabilityCallbackStore = .applicationSupport(),
        clientCapabilityURLOpener: (@MainActor (URL) async -> Bool)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.defaults = userDefaults
        self.sessionStore = SessionStore(defaults: userDefaults)
        // MessageStore persists finalized step timings; it must use the same
        // (test-isolated) defaults or suites would leak stepTimings across.
        self.messageStore = MessageStore(defaults: userDefaults)
        self.statsStore = SessionStatsStore(defaults: userDefaults)
        self.apiClient = apiClient
        self.sseClient = sseClient
        self.sshTunnelManager = sshTunnelManager ?? SSHTunnelManager()
        self.aiUsageQuotaClient = aiUsageQuotaClient
        self.carSpeechOutput = carSpeechOutput ?? CarSpeechOutputService()
        self.deepLinkSessionResolver = deepLinkSessionResolver
        self.deepLinkHydratesSelection = deepLinkHydratesSelection
        self.clientCapabilityStore = clientCapabilityStore
        self.clientCapabilityURLOpener = clientCapabilityURLOpener ?? { url in
            #if os(iOS)
            return await UIApplication.shared.open(url)
            #else
            return false
            #endif
        }
        if let storedServer = defaults.string(forKey: Self.serverURLKey) {
            if storedServer == APIConstants.legacyDefaultServer {
                _serverURL = APIClient.defaultServer
                defaults.set(APIClient.defaultServer, forKey: Self.serverURLKey)
            } else {
                _serverURL = storedServer
            }
        } else {
            _serverURL = APIClient.defaultServer
        }
        _username = defaults.string(forKey: Self.usernameKey) ?? ""
        _password = (try? KeychainHelper.load(forKey: Self.passwordKeychainKey)) ?? ""
        loadHostProfilesFromStorageOrLegacy()
        applyCurrentHostProfileToRuntime(persistLegacy: false)

        _aiBuilderBaseURL = defaults.string(forKey: Self.aiBuilderBaseURLKey) ?? "https://space.ai-builders.com/backend"
        _aiBuilderToken = (try? KeychainHelper.load(forKey: Self.aiBuilderTokenKeychainKey)) ?? ""
        _aiBuilderCustomPrompt = defaults.string(forKey: Self.aiBuilderCustomPromptKey) ?? Self.defaultAIBuilderCustomPrompt
        _aiBuilderTerminology = defaults.string(forKey: Self.aiBuilderTerminologyKey) ?? Self.defaultAIBuilderTerminology
        _aiBuilderRecordingStrategy = VoiceFlowRecordingStrategy(
            rawValue: defaults.string(forKey: Self.aiBuilderRecordingStrategyKey) ?? ""
        ) ?? .gptLiveTranscribe
        _selectedProjectWorktree = defaults.string(forKey: Self.selectedProjectWorktreeKey)
        _customProjectPath = defaults.string(forKey: Self.customProjectPathKey) ?? ""
        _languagePreference = L10n.languagePreference
        _aiUsageDashboardURL = defaults.string(forKey: Self.aiUsageDashboardURLKey) ?? ""
        isCarModeEnabled = defaults.bool(forKey: Self.carModeEnabledKey)
        healthExportPermission = ClientCapabilityPermission(
            rawValue: defaults.string(forKey: Self.healthExportPermissionKey) ?? ""
        ) ?? .ask

        // Restore last known-good AI Builder connection state if token/baseURL unchanged.
        let storedSig = defaults.string(forKey: Self.aiBuilderLastOKSignatureKey)
        let currentSig = Self.aiBuilderSignature(baseURL: _aiBuilderBaseURL, token: _aiBuilderToken)
        if let storedSig, storedSig == currentSig, !currentSig.isEmpty {
            aiBuilderConnectionOK = true
            if let ts = defaults.object(forKey: Self.aiBuilderLastOKTestedAtKey) as? Double {
                aiBuilderLastTestedAt = Date(timeIntervalSince1970: ts)
            }
        }

        if let data = defaults.data(forKey: Self.draftInputsBySessionKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            draftInputsBySessionID = decoded
        }

        if let data = defaults.data(forKey: Self.selectedModelBySessionKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            selectedModelIDBySessionID = decoded
        }

        if let data = defaults.data(forKey: Self.carSessionsByContextKey),
           let decoded = try? JSONDecoder().decode([String: CarSessionRecord].self, from: data) {
            carSessionsByContext = decoded
        }

        if let data = defaults.data(forKey: Self.modelShortlistKey),
           let decoded = try? JSONDecoder().decode([ModelShortlistItem].self, from: data) {
            modelShortlist = decoded
        }
    }

    var sessionScope = SessionScopedState()

    var draftInputsBySessionID: [String: String] {
        get { sessionScope.draftInputs }
        set { sessionScope.draftInputs = newValue }
    }

    var selectedModelIDBySessionID: [String: String] {
        get { sessionScope.selectedModelIDs }
        set { sessionScope.selectedModelIDs = newValue }
    }

    var hostProfiles: [HostProfile] = [] {
        didSet { saveHostProfiles() }
    }

    var currentHostProfileID: UUID = UUID() {
        didSet { defaults.set(currentHostProfileID.uuidString, forKey: Self.currentHostProfileIDKey) }
    }

    var currentHostProfile: HostProfile? {
        hostProfiles.first { $0.id == currentHostProfileID }
    }

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
            defaults.set(newValue, forKey: Self.aiBuilderBaseURLKey)
            aiBuilderConnectionOK = false
            aiBuilderConnectionError = nil
            aiBuilderLastTestedAt = nil
            defaults.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            defaults.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
        }
    }

    var _aiBuilderToken: String = ""
    var aiBuilderToken: String {
        get { _aiBuilderToken }
        set {
            _aiBuilderToken = newValue
            if newValue.isEmpty {
                try? KeychainHelper.delete(Self.aiBuilderTokenKeychainKey)
            } else {
                try? KeychainHelper.save(newValue, forKey: Self.aiBuilderTokenKeychainKey)
            }
            aiBuilderConnectionOK = false
            aiBuilderConnectionError = nil
            aiBuilderLastTestedAt = nil
            defaults.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            defaults.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
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
            defaults.set(newValue, forKey: Self.aiBuilderCustomPromptKey)
        }
    }

    var _aiBuilderTerminology: String = ""
    var aiBuilderTerminology: String {
        get { _aiBuilderTerminology }
        set {
            _aiBuilderTerminology = newValue
            defaults.set(newValue, forKey: Self.aiBuilderTerminologyKey)
        }
    }

    var _aiBuilderRecordingStrategy: VoiceFlowRecordingStrategy = .gptLiveTranscribe
    var aiBuilderRecordingStrategy: VoiceFlowRecordingStrategy {
        get { _aiBuilderRecordingStrategy }
        set {
            _aiBuilderRecordingStrategy = newValue
            defaults.set(newValue.rawValue, forKey: Self.aiBuilderRecordingStrategyKey)
        }
    }

    var aiBuilderConnectionError: String? = nil
    var aiBuilderConnectionOK: Bool = false
    var aiBuilderLastTestedAt: Date? = nil
    var isTestingAIBuilderConnection: Bool = false
    var _aiUsageDashboardURL: String = ""
    var aiUsageDashboardURL: String {
        get { _aiUsageDashboardURL }
        set {
            _aiUsageDashboardURL = newValue
            defaults.set(newValue, forKey: Self.aiUsageDashboardURLKey)
            aiUsageQuotaState = .idle
            aiUsageQuotaTestOK = false
            aiUsageQuotaError = nil
        }
    }
    var aiUsageQuotaState: AIUsageQuotaState = .idle
    var isRefreshingAIUsageProviders = false
    var aiUsageQuotaTestOK = false
    var aiUsageQuotaError: String?
    var isCarModeEnabled = false {
        didSet { defaults.set(isCarModeEnabled, forKey: Self.carModeEnabledKey) }
    }
    var isConnected: Bool = false
    var serverVersion: String?
    var connectionError: String?
    var connectionDiagnostic: ConnectionDiagnostic?
    var pendingSSHHostKeyMismatch: SSHHostKeyMismatch?
    var sendError: String?
    var pendingDeepLink: OpenCodeDeepLink?
    var deepLinkRouteState: DeepLinkRouteState = .idle
    var deepLinkError: String?
    var deepLinkRouteID = UUID()

    var sessionActivities: [String: SessionActivity] {
        get { sessionScope.activities }
        set { sessionScope.activities = newValue }
    }

    var sessionStatusUpdatedAt: [String: Date] {
        get { sessionScope.statusUpdatedAt }
        set { sessionScope.statusUpdatedAt = newValue }
    }

    var activityTextLastChangeAt: [String: Date] {
        get { sessionScope.activityTextLastChangeAt }
        set { sessionScope.activityTextLastChangeAt = newValue }
    }

    var activityTextPendingTask: [String: Task<Void, Never>] {
        get { sessionScope.activityTextPendingTask }
        set { sessionScope.activityTextPendingTask = newValue }
    }

    var currentSessionActivity: SessionActivity? {
        guard let sid = currentSessionID else { return nil }
        return sessionActivities[sid]
    }

    func activityTextForSession(_ sessionID: String) -> String {
        ActivityTracker.bestSessionActivityText(
            sessionID: sessionID,
            currentSessionID: currentSessionID,
            sessionStatuses: sessionStatuses,
            messages: messages
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

    let defaults: UserDefaults
    let sessionStore: SessionStore
    let messageStore: MessageStore
    let fileStore = FileStore()
    let todoStore = TodoStore()
    let statsStore: SessionStatsStore
    /// Sessions whose stats must be reset from the post-revert window on the
    /// next `loadMessages` (revert truncates history beyond window visibility).
    var revertResetPendingSessionIDs: Set<String> = []

    var sessions: [Session] { get { sessionStore.sessions } set { sessionStore.sessions = newValue } }
    var sortedSessions: [Session] {
        sessions
            .sorted { $0.time.updated > $1.time.updated }
    }
    var sidebarSessions: [Session] {
        sessions
            .filter { $0.parentID == nil }
            .sorted { $0.time.updated > $1.time.updated }
    }
    var sessionTree: [SessionNode] {
        Self.buildSessionTree(from: sessions)
    }
    var currentSessionID: String? { get { sessionStore.currentSessionID } set { sessionStore.currentSessionID = newValue } }
    var sessionStatuses: [String: SessionStatus] { get { sessionStore.sessionStatuses } set { sessionStore.sessionStatuses = newValue } }

    var messages: [MessageWithParts] { get { messageStore.messages } set { messageStore.messages = newValue } }
    var partsByMessage: [String: [Part]] { get { messageStore.partsByMessage } set { messageStore.partsByMessage = newValue } }
    var stepTimings: [String: MessageStore.StepTiming] { get { messageStore.stepTimings } set { messageStore.stepTimings = newValue } }

    /// The given session plus every descendant subagent session (linked via
    /// `parentID`), cycle-safe, with the requested session first. Subagents
    /// are same-project sessions spawned by the `task` tool; only those
    /// currently in the loaded session list are returned (pagination
    /// boundary — accepted, off-window subagents are always finished).
    func sessionGroup(including sessionID: String) -> [Session] {
        var seen = Set<String>([sessionID])
        var descendants: [Session] = []
        func visit(_ id: String) {
            for child in sessions where child.parentID == id {
                guard seen.insert(child.id).inserted else { continue }
                descendants.append(child)
                visit(child.id)
            }
        }
        visit(sessionID)
        guard let main = sessions.first(where: { $0.id == sessionID }) else {
            return descendants
        }
        return [main] + descendants
    }

    /// Status-line token total: the session's own cumulative usage plus every
    /// descendant subagent session's, so the number reflects what the whole
    /// conversation tree consumed. The session's own part prefers the
    /// server-maintained aggregate (pushed with every `session.updated`) and
    /// falls back to the loaded message window only when it covers the full
    /// history; subagent parts are aggregate-only, since their message
    /// windows are not loaded. The total is reported only when the session's
    /// own part is knowable — the status line never shows a number it cannot
    /// stand behind.
    func sessionTotalTokens(sessionID: String) -> Int? {
        let group = sessionGroup(including: sessionID)
        let main = group.first { $0.id == sessionID }
        var ownTotal: Int?
        if let own = main?.tokens, own.total > 0 {
            ownTotal = own.total
        } else if main != nil, hasMoreHistoryBySessionID[sessionID] == false {
            let windowSum = messages
                .filter { $0.info.isAssistant }
                .reduce(0) { $0 + ($1.info.tokens?.total ?? 0) }
            ownTotal = windowSum > 0 ? windowSum : nil
        }
        guard let base = ownTotal else { return nil }
        var total = base
        for sub in group.dropFirst() {
            if let tokens = sub.tokens, tokens.total > 0 {
                total += tokens.total
            }
        }
        return total
    }

    /// Status-line cache hit rate over the whole conversation tree: cached
    /// input divided by all input, summed across the session and every
    /// descendant subagent (the aggregate keeps `input` non-cached with
    /// `cache.read` alongside, so the two partition the input side). The
    /// session's own part uses the server aggregate, or the loaded message
    /// window when it covers the full history; subagent parts are
    /// aggregate-only. Reported only when the session's own part is
    /// knowable, mirroring `sessionTotalTokens`.
    func sessionCacheHitRate(sessionID: String) -> Double? {
        let group = sessionGroup(including: sessionID)
        let main = group.first { $0.id == sessionID }
        let ownKnown = main?.tokens != nil || hasMoreHistoryBySessionID[sessionID] == false
        guard ownKnown else { return nil }
        var freshInput = 0
        var cacheRead = 0
        for session in group {
            // An input-less aggregate (fresh session) carries no rate
            // information; the main session then falls back to its window.
            if let tokens = session.tokens, tokens.input + (tokens.cache?.read ?? 0) > 0 {
                freshInput += tokens.input
                cacheRead += tokens.cache?.read ?? 0
            } else if session.id == sessionID, hasMoreHistoryBySessionID[sessionID] == false {
                for row in messages where row.info.isAssistant {
                    freshInput += row.info.tokens?.input ?? 0
                    cacheRead += row.info.tokens?.cache?.read ?? 0
                }
            }
        }
        return Self.cacheHitRate(freshInput: freshInput, cacheRead: cacheRead)
    }

    private static func cacheHitRate(freshInput: Int, cacheRead: Int) -> Double? {
        let denominator = freshInput + cacheRead
        guard denominator > 0 else { return nil }
        return Double(cacheRead) / Double(denominator)
    }

    var selectedModelIndex: Int = 2
    
    var agents: [AgentInfo] = [
        AgentInfo(name: "OpenCode-Builder", description: "Build agent (OpenCode default)", mode: "all", hidden: false, native: false),
        AgentInfo(name: "Sisyphus (Ultraworker)", description: "Powerful AI orchestrator", mode: "primary", hidden: false, native: false),
        AgentInfo(name: "Hephaestus (Deep Agent)", description: "Autonomous Deep Worker", mode: "primary", hidden: false, native: false),
        AgentInfo(name: "Prometheus (Plan Builder)", description: "Plan agent", mode: "all", hidden: false, native: false),
        AgentInfo(name: "Atlas (Plan Executor)", description: "Plan Executor", mode: "primary", hidden: false, native: false),
    ]
    var selectedAgentIndex: Int = 0
    /// Name actually sent to the server. Not an index into a previous host's list.
    var selectedAgentName: String = AgentInfo.fallbackAgentName
    /// True only after GET /agent succeeds for the current host.
    var hasServerAgentCatalog: Bool = false
    var isLoadingAgents: Bool = false

    var expandedSessionIDs: Set<String> = []

    func filteredSessions(archived: Bool) -> [Session] {
        return sessions
            .filter { $0.isArchived == archived }
            .sorted { $0.time.updated > $1.time.updated }
    }

    func sessionTree(archived: Bool) -> [SessionNode] {
        Self.prioritizeAttention(
            Self.buildSessionTree(from: filteredSessions(archived: archived)),
            attentionCounts: sessionAttentionCounts,
            descendantBusyCounts: sessionDescendantBusyCounts
        )
    }

    var attentionSessionIDs: [String] {
        pendingPermissions.map(\.sessionID) + pendingQuestions.map(\.sessionID)
    }

    var sessionAttentionCounts: [String: Int] {
        Self.attentionCountsBySession(
            sessions: sessions,
            attentionSessionIDs: attentionSessionIDs
        )
    }

    /// Number of running descendant subagent sessions per session, derived from
    /// the global `sessionStatuses` map along `parentID` links. A session's own
    /// busy state is never counted, so a row can render a distinct "subagents
    /// running" signal side by side with (and subordinate to) its own Running.
    var sessionDescendantBusyCounts: [String: Int] {
        Self.descendantBusyCountsBySession(
            sessions: sessions,
            sessionStatuses: sessionStatuses
        )
    }

    /// Busy descendant subagent sessions of `sessionID`, most recently updated
    /// first. Drives the composer "background tasks running" segment; BFS over
    /// `parentID` links is cycle-safe and covers arbitrary nesting.
    func runningDescendantSessions(of sessionID: String) -> [Session] {
        let childrenByParent = Dictionary(grouping: sessions, by: \.parentID)
        var running: [Session] = []
        var visited = Set<String>([sessionID])
        var queue = [sessionID]
        while let current = queue.first {
            queue.removeFirst()
            for child in childrenByParent[current] ?? [] {
                guard visited.insert(child.id).inserted else { continue }
                if isBusySession(sessionStatuses[child.id]) {
                    running.append(child)
                }
                queue.append(child.id)
            }
        }
        return running.sorted { $0.time.updated > $1.time.updated }
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
            defaults.set(newValue, forKey: Self.selectedProjectWorktreeKey)
        }
    }
    var _selectedProjectWorktree: String?

    var customProjectPath: String {
        get { _customProjectPath }
        set {
            _customProjectPath = newValue
            defaults.set(newValue, forKey: Self.customProjectPathKey)
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

    var pendingPermissions: [PendingPermission] {
        get { sessionScope.pendingPermissions }
        set { sessionScope.pendingPermissions = newValue }
    }

    var pendingQuestions: [QuestionRequest] {
        get { sessionScope.pendingQuestions }
        set { sessionScope.pendingQuestions = newValue }
    }

    var themePreference: String = "auto"  // "auto" | "light" | "dark"
    var _languagePreference: L10n.LanguagePreference = .system
    var languagePreference: L10n.LanguagePreference {
        get { _languagePreference }
        set {
            _languagePreference = newValue
            L10n.languagePreference = newValue
        }
    }

    var sessionDiffs: [FileDiff] { get { fileStore.sessionDiffs } set { fileStore.sessionDiffs = newValue } }
    var selectedDiffFile: String? { get { fileStore.selectedDiffFile } set { fileStore.selectedDiffFile = newValue } }
    var selectedTab: Int = RootTab.chat.rawValue
    /// When set, Settings should open and pulse the matching row.
    var settingsFocus: SettingsFocus?
    var fileToOpenInFilesTab: String?  // 从 Chat 中 tool 点击跳转时设置，Files tab 或 sheet 展示
    var fileToOpenInFilesTabWorkspaceDirectory: String?

    /// iPad 三栏布局：中间栏文件预览
    var previewFilePath: String?
    var previewFileWorkspaceDirectory: String?

    var sessionTodos: [String: [TodoItem]] { get { todoStore.sessionTodos } set { todoStore.sessionTodos = newValue } }

    var fileTreeRoot: [FileNode] { get { fileStore.fileTreeRoot } set { fileStore.fileTreeRoot = newValue } }
    var fileStatusMap: [String: String] { get { fileStore.fileStatusMap } set { fileStore.fileStatusMap = newValue } }
    var expandedPaths: Set<String> { get { fileStore.expandedPaths } set { fileStore.expandedPaths = newValue } }
    var fileChildrenCache: [String: [FileNode]] { get { fileStore.fileChildrenCache } set { fileStore.fileChildrenCache = newValue } }
    var fileSearchQuery: String { get { fileStore.fileSearchQuery } set { fileStore.fileSearchQuery = newValue } }
    var fileSearchResults: [String] { get { fileStore.fileSearchResults } set { fileStore.fileSearchResults = newValue } }

    // Provider config cache (for context usage ring + dynamic model picker)
    var providersResponse: ProvidersResponse? = nil
    var providerModelsIndex: [String: ProviderModel] = [:]
    var providerConfigError: String? = nil
    /// Full chat-capable catalog from connected providers. Settings search
    /// uses this; the chat picker does not.
    var catalogModelPresets: [ModelPreset] = []
    /// Device-local picker membership. Persisted separately from the desktop
    /// manage-models store, which the server API does not expose.
    var modelShortlist: [ModelShortlistItem] = [] {
        didSet {
            persistModelShortlist()
            rebuildPickerModelItems(reason: "shortlist")
        }
    }
    /// Catalog alias for existing tests and diagnostics.
    var dynamicModelPresets: [ModelPreset] { catalogModelPresets }
    /// Provider display names for grouping the dynamic picker
    /// (providerID -> human name, e.g. "ollama" -> "Ollama (local)").
    var providerDisplayNames: [String: String] = [:]
    /// Model picker search text. Lives in AppState (not view @State) because
    /// the iOS 26 sheet content closure does not track the presenting view's
    /// @State updates — device log pdiag3: cached=18 groups but the sheet's
    /// List evaluated modelGroups as empty and dropped the agent section.
    var modelSearchText: String = ""
    /// Flat picker rows (provider header rows + model rows) rendered as one
    /// Section. Flat because iOS 26 List mis-diffs ForEach-generated dynamic
    /// Sections (pdiag1: false duplicate-ID warnings; pdiag2/3: zero rendered).
    var pickerModelItems: [ModelPickerItem] = []
    var pickerModelGen = 0

    let apiClient: APIClientProtocol
    let sseClient: SSEClientProtocol
    let sshTunnelManager: SSHTunnelManager
    let aiUsageQuotaClient: AIUsageQuotaClientProtocol
    let deepLinkSessionResolver: ((String) async throws -> Session)?
    let deepLinkHydratesSelection: Bool
    var sseTask: Task<Void, Never>?
    /// Time the last SSE frame of any type (including heartbeats) was
    /// received. Internal so unit tests can pre-seed it and drive
    /// `checkSSEWatchdog()` deterministically.
    var sseLastFrameAt: Date?
    /// Heartbeat watchdog task; same lifecycle as `sseTask` (launched after a
    /// successful connect + bootstrap, cancelled when the stream ends).
    var sseWatchdogTask: Task<Void, Never>?
    nonisolated static let sseWatchdogCheckInterval: TimeInterval = 5
    nonisolated static let sseSilenceThreshold: TimeInterval = 20

    var carSessionsByContext: [String: CarSessionRecord] = [:]
    var carPhase: CarModePhase = .idle
    var carLastTranscript = ""
    var carLastResponse: CarResponseEnvelope?
    var carError: String?
    var carActiveTurnID: UUID?
    var carActiveCapabilityCallbackID: String?
    let carSpeechOutput: CarSpeechOutputProviding
    let clientCapabilityStore: ClientCapabilityCallbackStore
    let clientCapabilityURLOpener: @MainActor (URL) async -> Bool
    var pendingClientCapabilityRequest: PendingClientCapabilityRequest?
    var clientCapabilityError: String?
    var clientCapabilityInFlightCallbackIDs: Set<String> = []
    var healthExportPermission: ClientCapabilityPermission = .ask {
        didSet {
            if healthExportPermission == .ask {
                defaults.removeObject(forKey: Self.healthExportPermissionKey)
            } else {
                defaults.set(healthExportPermission.rawValue, forKey: Self.healthExportPermissionKey)
            }
        }
    }

    /// Guard against race conditions when rapidly switching sessions.
    /// Each selectSession call generates a new ID; async tasks check if they're still current.
    var sessionLoadingID = UUID()
    nonisolated private static let sessionPageSize = 400
    var loadedSessionLimit = sessionPageSize
    var hasMoreSessions = true
    var isLoadingMoreSessions = false

    var canLoadMoreSessions: Bool {
        hasMoreSessions && !isLoadingMoreSessions
    }

    // WAN optimization: page message history in fixed-size message batches.
    nonisolated private static let messagePageSize = 20
    var loadedMessageLimitBySessionID: [String: Int] {
        get { sessionScope.loadedMessageLimit }
        set { sessionScope.loadedMessageLimit = newValue }
    }

    var hasMoreHistoryBySessionID: [String: Bool] {
        get { sessionScope.hasMoreHistory }
        set { sessionScope.hasMoreHistory = newValue }
    }

    var loadingOlderMessagesSessionIDs: Set<String> {
        get { sessionScope.loadingOlderMessages }
        set { sessionScope.loadingOlderMessages = newValue }
    }

    var selectedModel: ModelPreset? {
        pickerModelPresets.indices.contains(selectedModelIndex) ? pickerModelPresets[selectedModelIndex] : nil
    }

    /// Chat picker source: only the local shortlist.
    var pickerModelPresets: [ModelPreset] {
        modelShortlist.map { $0.asPreset() }
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

    nonisolated static func attentionCountsBySession(
        sessions: [Session],
        attentionSessionIDs: [String]
    ) -> [String: Int] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var counts: [String: Int] = [:]

        for sourceSessionID in attentionSessionIDs {
            var sessionID: String? = sourceSessionID
            var visited: Set<String> = []
            while let currentSessionID = sessionID, visited.insert(currentSessionID).inserted {
                counts[currentSessionID, default: 0] += 1
                sessionID = sessionsByID[currentSessionID]?.parentID
            }
        }
        return counts
    }

    /// Aggregates running descendant subagents up the `parentID` chain: each
    /// session gets the count of busy sessions strictly below it in the loaded
    /// tree. Counting walks ancestors and stops at the first non-busy node, so
    /// a session never contributes to its own count and a running chain is
    /// counted once per ancestor. Cycle-safe; scoped to the loaded `sessions`
    /// list (the global status map may carry other projects).
    nonisolated static func descendantBusyCountsBySession(
        sessions: [Session],
        sessionStatuses: [String: SessionStatus]
    ) -> [String: Int] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        func isBusy(_ id: String) -> Bool {
            guard let type = sessionStatuses[id]?.type else { return false }
            return type == "busy" || type == "retry"
        }

        var counts: [String: Int] = [:]
        for session in sessions where isBusy(session.id) {
            var ancestorID = sessionsByID[session.id]?.parentID
            var visited: Set<String> = []
            while let current = ancestorID, visited.insert(current).inserted {
                counts[current, default: 0] += 1
                ancestorID = sessionsByID[current]?.parentID
            }
        }
        return counts
    }

    nonisolated static func prioritizeAttention(
        _ nodes: [SessionNode],
        attentionCounts: [String: Int],
        descendantBusyCounts: [String: Int] = [:]
    ) -> [SessionNode] {
        nodes
            .map { node in
                SessionNode(
                    session: node.session,
                    children: prioritizeAttention(
                        node.children,
                        attentionCounts: attentionCounts,
                        descendantBusyCounts: descendantBusyCounts
                    )
                )
            }
            .sorted { lhs, rhs in
                // A collapsed row hides its children, so a tree whose delegated
                // work is still running must surface by its parent row the same
                // way an attention-needing tree does.
                let lhsSurfaces = attentionCounts[lhs.id, default: 0] > 0
                    || descendantBusyCounts[lhs.id, default: 0] > 0
                let rhsSurfaces = attentionCounts[rhs.id, default: 0] > 0
                    || descendantBusyCounts[rhs.id, default: 0] > 0
                if lhsSurfaces != rhsSurfaces {
                    return lhsSurfaces
                }
                return lhs.session.time.updated > rhs.session.time.updated
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
        // Diagnostics: build stamp + registry summary. One line per launch,
        // enough to identify which binary is running and what the server
        // returned, without dumping the whole payload.
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

        // The dynamic picker prefers the /provider registry: it knows which
        // providers are connected (incl. keyless local ones like Ollama),
        // so the picker shows only models the user can actually run.
        if let registry = try? await apiClient.providerRegistry() {
            rebuildDynamicModelPresets(from: registry)
        } else if catalogModelPresets.isEmpty {
            Self.logger.warning("loadProvidersConfig: /provider registry unavailable, catalog unchanged")
        }
    }

    /// Builds the Settings catalog from connected chat-capable models.
    /// The chat picker reads `modelShortlist`, not this list.
    func rebuildDynamicModelPresets(from registry: ProviderRegistryResponse) {
        let connected = Set(registry.connectedProviderIDs)
        var names: [String: String] = [:]
        var presets: [ModelPreset] = []
        for provider in registry.providers where connected.contains(provider.id) {
            if let n = provider.name, !n.isEmpty { names[provider.id] = n }
            for (modelID, model) in provider.models.sorted(by: { $0.key < $1.key }) {
                guard model.capabilities?.isChatCapable ?? true else { continue }
                presets.append(
                    ModelPreset(
                        displayName: model.name ?? modelID,
                        providerID: provider.id,
                        modelID: modelID
                    )
                )
            }
        }
        presets.sort { a, b in
            if a.providerID != b.providerID { return a.providerID < b.providerID }
            return a.displayName < b.displayName
        }
        catalogModelPresets = presets
        providerDisplayNames = names
        refreshShortlistDisplayNames(from: presets)
        reanchorSelectedModelIndex()
        rebuildPickerModelItems(reason: "catalog")
    }

    func revealModelShortlistInSettings() {
        settingsFocus = .modelShortlist
        selectedTab = RootTab.settings.rawValue
    }

    func persistModelShortlist() {
        if let data = try? JSONEncoder().encode(modelShortlist) {
            defaults.set(data, forKey: Self.modelShortlistKey)
        }
    }

    func addModelsToShortlist(_ presets: [ModelPreset]) {
        var existing = Set(modelShortlist.map(\.id))
        var next = modelShortlist
        for preset in presets where !existing.contains(preset.id) {
            next.append(ModelShortlistItem.from(preset))
            existing.insert(preset.id)
        }
        guard next.count != modelShortlist.count else { return }
        modelShortlist = next
        reanchorSelectedModelIndex()
    }

    func removeShortlistItem(id: String) {
        modelShortlist.removeAll { $0.id == id }
        reanchorSelectedModelIndex()
    }

    func moveShortlist(from source: IndexSet, to destination: Int) {
        var next = modelShortlist
        let moving = source.sorted().map { next[$0] }
        for index in source.sorted().reversed() {
            next.remove(at: index)
        }
        let dest = min(max(destination - source.filter { $0 < destination }.count, 0), next.count)
        next.insert(contentsOf: moving, at: dest)
        modelShortlist = next
        reanchorSelectedModelIndex()
    }

    func updateShortlistShortName(id: String, shortName: String) {
        guard let idx = modelShortlist.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = modelShortlist[idx]
        item.shortName = trimmed.isEmpty ? ModelPreset.suggestedShortName(for: item.displayName) : trimmed
        modelShortlist[idx] = item
    }

    private func refreshShortlistDisplayNames(from catalog: [ModelPreset]) {
        guard !modelShortlist.isEmpty else { return }
        let names = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.displayName) })
        var changed = false
        var next = modelShortlist
        for i in next.indices {
            if let name = names[next[i].id], name != next[i].displayName {
                next[i].displayName = name
                changed = true
            }
        }
        if changed { modelShortlist = next }
    }

    /// Rebuilds the flat picker rows (provider header + models) from the
    /// current picker source list and search text. AppState-backed so the
    /// sheet observes it directly.
    func rebuildPickerModelItems(reason: String) {
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = pickerModelPresets.enumerated().filter { _, preset in
            query.isEmpty
                || preset.displayName.lowercased().contains(query)
                || preset.modelID.lowercased().contains(query)
                || preset.providerID.lowercased().contains(query)
        }
        pickerModelItems = filtered.map { ModelPickerItem.model(index: $0.offset, preset: $0.element) }
        pickerModelGen += 1
    }

    /// After the picker list is rebuilt, point `selectedModelIndex` at the
    /// same model in the new list (or the canonical successor for aged ids).
    private func reanchorSelectedModelIndex() {
        let savedID = currentSessionID.flatMap { selectedModelIDBySessionID[$0] }
            ?? selectedModel.map { $0.id }
            ?? pickerModelPresets.first?.id
        guard let savedID else { return }
        let canonical = canonicalModelPresetID(for: savedID)
        if let idx = pickerModelPresets.firstIndex(where: { $0.id == canonical }) {
            selectedModelIndex = idx
        } else if !pickerModelPresets.isEmpty {
            selectedModelIndex = 0
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
