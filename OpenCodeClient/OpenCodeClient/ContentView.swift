//
//  ContentView.swift
//  OpenCodeClient
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum RootTab: Int {
    case chat
    case files
    case car
    case settings
}

struct ContentView: View {
    @State private var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettingsSheet = false
    @State private var showTabletSettings = false
    @State private var selectedTab = 0
    @State private var carModeEnabled: Bool

    init() {
        let initialState = Self.makeInitialState()
        _state = State(initialValue: initialState)
        _carModeEnabled = State(initialValue: initialState.isCarModeEnabled)
    }

    private static var hasUITestSessionTreeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_SESSION_TREE_FIXTURE")
    }

    private static var hasUITestToolCardsFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_TOOL_CARDS_FIXTURE")
    }

    private static var hasUITestF3ComposerFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_F3_TRANSCRIBING_FIXTURE")
            || ProcessInfo.processInfo.arguments.contains("UITEST_F3_RETRY_FIXTURE")
    }

    private static var hasUITestWebPreviewFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_WEB_PREVIEW_FIXTURE")
    }

    private static var hasUITestHostProfilesFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_HOST_PROFILES_FIXTURE")
    }

    private static var hasUITestQuotaFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_QUOTA_FIXTURE")
    }

    private static var hasUITestCarModeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CAR_MODE_FIXTURE")
    }

    private static var hasUITestCarHistoryFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CAR_HISTORY_FIXTURE")
    }

    private static var hasUITestCarDisabledFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CAR_DISABLED_FIXTURE")
    }

    private static var hasUITestClientCapabilityFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CLIENT_CAPABILITY_FIXTURE")
    }

    private static var hasUITestDeepLinkFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("UITEST_DEEP_LINK_FIXTURE")
        #else
        false
        #endif
    }

    /// Which bundled fixture markdown to render in the web preview. Defaults to
    /// the HTML-cards fixture; override via WEB_PREVIEW_FIXTURE_NAME env var.
    private static var webPreviewFixtureName: String {
        let env = ProcessInfo.processInfo.environment["WEB_PREVIEW_FIXTURE_NAME"]
        return (env?.isEmpty == false ? env! : "html_cards")
    }

    private static func loadFixtureMarkdown(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "WebPreviewFixtures")
            ?? Bundle.main.url(forResource: name, withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "# Fixture not found: \(name)"
        }
        return text
    }

    private static func makeInitialState() -> AppState {
        let state: AppState
        if hasUITestDeepLinkFixture {
            state = AppState(
                deepLinkSessionResolver: { sessionID in
                    guard sessionID == "ses_deep_link_target" else {
                        throw APIError.httpError(statusCode: 404, data: Data())
                    }
                    return deepLinkFixtureSession(
                        id: sessionID,
                        title: "Deep Link Target",
                        directory: "/tmp/deep-link-target"
                    )
                },
                deepLinkHydratesSelection: false
            )
        } else {
            state = AppState()
        }

        if hasUITestDeepLinkFixture {
            applyDeepLinkFixture(to: state)
            return state
        }

        if hasUITestCarHistoryFixture {
            applyCarHistoryFixture(to: state)
            return state
        }

        if hasUITestCarDisabledFixture {
            state.isCarModeEnabled = false
            state.selectedTab = RootTab.chat.rawValue
            return state
        }

        if hasUITestCarModeFixture {
            state.isConnected = true
            state.isCarModeEnabled = true
            state.selectedTab = RootTab.car.rawValue
            state.carLastTranscript = "Navigate to Space Needle and avoid the traffic on I-5."
            state.carLastResponse = CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "I found a faster route. It saves twelve minutes and is ready in Apple Maps.",
                confirmation: nil,
                clientActions: []
            )
            return state
        }

        if hasUITestClientCapabilityFixture {
            state.pendingClientCapabilityRequest = PendingClientCapabilityRequest(
                action: .healthExportAll(id: "health-fixture", reason: "Sync last night's sleep data before analysis"),
                hostProfileID: state.currentHostProfileID,
                sessionID: "ses_health_fixture",
                carContextKey: "fixture|health",
                assistantMessageID: "msg_health_fixture"
            )
            return state
        }

        if hasUITestQuotaFixture {
            applyQuotaFixture(to: state)
            return state
        }

        if hasUITestHostProfilesFixture {
            applyHostProfilesFixture(to: state)
            return state
        }

        if hasUITestF3ComposerFixture {
            applyF3ComposerFixture(to: state)
            return state
        }

        if hasUITestToolCardsFixture {
            applyToolCardsFixture(to: state)
            return state
        }

        guard hasUITestSessionTreeFixture else { return state }

        state.isConnected = true
        state.sessions = [
            Session(
                id: "root-session",
                slug: "root-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Root Session",
                version: "1",
                time: .init(created: 0, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            ),
            Session(
                id: "child-session",
                slug: "child-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: "root-session",
                title: "Child Session",
                version: "1",
                time: .init(created: 0, updated: 1_500, archived: nil),
                share: nil,
                summary: nil
            ),
            Session(
                id: "archived-session",
                slug: "archived-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Archived Session",
                version: "1",
                time: .init(created: 0, updated: 1_200, archived: 3_000),
                share: nil,
                summary: nil
            ),
            Session(
                id: "archived-child-session",
                slug: "archived-child-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: "archived-session",
                title: "Archived Child",
                version: "1",
                time: .init(created: 0, updated: 1_100, archived: 3_000),
                share: nil,
                summary: nil
            ),
        ]
        state.currentSessionID = "root-session"
        state.expandedSessionIDs = ["root-session", "archived-session"]
        return state
    }

    private static func deepLinkFixtureSession(id: String, title: String, directory: String) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "deep-link-project",
            directory: directory,
            parentID: nil,
            title: title,
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
    }

    private static func applyDeepLinkFixture(to state: AppState) {
        let source = deepLinkFixtureSession(
            id: "ses_deep_link_source",
            title: "Deep Link Source",
            directory: "/tmp/deep-link-source"
        )
        state.isConnected = true
        state.sessions = [source]
        state.currentSessionID = source.id
        state.selectedTab = RootTab.chat.rawValue

        let assistant = Message(
            id: "msg_deep_link_assistant",
            sessionID: source.id,
            role: "assistant",
            parentID: nil,
            providerID: "fixture",
            modelID: "fixture",
            model: nil,
            error: nil,
            time: .init(created: 1, completed: 2),
            finish: "stop",
            tokens: nil,
            cost: nil
        )
        let text = decodePart([
            "id": "part_deep_link_text",
            "messageID": assistant.id,
            "sessionID": source.id,
            "type": "text",
            "text": "[Open target session](opencode://session/ses_deep_link_target)",
        ])
        state.messages = [MessageWithParts(info: assistant, parts: [text])]
    }

    private static func applyCarHistoryFixture(to state: AppState) {
        let sessionID = "car-history-session"
        state.isConnected = true
        state.selectedTab = RootTab.chat.rawValue
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp/car-history",
                parentID: nil,
                title: "Car Mode",
                version: "1",
                time: .init(created: 1, updated: 3, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        let user = Message(
            id: "car-user",
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
        let assistant = Message(
            id: "car-assistant",
            sessionID: sessionID,
            role: "assistant",
            parentID: user.id,
            providerID: "openai",
            modelID: "gpt-5.6-sol-fast",
            model: nil,
            error: nil,
            time: .init(created: 2, completed: 3),
            finish: "tool-calls",
            tokens: nil,
            cost: nil,
            structured: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "The garage door is closed.",
                confirmation: nil,
                clientActions: []
            )
        )
        let userPart = decodePart([
            "id": "car-user-text",
            "messageID": user.id,
            "sessionID": sessionID,
            "type": "text",
            "text": "Is the garage door closed?",
        ])
        state.messages = [
            MessageWithParts(info: user, parts: [userPart]),
            MessageWithParts(info: assistant, parts: []),
        ]
    }

    private static func applyQuotaFixture(to state: AppState) {
        let sessionID = "quota-fixture-session"
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp/quota-fixture",
                parentID: nil,
                title: "Quota UX Review",
                version: "1",
                time: .init(created: 1_000, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        state.draftInputsBySessionID[sessionID] = ""
        state.selectedModelIndex = 6
        state.aiUsageDashboardURL = "http://usage-dashboard.local:7995"
        state.aiUsageQuotaState = .ready(.init(
            generatedAt: "2026-07-12T09:40:00",
            fetchedAt: Date(),
            quotas: [
                AIUsageQuota(provider: "codex", label: "5h", usedPercentage: 29, remainingPercentage: 71, nextResetTimeMs: 1_783_842_841_000, nextResetISO: nil, usage: nil, remaining: nil),
                AIUsageQuota(provider: "codex", label: "7d", usedPercentage: 62, remainingPercentage: 38, nextResetTimeMs: 1_783_950_000_000, nextResetISO: nil, usage: nil, remaining: nil),
                AIUsageQuota(provider: "claude", label: "5h", usedPercentage: 84, remainingPercentage: 16, nextResetTimeMs: 1_783_850_000_000, nextResetISO: nil, usage: nil, remaining: nil),
                AIUsageQuota(provider: "glm", label: "5h", usedPercentage: 8, remainingPercentage: 92, nextResetTimeMs: 1_783_860_000_000, nextResetISO: nil, usage: nil, remaining: nil),
            ]
        ))
    }

    private static func applyHostProfilesFixture(to state: AppState) {
        let local = HostProfile(
            name: "Local OpenCode",
            transport: .direct,
            serverURL: "127.0.0.1:4096",
            basicAuth: nil,
            ssh: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        )
        let ssh = HostProfile(
            name: "SSH Lab",
            transport: .sshTunnel,
            serverURL: APIClient.defaultServer,
            basicAuth: nil,
            ssh: SSHTunnelConfig(isEnabled: true, host: "gateway.example.invalid", port: 8006, username: "opencode", remotePort: 19001),
            lastUsedAt: Date(timeIntervalSince1970: 2_000)
        )
        state.hostProfiles = [local, ssh]
        state.currentHostProfileID = local.id
        state.applyCurrentHostProfileToRuntime(persistLegacy: false)
        state.selectedTab = RootTab.settings.rawValue
    }

    /// iPad / Vision Pro：左右分栏，无 Tab Bar
    private var useSplitLayout: Bool { sizeClass == .regular }

    private var showsCarMode: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone && carModeEnabled
        #else
        false
        #endif
    }

    private var carModeEnabledBinding: Binding<Bool> {
        Binding(
            get: { carModeEnabled },
            set: { isEnabled in
                carModeEnabled = isEnabled
                state.isCarModeEnabled = isEnabled
            }
        )
    }

    private var themeColorScheme: ColorScheme? {
        switch state.themePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var filePreviewSheetItem: Binding<FilePathWrapper?> {
        Binding(
            get: {
                // 仅在 iPhone / compact 时使用 sheet 预览；iPad 在中间栏内联预览。
                guard !useSplitLayout else { return nil }
                return state.fileToOpenInFilesTab.map {
                    FilePathWrapper(path: $0, workspaceDirectory: state.fileToOpenInFilesTabWorkspaceDirectory)
                }
            },
            set: { newValue, _ in
                Task { @MainActor in
                    await Task.yield()
                    state.fileToOpenInFilesTab = newValue?.path
                    state.fileToOpenInFilesTabWorkspaceDirectory = newValue?.workspaceDirectory
                    if newValue == nil, !useSplitLayout {
                        selectedTab = RootTab.chat.rawValue
                        state.selectedTab = RootTab.chat.rawValue
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var rootLayout: some View {
        if useSplitLayout {
            tabletWorkspaceLayout
        } else {
            tabLayout
        }
    }

    /// Injects a deterministic assistant turn so the UI test renders the new tool
    /// cards (file-op grid + merged "N tool calls" row) without a live server.
    /// Only active under the UITEST_TOOL_CARDS_FIXTURE launch argument.
    private static func applyToolCardsFixture(to state: AppState) {
        let sessionID = "toolcards-session"
        let userMessageID = "u-toolcards"
        let assistantMessageID = "a-toolcards"

        state.isConnected = true
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Tool Cards Session",
                version: "1",
                time: .init(created: 0, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        state.expandedSessionIDs = [sessionID]

        // User message: a single text part.
        let userInfo = Message(
            id: userMessageID,
            sessionID: sessionID,
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
        let userTextPart = decodePart([
            "id": "up-text",
            "messageID": userMessageID,
            "sessionID": sessionID,
            "type": "text",
            "text": "Refactor the API client and run the tests.",
        ])

        // Assistant message: resolvedModel via top-level providerID/modelID so the
        // small "providerID/modelID" footer shows.
        let assistantInfo = Message(
            id: assistantMessageID,
            sessionID: sessionID,
            role: "assistant",
            parentID: userMessageID,
            providerID: "openai",
            modelID: "gpt-5.6-sol",
            model: nil,
            error: nil,
            time: .init(created: 1_100, completed: 1_200),
            finish: "stop",
            tokens: nil,
            cost: nil
        )

        var assistantParts: [Part] = []

        // Leading text so the assistant turn reads naturally.
        assistantParts.append(decodePart([
            "id": "ap-text",
            "messageID": assistantMessageID,
            "sessionID": sessionID,
            "type": "text",
            "text": "Here are the changes I made.",
        ]))

        // File-operation parts -> render as FileCardView in the 2-column grid.
        let fileTools: [(id: String, tool: String, path: String)] = [
            ("ap-read", "read_file", "src/api/client.ts"),
            ("ap-edit", "edit_file", "src/api/types.ts"),
            ("ap-write", "write_file", "README.md"),
        ]
        for f in fileTools {
            assistantParts.append(decodePart([
                "id": f.id,
                "messageID": assistantMessageID,
                "sessionID": sessionID,
                "type": "tool",
                "tool": f.tool,
                "callID": "call-\(f.id)",
                "metadata": ["path": f.path],
                "state": [
                    "status": "completed",
                    "input": ["path": f.path],
                    "output": "ok",
                ],
            ]))
        }

        // A patch part with files -> a fourth file card.
        assistantParts.append(decodePart([
            "id": "ap-patch",
            "messageID": assistantMessageID,
            "sessionID": sessionID,
            "type": "patch",
            "files": [
                ["path": "src/api/index.ts", "additions": 12, "deletions": 3, "status": "modified"],
            ],
        ]))

        // Non-file tools -> collapse into the merged "3 tool calls" row.
        let otherTools: [(id: String, tool: String, command: String, output: String)] = [
            ("ap-bash", "bash", "npm test", "All tests passed"),
            ("ap-grep", "grep", "TODO", "3 matches"),
            ("ap-list", "list", "src/api", "client.ts\ntypes.ts\nindex.ts"),
        ]
        for t in otherTools {
            assistantParts.append(decodePart([
                "id": t.id,
                "messageID": assistantMessageID,
                "sessionID": sessionID,
                "type": "tool",
                "tool": t.tool,
                "callID": "call-\(t.id)",
                "state": [
                    "status": "completed",
                    "title": t.command,
                    "input": ["command": t.command],
                    "output": t.output,
                ],
            ]))
        }

        state.messages = [
            MessageWithParts(info: userInfo, parts: [userTextPart]),
            MessageWithParts(info: assistantInfo, parts: assistantParts),
        ]
    }

    /// Injects a deterministic busy session for F3 composer screenshots.
    /// The voice-side states are controlled by ChatTabView launch arguments.
    private static func applyF3ComposerFixture(to state: AppState) {
        let sessionID = "f3-composer-session"
        state.isConnected = true
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp/opencode-ios-f3-fixture",
                parentID: nil,
                title: "F3 Voice Steer",
                version: "1",
                time: .init(created: 1_000, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        state.sessionStatuses[sessionID] = SessionStatus(type: "busy", attempt: nil, message: "Running implementation", next: nil)
    }

    /// Decode a Part from a JSON-object dictionary, mirroring how the server feeds
    /// parts through Codable (so metadata/state/path classification flows identically).
    private static func decodePart(_ obj: [String: Any]) -> Part {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return try! JSONDecoder().decode(Part.self, from: data)
    }

    private func restoreConnectionFlow() async {
        if Self.hasUITestSessionTreeFixture || Self.hasUITestToolCardsFixture || Self.hasUITestF3ComposerFixture || Self.hasUITestWebPreviewFixture || Self.hasUITestWebPreviewModeFixture || Self.hasUITestQuotaFixture || Self.hasUITestCarModeFixture || Self.hasUITestCarHistoryFixture || Self.hasUITestCarDisabledFixture || Self.hasUITestClientCapabilityFixture || Self.hasUITestDeepLinkFixture {
            return
        }

        #if !os(visionOS)
        if state.sshTunnelManager.config.isEnabled,
           state.sshTunnelManager.status != .connected {
            await state.sshTunnelManager.connect()
        }
        #endif

        await state.refresh()

        // iOS suspend/restore can leave SSH state stale (status still connected but
        // actual tunnel already dropped). If refresh still cannot reach server through
        // localhost after an enabled SSH config, force a tunnel re-establish once.
        #if !os(visionOS)
        if state.sshTunnelManager.config.isEnabled, !state.isConnected {
            state.sshTunnelManager.disconnect()
            await state.sshTunnelManager.connect()
            await state.refresh()
        }
        #endif

        if state.isConnected {
            state.connectSSE()
            await state.processPendingDeepLinkIfPossible()
            await state.retryClientCapabilityOutbox()
        } else {
            state.disconnectSSE()
        }
    }

    private static var webPreviewFixtureColorScheme: ColorScheme {
        ProcessInfo.processInfo.environment["UITEST_FORCE_THEME"] == "dark" ? .dark : .light
    }

    @ViewBuilder
    private var webPreviewFixtureView: some View {
        MarkdownWebPreviewView(
            input: MarkdownWebPreviewInput(
                markdown: Self.loadFixtureMarkdown(Self.webPreviewFixtureName),
                colorScheme: Self.webPreviewFixtureColorScheme
            )
        )
        .accessibilityIdentifier("web-preview-fixture-root")
        .ignoresSafeArea()
    }

    private static var hasUITestWebPreviewModeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_WEB_PREVIEW_MODE_FIXTURE")
    }

    var body: some View {
        #if DEBUG
        if Self.hasUITestWebPreviewModeFixture {
            NavigationStack {
                WebPreviewModeFixtureHost(
                    markdown: Self.loadFixtureMarkdown(Self.webPreviewFixtureName)
                )
            }
            .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else if Self.hasUITestWebPreviewFixture {
            webPreviewFixtureView
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else {
            mainBody
        }
        #else
        if Self.hasUITestWebPreviewFixture {
            webPreviewFixtureView
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else {
            mainBody
        }
        #endif
    }

    private var mainBody: some View {
        rootLayout
        .task {
            state.cleanupClientCapabilityCallbacks()
            if Self.hasUITestDeepLinkFixture,
               let rawURL = ProcessInfo.processInfo.environment["UITEST_INITIAL_DEEP_LINK"],
               let url = URL(string: rawURL) {
                state.receiveDeepLink(url)
            }
            await restoreConnectionFlow()
            await state.processPendingDeepLinkIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await restoreConnectionFlow()
                state.cleanupClientCapabilityCallbacks()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            state.invalidateDeepLinkRoute(keepPending: true)
            state.isConnected = false
            state.disconnectSSE()
            #if !os(visionOS)
            if state.sshTunnelManager.config.isEnabled {
                state.sshTunnelManager.disconnect()
            }
            #endif
        }
        .onOpenURL { url in
            state.receiveDeepLink(url)
        }
        .overlay {
            if case .resolving = state.deepLinkRouteState {
                ProgressView(L10n.t(.deepLinkOpening))
                    .padding(.horizontal, DesignSpacing.lg)
                    .padding(.vertical, DesignSpacing.md)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignCorners.medium))
                    .accessibilityIdentifier("deep-link-opening")
            }
        }
        .alert(
            L10n.t(.appError),
            isPresented: Binding(
                get: { state.deepLinkError != nil },
                set: { if !$0 { state.deepLinkError = nil } }
            )
        ) {
            Button(L10n.t(.commonOk)) { state.deepLinkError = nil }
        } message: {
            if let error = state.deepLinkError {
                Text(error)
                    .accessibilityIdentifier("deep-link-error")
            }
        }
        .sheet(item: $state.pendingClientCapabilityRequest) { request in
            ClientCapabilityPermissionView(state: state, request: request)
        }
        .alert(
            L10n.t(.appError),
            isPresented: Binding(
                get: { state.clientCapabilityError != nil },
                set: { if !$0 { state.clientCapabilityError = nil } }
            )
        ) {
            Button(L10n.t(.commonOk)) { state.clientCapabilityError = nil }
        } message: {
            Text(state.clientCapabilityError ?? "")
                .accessibilityIdentifier("client-capability-error")
        }
        .preferredColorScheme(themeColorScheme)
        .environment(\.locale, L10n.currentLocale)
        .onAppear {
            selectedTab = state.selectedTab
        }
        .onChange(of: sizeClass) { _, newValue in
            // iPhone → iPad 或 split layout 切换时，将 sheet 预览迁移到中间栏预览。
            if newValue == .regular, let p = state.fileToOpenInFilesTab {
                Task { @MainActor in
                    await Task.yield()
                    state.previewFilePath = p
                    state.previewFileWorkspaceDirectory = state.fileToOpenInFilesTabWorkspaceDirectory
                    state.fileToOpenInFilesTab = nil
                    state.fileToOpenInFilesTabWorkspaceDirectory = nil
                }
            }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            Task { @MainActor in
                await Task.yield()
                state.selectedTab = newTab
            }
            if oldTab == RootTab.settings.rawValue && newTab != RootTab.settings.rawValue {
                Task { await state.refresh() }
            }
        }
        .onChange(of: state.selectedTab) { _, newTab in
            guard selectedTab != newTab else { return }
            Task { @MainActor in
                await Task.yield()
                selectedTab = newTab
            }
        }
        .onChange(of: carModeEnabled) { _, isEnabled in
            guard !isEnabled, selectedTab == RootTab.car.rawValue else { return }
            selectedTab = RootTab.chat.rawValue
            state.selectedTab = RootTab.chat.rawValue
        }
        .sheet(item: filePreviewSheetItem) { wrapper in
            NavigationStack {
                FileContentView(state: state, filePath: wrapper.path, workspaceDirectory: wrapper.workspaceDirectory)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                Task { @MainActor in
                                    state.fileToOpenInFilesTab = nil
                                    state.fileToOpenInFilesTabWorkspaceDirectory = nil
                                    if !useSplitLayout {
                                        selectedTab = RootTab.chat.rawValue
                                        state.selectedTab = RootTab.chat.rawValue
                                    }
                                }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel(L10n.t(.appClose))
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettingsSheet, onDismiss: {
            Task { await state.refresh() }
        }) {
            NavigationStack {
                SettingsTabView(state: state, isCarModeEnabled: carModeEnabledBinding)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(L10n.t(.appClose)) { showSettingsSheet = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var tabLayout: some View {
        if showsCarMode {
            carEnabledTabLayout
        } else {
            standardTabLayout
        }
    }

    private var standardTabLayout: some View {
        TabView(selection: $selectedTab) {
            ChatTabView(state: state)
                .tabItem { Label(L10n.t(.appChat), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(RootTab.chat.rawValue)

            FilesTabView(state: state)
                .tabItem { Label(L10n.t(.navFiles), systemImage: "folder") }
                .tag(RootTab.files.rawValue)

            SettingsTabView(state: state, isCarModeEnabled: carModeEnabledBinding)
                .tabItem { Label(L10n.t(.navSettings), systemImage: "gear") }
                .tag(RootTab.settings.rawValue)
        }
    }

    private var carEnabledTabLayout: some View {
        TabView(selection: $selectedTab) {
            ChatTabView(state: state)
                .tabItem { Label(L10n.t(.appChat), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(RootTab.chat.rawValue)

            FilesTabView(state: state)
                .tabItem { Label(L10n.t(.navFiles), systemImage: "folder") }
                .tag(RootTab.files.rawValue)

            CarModeView(state: state)
                .tabItem { Label(L10n.t(.carTab), systemImage: "car.fill") }
                .tag(RootTab.car.rawValue)

            SettingsTabView(state: state, isCarModeEnabled: carModeEnabledBinding)
                .tabItem { Label(L10n.t(.navSettings), systemImage: "gear") }
                .tag(RootTab.settings.rawValue)
        }
    }

    /// iPad / Vision Pro：Android-aligned three-pane layout.
    @State private var sessionsCollapsed: Bool = false

    private var tabletWorkspaceLayout: some View {
        GeometryReader { geo in
            let total = geo.size.width
            // 折叠时 Sessions 宽度收为 0，Files / Chat 平分总宽度。
            let sessionsWidth: CGFloat = sessionsCollapsed ? 0 : total * 0.25
            let remaining = total - sessionsWidth
            let paneWidth = sessionsCollapsed ? remaining / 2 : total * 0.375

            HStack(spacing: 0) {
                if !sessionsCollapsed {
                    TabletSessionsColumn(
                        state: state,
                        showSettings: $showTabletSettings,
                        onCollapse: { withAnimation(DesignAnimation.spring) { sessionsCollapsed = true } }
                    )
                    .frame(width: sessionsWidth)
                    .transition(.move(edge: .leading))

                    Divider()
                }

                TabletFilesColumn(
                    state: state,
                    sessionsCollapsed: sessionsCollapsed,
                    onExpandSessions: { withAnimation(DesignAnimation.spring) { sessionsCollapsed = false } }
                )
                .frame(width: paneWidth)

                Divider()

                ChatTabView(
                    state: state,
                    showSettingsInToolbar: false,
                    showSessionListInToolbar: false,
                    showCreateSessionInToolbar: false
                )
                .frame(width: paneWidth)
            }
            // 折叠时支持从屏幕左边缘右滑展开 Sessions
            .overlay(alignment: .leading) {
                if sessionsCollapsed {
                    Color.clear
                        .frame(width: 16)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if value.translation.width > 40 && abs(value.translation.height) < 80 {
                                        withAnimation(DesignAnimation.spring) {
                                            sessionsCollapsed = false
                                        }
                                    }
                                }
                        )
                }
            }
        }
        .accessibilityIdentifier("ipad-workspace-layout")
    }
}

private struct FilePathWrapper: Identifiable {
    let path: String
    let workspaceDirectory: String?
    var id: String { "\(workspaceDirectory ?? ""):\(path)" }
}

private struct TabletFilesColumn: View {
    @Bindable var state: AppState
    var sessionsCollapsed: Bool = false
    var onExpandSessions: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let path = state.previewFilePath, !path.isEmpty {
                    FileContentView(state: state, filePath: path, workspaceDirectory: state.previewFileWorkspaceDirectory)
                } else {
                    FileTreeView(state: state, forceSplitPreview: true)
                        .searchable(text: $state.fileSearchQuery, prompt: L10n.t(.appSearchFiles))
                        .onSubmit(of: .search) {
                            Task { await state.searchFiles(query: state.fileSearchQuery) }
                        }
                        .onChange(of: state.fileSearchQuery) { _, newValue in
                            if newValue.isEmpty {
                                state.fileSearchResults = []
                            } else {
                                Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    await state.searchFiles(query: newValue)
                                }
                            }
                        }
                        .navigationTitle(L10n.t(.navFiles))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                // 折叠 Sessions 时, Files 工具栏左上显示"展开 Sessions"按钮
                if sessionsCollapsed, let onExpandSessions {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onExpandSessions) {
                            Image(systemName: "sidebar.left")
                        }
                        .help(L10n.t(.sidebarShowSessions))
                        .accessibilityIdentifier("ipad-show-sessions-button")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let path = state.previewFilePath, !path.isEmpty {
                        Button {
                            state.previewFilePath = nil
                            state.previewFileWorkspaceDirectory = nil
                            state.fileToOpenInFilesTab = nil
                            state.fileToOpenInFilesTabWorkspaceDirectory = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .help(L10n.t(.appClose))
                    }
                }
            }
        }
    }
}

private struct TabletSessionsColumn: View {
    @Bindable var state: AppState
    @Binding var showSettings: Bool
    var onCollapse: (() -> Void)? = nil
    @State private var activeExpanded = true
    @State private var archivedExpanded = false
    @State private var mutatingSessionID: String?
    @State private var actionError: String?
    @State private var showCreateDisabledAlert = false

    private var activeNodes: [SessionNode] {
        state.sessionTree(archived: false)
    }

    private var archivedNodes: [SessionNode] {
        state.sessionTree(archived: true)
    }

    var body: some View {
        NavigationStack {
            Group {
                if showSettings {
                    SettingsTabView(state: state, isCarModeEnabled: .constant(false))
                } else if activeNodes.isEmpty && archivedNodes.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.sessionsEmptyTitle),
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text(L10n.t(.sessionsEmptyDescription))
                    )
                } else {
                    List {
                        SessionSectionHeader(title: L10n.t(.sessionsActive), isExpanded: activeExpanded) {
                            activeExpanded.toggle()
                        }

                        if activeExpanded {
                            sessionNodes(activeNodes, archived: false, attentionCounts: state.sessionAttentionCounts)
                        }

                        SessionSectionHeader(title: L10n.t(.sessionsArchived), isExpanded: archivedExpanded) {
                            archivedExpanded.toggle()
                        }

                        if archivedExpanded {
                            sessionNodes(archivedNodes, archived: true, attentionCounts: state.sessionAttentionCounts)
                        }

                        if state.isLoadingMoreSessions {
                            LoadMoreSessionsRow(isLoading: true) {}
                        } else if state.canLoadMoreSessions {
                            LoadMoreSessionsRow(isLoading: false) {
                                Task { await state.loadMoreSessions() }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .refreshable {
                        await state.refreshSessions()
                    }
                }
            }
            .navigationTitle(showSettings ? L10n.t(.navSettings) : L10n.t(.sessionsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sessions 列左上"折叠"按钮 (除 settings sheet 外都显示)
                if !showSettings, let onCollapse {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onCollapse) {
                            Image(systemName: "sidebar.left")
                        }
                        .help(L10n.t(.sidebarHideSessions))
                        .accessibilityIdentifier("ipad-hide-sessions-button")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if showSettings {
                        Button(L10n.t(.appDone)) {
                            showSettings = false
                            Task { await state.refresh() }
                        }
                    } else {
                        HStack(spacing: 8) {
                            // 用 plus 图标替代 "New" 文字, 给 iPad 上 Sessions 标题留空间
                            // (Session 也是窄列, 文字按钮会把标题挤成省略号)
                            Button {
                                Task { await state.createSession() }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(!state.canCreateSession)
                            .foregroundColor(state.canCreateSession ? DesignColors.Brand.primary : DesignColors.Neutral.textTertiary)
                            .help(L10n.t(.sessionsNew))
                            .accessibilityLabel(L10n.t(.sessionsNew))

                            if !state.canCreateSession {
                                Button {
                                    showCreateDisabledAlert = true
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .foregroundColor(.secondary)
                            }

                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gear")
                            }
                            .accessibilityIdentifier("ipad-settings-button")
                        }
                    }
                }
            }
        }
        .alert(
            L10n.t(.sessionsActionFailedTitle),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(L10n.t(.commonOk)) {
                actionError = nil
            }
        } message: {
            if let actionError {
                Text(actionError)
            }
        }
        .alert(L10n.t(.chatCreateDisabledHint), isPresented: $showCreateDisabledAlert) {
            Button(L10n.t(.commonOk)) {}
        }
    }

    private func sessionNodes(
        _ nodes: [SessionNode],
        archived: Bool,
        depth: Int = 0,
        attentionCounts: [String: Int]
    ) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                let session = node.session
                let status = state.sessionStatuses[session.id]

                SessionRowView(
                    session: session,
                    status: status,
                    attentionCount: attentionCounts[session.id, default: 0],
                    isSelected: state.currentSessionID == session.id,
                    isMutating: mutatingSessionID == session.id,
                    isArchived: archived,
                    depth: depth,
                    hasChildren: !node.children.isEmpty,
                    isCollapsed: !state.expandedSessionIDs.contains(session.id),
                    onSelect: { state.selectSession(session) },
                    onToggleCollapse: { state.toggleSessionExpanded(session.id) }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        mutateSession(session) {
                            if archived {
                                try await state.restoreSession(sessionID: session.id)
                            } else {
                                try await state.archiveSession(sessionID: session.id)
                            }
                        }
                    } label: {
                        Label(archived ? L10n.t(.sessionsRestore) : L10n.t(.sessionsArchive), systemImage: archived ? "arrow.uturn.backward" : "archivebox")
                    }
                    .tint(DesignColors.Brand.primary.opacity(0.7))
                    .disabled(mutatingSessionID != nil)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        mutateSession(session) {
                            try await state.deleteSession(sessionID: session.id)
                        }
                    } label: {
                        Label(L10n.t(.sessionsDelete), systemImage: "trash")
                    }
                    .tint(.red)
                    .disabled(mutatingSessionID != nil)
                }

                if state.expandedSessionIDs.contains(session.id) {
                    sessionNodes(
                        node.children,
                        archived: archived,
                        depth: depth + 1,
                        attentionCounts: attentionCounts
                    )
                }
            }
        )
    }

    private func mutateSession(_ session: Session, action: @escaping () async throws -> Void) {
        guard mutatingSessionID == nil else { return }
        mutatingSessionID = session.id
        Task {
            do {
                try await action()
            } catch {
                actionError = error.localizedDescription
            }
            mutatingSessionID = nil
        }
    }
}

#Preview {
    ContentView()
}
