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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettingsSheet = false
    @State private var showTabletSettings = false
    @State private var selectedTab = 0
    @State private var carModeEnabled: Bool
    @State private var sessionsCollapsed: Bool = false
    @State private var navigationBarFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowWidth: CGFloat = 0
    @State private var showFileBrowser = false
    @AppStorage("workspace.filesPinned") private var filesPinned = true

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

    private var presentation: WorkspacePresentation {
        if showsCarMode && selectedTab == RootTab.car.rawValue { return .compact }
        if let forcedWidthClass {
            return state.layoutPreference == .automatic && forcedWidthClass == .regular ? .wide : .compact
        }
        return WorkspacePresentation.resolve(
            preference: state.layoutPreference,
            width: windowWidth,
            widthClass: WindowWidthClass(horizontalSizeClass: resolvedSizeClass),
            shortWindow: verticalSizeClass == .compact
        )
    }

    private var effectiveLayout: EffectiveLayout { presentation.previewLayout }
    private var useSplitLayout: Bool { presentation != .compact }
    private var showsFilesColumn: Bool { presentation == .wide && (filesPinned || state.previewFilePath != nil) }

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

    private var rootLayout: some View {
        GeometryReader { geo in
            let metrics = RegularPaneMetrics(totalWidth: geo.size.width, sessionsCollapsed: sessionsCollapsed,
                                             showsFiles: showsFilesColumn)
            let showColumns = useSplitLayout && geo.size.width > 0
            let buttonTop = navigationButtonTop(in: geo)
            HStack(spacing: 0) {
                regularColumnsSlot(shown: showColumns, metrics: metrics, buttonTop: buttonTop)
                tabLayout
                    .frame(width: showColumns ? metrics.chatWidth : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: sessionsCollapsed)
            .overlay(alignment: .leading) {
                if showColumns, sessionsCollapsed {
                    Color.clear
                        .frame(width: 16)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if value.translation.width > 40 && abs(value.translation.height) < 80 {
                                        sessionsCollapsed = false
                                    }
                                }
                        )
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { windowWidth = $0 }
        .background(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier(presentation == .sidebar ? "sidebar-workspace-layout"
                                         : useSplitLayout ? "ipad-workspace-layout" : "compact-workspace-layout")
        }
    }

    private func navigationButtonTop(in geo: GeometryProxy) -> CGFloat {
        let rootTop = geo.frame(in: .global).minY
        guard navigationBarFrame.height > 1 else { return geo.safeAreaInsets.top }
        return max(0, navigationBarFrame.midY - 22 - rootTop)
    }

    private func regularColumnsSlot(shown: Bool, metrics: RegularPaneMetrics, buttonTop: CGFloat) -> some View {
        Group {
            if shown {
                HStack(spacing: 0) {
                    TabletSessionsColumn(
                        state: state,
                        showSettings: $showTabletSettings,
                        carModeEnabled: carModeEnabledBinding,
                        usesNarrowLayout: metrics.sessionsWidth < 240,
                        usesAlignedHeader: alignsSessionHeader,
                        headerTop: buttonTop,
                        onCollapse: { sessionsCollapsed = true }
                    )
                    .frame(width: metrics.sessionsWidth)
                    .clipped()
                    .accessibilityHidden(sessionsCollapsed)
                    .allowsHitTesting(!sessionsCollapsed)
                    if metrics.sessionsWidth > 0 { Divider() }
                    if showsFilesColumn {
                        TabletFilesColumn(
                            state: state,
                            sessionsCollapsed: sessionsCollapsed,
                            onExpandSessions: { sessionsCollapsed = false }
                        )
                        .frame(width: metrics.filesWidth)
                        Divider()
                    }
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

    private var alignsSessionHeader: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
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
        }
        .onChange(of: presentation) { oldValue, newValue in
            guard oldValue != .compact, newValue == .compact, selectedTab != RootTab.car.rawValue else { return }
            selectedTab = RootTab.chat.rawValue
            state.selectedTab = RootTab.chat.rawValue
        }
        .onChange(of: state.pendingEventSequence) { _, sequence in
            guard ExternalFileOpenRouting.shouldAdopt(sequence: sequence, path: state.fileToOpenInFilesTab) else { return }
            state.adoptPendingFileOpen(layout: effectiveLayout)
            if state.inlinePreviewPath != nil {
                selectedTab = RootTab.chat.rawValue
                state.selectedTab = RootTab.chat.rawValue
            }
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
        .sheet(isPresented: $showFileBrowser) {
            NavigationStack {
                FileTreeView(state: state, onFileSelect: openWorkspaceFile)
                    .fileSearchQueryHandlers(state: state)
                    .navigationTitle(L10n.t(.navFiles))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.t(.appClose)) { showFileBrowser = false }
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

    private func openWorkspaceFile(_ path: String) {
        if effectiveLayout == .regular {
            state.presentFilesColumnPreview(path: path, workspaceDirectory: state.effectiveProjectDirectory)
        } else {
            state.presentChatFilePreview(path: path, workspaceDirectory: state.effectiveProjectDirectory ?? "",
                                         layout: .compact, bindToSession: false)
        }
        selectedTab = RootTab.chat.rawValue
        state.selectedTab = RootTab.chat.rawValue
        showFileBrowser = false
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
            showCreateSessionInToolbar: !useSplitLayout,
            onFilesTap: useSplitLayout ? { showFileBrowser = true } : nil,
            onRestoreSessions: useSplitLayout && sessionsCollapsed && !showsFilesColumn
                ? { sessionsCollapsed = false } : nil,
            filesPinned: presentation == .wide ? $filesPinned : nil,
            sharesWidthWithFiles: showsFilesColumn,
            navigationBarFrame: $navigationBarFrame
        )
    }

    private var standardTabLayout: some View {
        TabView(selection: tabSelection) {
            systemTabBar(chatTab)
                .tabItem { Label(L10n.t(.appChat), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(RootTab.chat.rawValue)

            systemTabBar(FilesTabView(state: state, onFileSelect: openWorkspaceFile))
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

            systemTabBar(FilesTabView(state: state, onFileSelect: openWorkspaceFile))
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
    let sessionsWidth: CGFloat
    let filesWidth: CGFloat
    let chatWidth: CGFloat

    var leadingWidth: CGFloat { sessionsWidth + filesWidth + (sessionsWidth > 0 ? 1 : 0) + (filesWidth > 0 ? 1 : 0) }

    init(totalWidth: CGFloat, sessionsCollapsed: Bool, showsFiles: Bool) {
        let sessions = sessionsCollapsed ? 0 : min(264, max(152, totalWidth * 0.245))
        let contentWidth = max(0, totalWidth - sessions - (sessions > 0 ? 1 : 0) - (showsFiles ? 1 : 0))
        sessionsWidth = sessions
        if showsFiles {
            // Size the composer from the window, not from the space left by Sessions.
            chatWidth = min(contentWidth, min(360, max(288, totalWidth * 0.32)))
            filesWidth = contentWidth - chatWidth
        } else {
            filesWidth = 0
            chatWidth = contentWidth
        }
    }
}

private struct TabletFilesColumn: View {
    @Bindable var state: AppState
    var sessionsCollapsed = false
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
        // Keep the restore control out of the navigation bar so resizing the
        // sidebar doesn't also change the native title's toolbar layout.
        .overlay(alignment: .topLeading) {
            if sessionsCollapsed, let onExpandSessions {
                Button(action: onExpandSessions) {
                    Image(systemName: "sidebar.left")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(.sidebarShowSessions))
                .accessibilityIdentifier("ipad-show-sessions-button")
                .padding(.leading, 4)
                .padding(.top, 6)
            }
        }
    }
}

private struct TabletSessionsColumn: View {
    @Bindable var state: AppState
    @Binding var showSettings: Bool
    @Binding var carModeEnabled: Bool
    let usesNarrowLayout: Bool
    let usesAlignedHeader: Bool
    let headerTop: CGFloat
    var onCollapse: (() -> Void)? = nil
    @State private var activeExpanded = true
    @State private var archivedExpanded = false
    @State private var mutatingSessionID: String?
    @State private var actionError: String?
    @State private var showCreateDisabledAlert = false
    @State private var archiveSelection = SessionArchiveSelection()

    private var isSelecting: Bool { archiveSelection.scope == state.sessionArchiveScope }
    private var showsAlignedHeader: Bool { usesAlignedHeader && !showSettings && !isSelecting }

    private var activeNodes: [SessionNode] {
        state.sessionTree(archived: false)
    }

    private var archivedNodes: [SessionNode] {
        state.sessionTree(archived: true)
    }

    var body: some View {
        let presentations = state.sessionIndicatorPresentations
        VStack(spacing: 0) {
            if showsAlignedHeader { alignedHeader }
            sessionsNavigation(presentations: presentations)
        }
    }

    private func sessionsNavigation(presentations: [String: SessionIndicatorPresentation]) -> some View {
        NavigationStack {
            Group {
                if showSettings {
                    SettingsTabView(state: state, isCarModeEnabled: $carModeEnabled)
                } else if activeNodes.isEmpty && archivedNodes.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.sessionsEmptyTitle),
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text(L10n.t(.sessionsEmptyDescription))
                    )
                } else {
                    List {
                        SessionSectionHeader(
                            title: L10n.t(.sessionsActive), isExpanded: activeExpanded, canToggle: !isSelecting,
                            onToggle: { activeExpanded.toggle() },
                            archiveAccessory: isSelecting ? nil : SessionArchiveSelectButton(
                                disabled: !state.isConnected || activeNodes.isEmpty || mutatingSessionID != nil
                            ) {
                                activeExpanded = true
                                archiveSelection.begin(in: state.sessionArchiveScope)
                            }
                        )

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
            .modifier(SessionArchiveSuccessOverlay(selection: archiveSelection))
            .navigationTitle(showSettings ? L10n.t(.navSettings) : isSelecting
                             ? L10n.t(.sessionsBatchSelected, archiveSelection.selected.count) : L10n.t(.sessionsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsAlignedHeader ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !showsAlignedHeader, !showSettings, !isSelecting, let onCollapse {
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
                        .accessibilityIdentifier("sidebar-settings-done")
                    } else if isSelecting {
                        Button(L10n.t(.commonCancel), action: archiveSelection.cancel)
                            .disabled(archiveSelection.isRunning)
                    } else if !showsAlignedHeader {
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
                            .accessibilityIdentifier("sidebar-new-session")

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
        .onChange(of: state.sessionArchiveScope) { archiveSelection.scopeChanged() }
        .onChange(of: showSettings) { if showSettings { archiveSelection.scopeChanged() } }
        .onDisappear { archiveSelection.scopeChanged() }
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

    private var alignedHeader: some View {
        HStack(spacing: 0) {
            if let onCollapse {
                alignedHeaderButton("sidebar.left", label: L10n.t(.sidebarHideSessions),
                                    id: "ipad-hide-sessions-button", action: onCollapse)
            }
            Spacer(minLength: 0)
            alignedHeaderButton(state.canCreateSession ? "plus" : "plus.circle",
                                label: L10n.t(.sessionsNew), id: "sidebar-new-session") {
                if state.canCreateSession {
                    Task { await state.createSession() }
                } else {
                    showCreateDisabledAlert = true
                }
            }
            alignedHeaderButton("gear", label: L10n.t(.navSettings), id: "ipad-settings-button") {
                showSettings = true
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, headerTop)
        .background(.bar)
    }

    private func alignedHeaderButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .accessibilityIdentifier(id)
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
                    titleLineLimit: usesNarrowLayout ? 3 : 1,
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
