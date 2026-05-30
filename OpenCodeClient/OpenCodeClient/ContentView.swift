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
    // iPad/visionOS: keep all three columns visible by default so the layout
    // reads as the intended sidebar · preview · chat triptych instead of
    // collapsing to a single detail pane.
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all

    init() {
        _state = State(initialValue: Self.makeInitialState())
    }

    private static var hasUITestSessionTreeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_SESSION_TREE_FIXTURE")
    }

    private static var hasUITestToolCardsFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_TOOL_CARDS_FIXTURE")
    }

    private static func makeInitialState() -> AppState {
        let state = AppState()

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
        ]
        state.currentSessionID = "root-session"
        state.expandedSessionIDs = ["root-session"]
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

    /// Decode a Part from a JSON-object dictionary, mirroring how the server feeds
    /// parts through Codable (so metadata/state/path classification flows identically).
    private static func decodePart(_ obj: [String: Any]) -> Part {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return try! JSONDecoder().decode(Part.self, from: data)
    }

    private func restoreConnectionFlow() async {
        if Self.hasUITestSessionTreeFixture || Self.hasUITestToolCardsFixture {
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

    var body: some View {
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
                            Button(L10n.t(.appClose)) {
                                state.fileToOpenInFilesTab = nil
                                if !useSplitLayout { state.selectedTab = 0 }
                            }
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

    /// iPad / Vision Pro：左右分栏，左 Files 右 Chat，Settings 为 toolbar 按钮
    private var splitLayout: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let sidebarIdeal = total * LayoutConstants.SplitView.sidebarWidthFraction
            let paneIdeal = total * LayoutConstants.SplitView.previewWidthFraction

            let sidebarMin = min(sidebarIdeal, total * LayoutConstants.SplitView.sidebarMinFraction)
            let sidebarMax = max(sidebarIdeal, total * LayoutConstants.SplitView.sidebarMaxFraction)

            let paneMin = min(paneIdeal, total * LayoutConstants.SplitView.paneMinFraction)
            let paneMax = max(paneIdeal, total * LayoutConstants.SplitView.paneMaxFraction)

            NavigationSplitView(columnVisibility: $splitColumnVisibility) {
                SplitSidebarView(state: state)
                    .navigationSplitViewColumnWidth(min: sidebarMin, ideal: sidebarIdeal, max: sidebarMax)
            } content: {
                PreviewColumnView(state: state)
                    .navigationSplitViewColumnWidth(min: paneMin, ideal: paneIdeal, max: paneMax)
            } detail: {
                ChatTabView(state: state, showSettingsInToolbar: true, onSettingsTap: { showSettingsSheet = true })
                    .navigationSplitViewColumnWidth(min: paneMin, ideal: paneIdeal, max: paneMax)
            }
            .navigationSplitViewStyle(.balanced)
        }
    }
}

private struct FilePathWrapper: Identifiable {
    let path: String
    var id: String { path }
}

private struct PreviewColumnView: View {
    @Bindable var state: AppState
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let path = state.previewFilePath, !path.isEmpty {
                    FileContentView(state: state, filePath: path)
                        .id("\(path)|\(reloadToken.uuidString)")
                } else {
                    ContentUnavailableView(
                        L10n.t(.contentPreviewUnavailableTitle),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.t(.contentPreviewUnavailableDescription))
                    )
                    .navigationTitle(L10n.t(.navPreview))
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        reloadToken = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled((state.previewFilePath ?? "").isEmpty)
                    .help(L10n.t(.contentRefreshHelp))
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
