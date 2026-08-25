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

enum SettingsFocus: Equatable {
    case modelShortlist
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

    private static func makeInitialState() -> AppState {
        UITestFixtures.makeInitialState()
    }

    private var themeColorScheme: ColorScheme? {
        switch state.themePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

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

    private var filePreviewSheetItem: Binding<FilePathWrapper?> {
        Binding(
            get: {
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

    private func restoreConnectionFlow() async {
        if UITestFixtures.shouldSkipConnectionRestore {
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
                markdown: UITestFixtures.loadFixtureMarkdown(UITestFixtures.webPreviewFixtureName),
                colorScheme: Self.webPreviewFixtureColorScheme
            )
        )
        .accessibilityIdentifier("web-preview-fixture-root")
        .ignoresSafeArea()
    }

    var body: some View {
        #if DEBUG
        if UITestFixtures.hasUITestWebPreviewModeFixture {
            NavigationStack {
                WebPreviewModeFixtureHost(
                    markdown: UITestFixtures.loadFixtureMarkdown(UITestFixtures.webPreviewFixtureName)
                )
            }
            .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else if UITestFixtures.hasUITestWebPreviewFixture {
            webPreviewFixtureView
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else {
            mainBody
        }
        #else
        if UITestFixtures.hasUITestWebPreviewFixture {
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
            if UITestFixtures.hasUITestDeepLinkFixture,
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
        .onChange(of: state.settingsFocus) { _, focus in
            guard focus != nil else { return }
            if useSplitLayout {
                showTabletSettings = true
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
