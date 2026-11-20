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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettingsSheet = false
    @State private var showTabletSettings = false
    @State private var selectedTab = 0
    @State private var carModeEnabled: Bool
    @State private var sessionsCollapsed: Bool = false

    init() {
        let initialState = Self.makeInitialState()
        _state = State(initialValue: initialState)
        _carModeEnabled = State(initialValue: initialState.isCarModeEnabled)
    }

    private static func makeInitialState() -> AppState {
        let state = UITestFixtures.makeInitialState()
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["UITEST_LAYOUT_PREFERENCE"], !raw.isEmpty {
            state.layoutPreference = LayoutPreference.resolved(from: raw)
        }
        #endif
        return state
    }

    private var themeColorScheme: ColorScheme? {
        switch state.themePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var forcedWidthClass: UserInterfaceSizeClass? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["UITEST_FORCE_WIDTH_CLASS"] {
        case "compact": return .compact
        case "regular": return .regular
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private var resolvedSizeClass: UserInterfaceSizeClass? {
        forcedWidthClass ?? sizeClass
    }

    private var effectiveLayout: EffectiveLayout {
        EffectiveLayoutResolver.resolve(
            preference: state.layoutPreference,
            width: WindowWidthClass(horizontalSizeClass: resolvedSizeClass)
        )
    }

    private var useSplitLayout: Bool { effectiveLayout == .regular }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { useSplitLayout ? RootTab.chat.rawValue : selectedTab },
            set: { newValue in
                guard !useSplitLayout else { return }
                selectedTab = newValue
            }
        )
    }

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
                guard newValue == nil else { return }
                let dismissedSequence = state.pendingEventSequence
                Task { @MainActor in
                    await Task.yield()
                    guard state.pendingEventSequence == dismissedSequence else { return }
                    state.fileToOpenInFilesTab = nil
                    state.fileToOpenInFilesTabWorkspaceDirectory = nil
                    state.pendingFileOpenOwner = nil
                    state.pendingEventSequence = 0
                    if !useSplitLayout {
                        selectedTab = RootTab.chat.rawValue
                        state.selectedTab = RootTab.chat.rawValue
                    }
                }
            }
        )
    }

    private var rootLayout: some View {
        GeometryReader { geo in
            let metrics = RegularPaneMetrics(totalWidth: geo.size.width, sessionsCollapsed: sessionsCollapsed)
            let showColumns = useSplitLayout && geo.size.width > 0
            HStack(spacing: 0) {
                regularColumnsSlot(shown: showColumns, metrics: metrics)
                tabLayout
                    .frame(width: showColumns ? metrics.chatWidth : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .leading) {
                if showColumns, sessionsCollapsed {
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
        .accessibilityIdentifier(useSplitLayout ? "ipad-workspace-layout" : "compact-workspace-layout")
    }

    private func regularColumnsSlot(shown: Bool, metrics: RegularPaneMetrics) -> some View {
        Group {
            if shown {
                HStack(spacing: 0) {
                    if !sessionsCollapsed {
                        TabletSessionsColumn(
                            state: state,
                            showSettings: $showTabletSettings,
                            onCollapse: { withAnimation(DesignAnimation.spring) { sessionsCollapsed = true } }
                        )
                        .frame(width: metrics.sessionsWidth)
                        Divider()
                    }
                    TabletFilesColumn(
                        state: state,
                        sessionsCollapsed: sessionsCollapsed,
                        onExpandSessions: { withAnimation(DesignAnimation.spring) { sessionsCollapsed = false } }
                    )
                    .frame(width: metrics.filesWidth)
                    Divider()
                }
            } else {
                Color.clear.frame(width: 0)
            }
        }
        .frame(width: shown ? metrics.leadingWidth : 0)
        .clipped()
        .accessibilityHidden(!shown)
        .allowsHitTesting(shown)
    }

    private func restoreConnectionFlow() async {
        if UITestFixtures.shouldSkipConnectionRestore {
            return
        }
        await state.restoreConnectionsAfterForeground()
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

    private var webPreviewRetryFixtureView: some View {
        ZStack(alignment: .topLeading) {
            MarkdownWebPreviewContainer(
                text: UITestFixtures.webPreviewRetryText,
                state: state,
                markdownFilePath: UITestFixtures.webPreviewRetryFile,
                workspaceDirectory: UITestFixtures.webPreviewRetryWorkspace
            )
            .ignoresSafeArea()

            Text(UITestFixtures.webPreviewRetryIdentity)
                .font(.system(size: 1))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("web-preview-fixture-identity")
                .accessibilityIdentifier("web-preview-fixture-identity")
                .accessibilityValue(UITestFixtures.webPreviewRetryIdentity)
        }
    }

    var body: some View {
        widthAdjusted(rootContent)
    }

    @ViewBuilder
    private var rootContent: some View {
        if FileContentReuseFixture.isActive {
            FileContentReuseHost(state: state)
        } else if FileSearchFixture.routesSplitHost {
            FileSearchSplitHost(state: state)
        } else {
            standardFixtureBody
        }
    }

    @ViewBuilder
    private func widthAdjusted<V: View>(_ view: V) -> some View {
        if let forcedWidthClass {
            view.environment(\.horizontalSizeClass, forcedWidthClass)
        } else {
            view
        }
    }

    @ViewBuilder
    private var standardFixtureBody: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_SESSION_INDICATOR_FIXTURE") {
            SessionIndicatorFixtureView()
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else if UITestFixtures.hasUITestWebPreviewRetryFixture {
            webPreviewRetryFixtureView
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else if UITestFixtures.hasUITestWebPreviewModeFixture {
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
        if UITestFixtures.hasUITestWebPreviewRetryFixture {
            webPreviewRetryFixtureView
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else if UITestFixtures.hasUITestWebPreviewFixture {
            webPreviewFixtureView
                .preferredColorScheme(Self.webPreviewFixtureColorScheme)
        } else {
            mainBody
        }
        #endif
    }

    private var mainBody: some View {
        rootLayout
        .overlay(alignment: .bottomLeading) {
            if FileSearchFixture.isActive {
                Text(FileSearchFixture.probe.summary)
                    .font(.system(size: 1))
                    .accessibilityIdentifier("file-search-probe")
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["UITEST_PREVIEW_MIGRATION_HARNESS"] == "1" {
                Button(state.layoutPreference == .focus ? "Auto" : "Focus") {
                    state.layoutPreference = state.layoutPreference == .focus ? .automatic : .focus
                }
                .accessibilityIdentifier("preview-migration-toggle-layout")
                .padding(8)
            }
            #endif
        }
        .overlay(alignment: .bottomTrailing) {
            if TurnStabilityFixture.showsAppendControls {
                TurnStabilityAppendControls(state: state)
                    .padding(.trailing, 12)
                    .padding(.bottom, 140)
            }
        }
        .overlay(alignment: .topTrailing) {
            if Tier4OfflineFixture.isActive {
                Tier4OfflineControls()
            }
        }
        .task {
            #if os(iOS)
            state.activateWatchBridge()
            #endif
            state.cleanupClientCapabilityCallbacks()
            if UITestFixtures.hasUITestDeepLinkFixture,
               let rawURL = ProcessInfo.processInfo.environment["UITEST_INITIAL_DEEP_LINK"],
               let url = URL(string: rawURL) {
                state.receiveDeepLink(url)
            }
            await restoreConnectionFlow()
            await state.processPendingDeepLinkIfPossible()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                state.handleApplicationScene(.active)
            case .inactive:
                state.handleApplicationScene(.inactive)
            case .background:
                state.handleApplicationScene(.background)
            @unknown default:
                state.handleApplicationScene(.other)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await restoreConnectionFlow()
                state.cleanupClientCapabilityCallbacks()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            state.handleApplicationScene(.background)
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
        .environment(\.effectiveLayout, effectiveLayout)
        .environment(\.locale, L10n.currentLocale)
        .onAppear {
            selectedTab = state.selectedTab
        }
        .onChange(of: effectiveLayout) { oldValue, newValue in
            state.applyPreviewLayout(from: oldValue, to: newValue)
            if oldValue == .regular, newValue == .compact {
                selectedTab = RootTab.chat.rawValue
            }
        }
        .onChange(of: state.pendingEventSequence) { _, sequence in
            guard ExternalFileOpenRouting.shouldAdopt(sequence: sequence, path: state.fileToOpenInFilesTab) else { return }
            state.adoptPendingFileOpen(layout: effectiveLayout)
        }
        .onChange(of: state.currentHostProfileID) { oldHost, newHost in
            state.discardPreviewIfHostChanged(from: oldHost, to: newHost)
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
                FileContentView(
                    state: state,
                    filePath: wrapper.path,
                    workspaceDirectory: wrapper.workspaceDirectory,
                    boundSessionID: state.pendingFileOpenOwner?.sessionID
                )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                Task { @MainActor in
                                    state.fileToOpenInFilesTab = nil
                                    state.fileToOpenInFilesTabWorkspaceDirectory = nil
                                    state.pendingFileOpenOwner = nil
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
        Group {
            if showsCarMode {
                carEnabledTabLayout
            } else {
                standardTabLayout
            }
        }
    }

    private var chatTab: some View {
        ChatTabView(
            state: state,
            showSettingsInToolbar: false,
            showSessionListInToolbar: !useSplitLayout,
            showCreateSessionInToolbar: !useSplitLayout
        )
    }

    private var standardTabLayout: some View {
        TabView(selection: tabSelection) {
            systemTabBar(chatTab)
                .tabItem { Label(L10n.t(.appChat), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(RootTab.chat.rawValue)

            systemTabBar(FilesTabView(state: state))
                .tabItem { Label(L10n.t(.navFiles), systemImage: "folder") }
                .tag(RootTab.files.rawValue)

            systemTabBar(SettingsTabView(state: state, isCarModeEnabled: carModeEnabledBinding))
                .tabItem { Label(L10n.t(.navSettings), systemImage: "gear") }
                .tag(RootTab.settings.rawValue)
        }
    }

    private var carEnabledTabLayout: some View {
        TabView(selection: tabSelection) {
            systemTabBar(chatTab)
                .tabItem { Label(L10n.t(.appChat), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(RootTab.chat.rawValue)

            systemTabBar(FilesTabView(state: state))
                .tabItem { Label(L10n.t(.navFiles), systemImage: "folder") }
                .tag(RootTab.files.rawValue)

            systemTabBar(CarModeView(state: state))
                .tabItem { Label(L10n.t(.carTab), systemImage: "waveform") }
                .tag(RootTab.car.rawValue)

            systemTabBar(SettingsTabView(state: state, isCarModeEnabled: carModeEnabledBinding))
                .tabItem { Label(L10n.t(.navSettings), systemImage: "gear") }
                .tag(RootTab.settings.rawValue)
        }
    }

    private func systemTabBar<V: View>(_ content: V) -> some View {
        content
            .toolbar(useSplitLayout ? .hidden : .visible, for: .tabBar)
            .background(alignment: .topLeading) {
                SystemTabBarVisibility(tabBarHidden: useSplitLayout)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

}

private struct RegularPaneMetrics {
    var sessionsWidth: CGFloat
    var filesWidth: CGFloat
    var chatWidth: CGFloat

    var leadingWidth: CGFloat { sessionsWidth + filesWidth + 2 }

    init(totalWidth: CGFloat, sessionsCollapsed: Bool) {
        let sessions = sessionsCollapsed ? 0 : totalWidth * 0.25
        let remaining = max(0, totalWidth - sessions)
        let pane = sessionsCollapsed ? remaining / 2 : totalWidth * 0.375
        sessionsWidth = sessions
        filesWidth = pane
        chatWidth = pane
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
                    FileContentView(
                        state: state,
                        filePath: path,
                        workspaceDirectory: state.previewFileWorkspaceDirectory,
                        boundSessionID: state.previewSessionID
                    )
                } else {
                    FileTreeView(state: state, forceSplitPreview: true)
                        .fileSearchQueryHandlers(state: state)
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
                            state.closeFilePreview()
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
    @State private var archiveSelection = SessionArchiveSelection()

    private var isSelecting: Bool { archiveSelection.scope == state.sessionArchiveScope }

    private var activeNodes: [SessionNode] {
        state.sessionTree(archived: false)
    }

    private var archivedNodes: [SessionNode] {
        state.sessionTree(archived: true)
    }

    var body: some View {
        let presentations = state.sessionIndicatorPresentations
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
                        SessionSectionHeader(title: L10n.t(.sessionsActive), isExpanded: activeExpanded, canToggle: !isSelecting) {
                            activeExpanded.toggle()
                        }

                        if activeExpanded || isSelecting {
                            sessionNodes(activeNodes, archived: false, presentations: presentations)
                        }

                        if !isSelecting {
                            SessionSectionHeader(title: L10n.t(.sessionsArchived), isExpanded: archivedExpanded) {
                                archivedExpanded.toggle()
                            }
                            if archivedExpanded {
                                sessionNodes(archivedNodes, archived: true, presentations: presentations)
                            }
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
                        guard !archiveSelection.isRunning else { return }
                        await state.refreshSessions()
                    }
                    .disabled(archiveSelection.isRunning)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !showSettings { SessionArchiveBar(selection: archiveSelection, state: state) }
            }
            .navigationTitle(showSettings ? L10n.t(.navSettings) : isSelecting
                             ? L10n.t(.sessionsBatchSelected, archiveSelection.selected.count) : L10n.t(.sessionsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sessions 列左上"折叠"按钮 (除 settings sheet 外都显示)
                if !showSettings, !isSelecting, let onCollapse {
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
                    } else if isSelecting {
                        Button(L10n.t(.commonCancel), action: archiveSelection.cancel)
                            .disabled(archiveSelection.isRunning)
                    } else {
                        HStack(spacing: 8) {
                            SessionArchiveSelectButton(disabled: !state.isConnected || activeNodes.isEmpty || mutatingSessionID != nil) {
                                activeExpanded = true
                                archiveSelection.begin(in: state.sessionArchiveScope)
                            }
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
        .onChange(of: state.sessionArchiveScope) { archiveSelection.cancel() }
        .onChange(of: showSettings) { if showSettings { archiveSelection.cancel() } }
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
        .modifier(SessionStatusRefresh(state: state))
    }

    private func sessionNodes(
        _ nodes: [SessionNode],
        archived: Bool,
        depth: Int = 0,
        presentations: [String: SessionIndicatorPresentation]
    ) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                let session = node.session
                let status = state.sessionStatuses[session.id]

                SessionRowView(
                    session: session,
                    status: status,
                    indicator: presentations[session.id]?.indicator,
                    presentation: presentations[session.id],
                    isSelected: !isSelecting && state.currentSessionID == session.id,
                    isMutating: mutatingSessionID == session.id,
                    isArchived: archived,
                    depth: depth,
                    hasChildren: !node.children.isEmpty,
                    isCollapsed: !state.expandedSessionIDs.contains(session.id),
                    archiveChecked: isSelecting ? archiveSelection.selected.contains(session.id) : nil,
                    onSelect: {
                        if isSelecting { archiveSelection.toggle(session.id) } else { state.selectSession(session) }
                    },
                    onToggleCollapse: { state.toggleSessionExpanded(session.id) }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if !isSelecting {
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
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isSelecting {
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
                }

                if state.expandedSessionIDs.contains(session.id) {
                    sessionNodes(
                        node.children,
                        archived: archived,
                        depth: depth + 1,
                        presentations: presentations
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

#if canImport(UIKit)
private struct SystemTabBarVisibility: UIViewRepresentable {
    var tabBarHidden: Bool

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.tabBarHidden = tabBarHidden
        probe.sync()
        for delay in [0.05, 0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak probe] in
                probe?.sync()
            }
        }
    }

    final class Probe: UIView {
        var tabBarHidden = false
        private var syncing = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            sync()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            sync()
        }

        func sync() {
            guard !syncing else { return }
            syncing = true
            defer { syncing = false }
            guard let tab = nearestTabBarController() else { return }
            #if os(visionOS)
            guard tab.isTabBarHidden != tabBarHidden else { return }
            tab.setTabBarHidden(tabBarHidden, animated: false)
            #else
            if #available(iOS 18.0, *) {
                if tab.isTabBarHidden != tabBarHidden {
                    tab.setTabBarHidden(tabBarHidden, animated: false)
                }
                tab.tabBar.isHidden = tabBarHidden
            } else {
                tab.tabBar.isHidden = tabBarHidden
            }
            #endif
        }

        private func nearestTabBarController() -> UITabBarController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let tab = current as? UITabBarController { return tab }
                if let controller = current as? UIViewController, let tab = controller.tabBarController {
                    return tab
                }
                responder = current.next
            }
            return nil
        }
    }
}
#endif

#Preview {
    ContentView()
}
