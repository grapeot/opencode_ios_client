//
//  ContentView.swift
//  OpenCodeClient
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @State private var state = AppState()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettingsSheet = false

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

    private func restoreConnectionFlow() async {
        if state.sshTunnelManager.config.isEnabled,
           state.sshTunnelManager.status != .connected {
            await state.sshTunnelManager.connect()
        }

        await state.refresh()

        // iOS suspend/restore can leave SSH state stale (status still connected but
        // actual tunnel already dropped). If refresh still cannot reach server through
        // localhost after an enabled SSH config, force a tunnel re-establish once.
        if state.sshTunnelManager.config.isEnabled, !state.isConnected {
            state.sshTunnelManager.disconnect()
            await state.sshTunnelManager.connect()
            await state.refresh()
        }

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
            if state.sshTunnelManager.config.isEnabled {
                state.sshTunnelManager.disconnect()
            }
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
                .tabItem { Label(L10n.t(.appChat), systemImage: "bubble.left.and.bubble.right") }
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

            NavigationSplitView {
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
