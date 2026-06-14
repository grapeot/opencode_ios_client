//
//  ContentView.swift
//  OpenCodeClient
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @State private var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettingsSheet = false
    @State private var showTabletSettings = false

    init() {
        _state = State(initialValue: Self.makeInitialState())
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
        let state = AppState()

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

    /// iPad / Vision Pro：左右分栏，无 Tab Bar
    private var useSplitLayout: Bool { sizeClass == .regular }

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
                return state.fileToOpenInFilesTab.map { FilePathWrapper(path: $0) }
            },
            set: { newValue, _ in
                state.fileToOpenInFilesTab = newValue?.path
                if newValue == nil, !useSplitLayout {
                    state.selectedTab = 0
                }
            }
        )
    }

    @ViewBuilder
    private var rootLayout: some View {
        if useSplitLayout {
            splitLayout
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
            modelID: "gpt-5.5",
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
        if Self.hasUITestSessionTreeFixture || Self.hasUITestToolCardsFixture || Self.hasUITestF3ComposerFixture || Self.hasUITestWebPreviewFixture {
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

    var body: some View {
        if Self.hasUITestWebPreviewFixture {
            webPreviewFixtureView
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else {
            mainBody
        }
    }

    private var mainBody: some View {
        rootLayout
        .task {
            await restoreConnectionFlow()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await restoreConnectionFlow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            state.disconnectSSE()
            #if !os(visionOS)
            if state.sshTunnelManager.config.isEnabled {
                state.sshTunnelManager.disconnect()
            }
            #endif
        }
        .preferredColorScheme(themeColorScheme)
        .onChange(of: sizeClass) { _, newValue in
            // iPhone → iPad 或 split layout 切换时，将 sheet 预览迁移到中间栏预览。
            if newValue == .regular, let p = state.fileToOpenInFilesTab {
                state.previewFilePath = p
                state.fileToOpenInFilesTab = nil
            }
        }
        .onChange(of: state.selectedTab) { oldTab, newTab in
            if oldTab == 2 && newTab != 2 {
                Task { await state.refresh() }
            }
        }
        .sheet(item: filePreviewSheetItem) { wrapper in
            NavigationStack {
                FileContentView(state: state, filePath: wrapper.path)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                state.fileToOpenInFilesTab = nil
                                if !useSplitLayout { state.selectedTab = 0 }
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
                SettingsTabView(state: state)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(L10n.t(.appClose)) { showSettingsSheet = false }
                        }
                    }
            }
        }
    }

    /// iPhone：Tab Bar 三 Tab
    private var tabLayout: some View {
        TabView(selection: Binding(
            get: { state.selectedTab },
            set: { state.selectedTab = $0 }
        )) {
            ChatTabView(state: state)
                .tabItem { Label(L10n.t(.appChat), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(0)

            FilesTabView(state: state)
                .tabItem { Label(L10n.t(.navFiles), systemImage: "folder") }
                .tag(1)

            SettingsTabView(state: state)
                .tabItem { Label(L10n.t(.navSettings), systemImage: "gear") }
                .tag(2)
        }
    }

    /// iPad / Vision Pro：Android-aligned three-pane layout.
    private var splitLayout: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let sessionsWidth = total * 0.25
            let paneWidth = total * 0.375

            HStack(spacing: 0) {
                TabletSessionsColumn(
                    state: state,
                    showSettings: $showTabletSettings
                )
                .frame(width: sessionsWidth)

                Divider()

                TabletFilesColumn(state: state)
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
        }
    }
}

private struct FilePathWrapper: Identifiable {
    let path: String
    var id: String { path }
}

private struct TabletFilesColumn: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            Group {
                if let path = state.previewFilePath, !path.isEmpty {
                    FileContentView(state: state, filePath: path)
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
                ToolbarItem(placement: .primaryAction) {
                    if let path = state.previewFilePath, !path.isEmpty {
                        Button {
                            state.previewFilePath = nil
                            state.fileToOpenInFilesTab = nil
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
                    SettingsTabView(state: state)
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
                            sessionNodes(activeNodes, archived: false)
                        }

                        SessionSectionHeader(title: L10n.t(.sessionsArchived), isExpanded: archivedExpanded) {
                            archivedExpanded.toggle()
                        }

                        if archivedExpanded {
                            sessionNodes(archivedNodes, archived: true)
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
                ToolbarItem(placement: .primaryAction) {
                    if showSettings {
                        Button(L10n.t(.appDone)) {
                            showSettings = false
                            Task { await state.refresh() }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Button {
                                Task { await state.createSession() }
                            } label: {
                                Text(L10n.t(.sessionsNew))
                            }
                            .disabled(!state.canCreateSession)
                            .foregroundColor(state.canCreateSession ? DesignColors.Brand.primary : DesignColors.Neutral.textTertiary)

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

    private func sessionNodes(_ nodes: [SessionNode], archived: Bool, depth: Int = 0) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                let session = node.session
                let status = state.sessionStatuses[session.id]

                SessionRowView(
                    session: session,
                    status: status,
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
                    sessionNodes(node.children, archived: archived, depth: depth + 1)
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
