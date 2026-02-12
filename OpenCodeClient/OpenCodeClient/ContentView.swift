//
//  ContentView.swift
//  OpenCodeClient
//

import SwiftUI

struct ContentView: View {
    @State private var state = AppState()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettingsSheet = false

    /// iPad / Vision Pro：左右分栏，无 Tab Bar
    private var useSplitLayout: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if useSplitLayout {
                splitLayout
            } else {
                tabLayout
            }
        }
        .task {
            await state.refresh()
            if state.isConnected {
                state.connectSSE()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await state.refresh()
                if state.isConnected {
                    state.connectSSE()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            state.disconnectSSE()
        }
        .preferredColorScheme(state.themePreference == "light" ? .light : state.themePreference == "dark" ? .dark : nil)
        .sheet(item: Binding(
            get: { state.fileToOpenInFilesTab.map { FilePathWrapper(path: $0) } },
            set: { newValue in
                state.fileToOpenInFilesTab = newValue?.path
                if newValue == nil, !useSplitLayout {
                    state.selectedTab = 0
                }
            }
        )) { wrapper in
            NavigationStack {
                FileContentView(state: state, filePath: wrapper.path)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                state.fileToOpenInFilesTab = nil
                                if !useSplitLayout { state.selectedTab = 0 }
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                SettingsTabView(state: state)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showSettingsSheet = false }
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
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)

            FilesTabView(state: state)
                .tabItem { Label("Files", systemImage: "folder") }
                .tag(1)

            SettingsTabView(state: state)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(2)
        }
    }

    /// iPad / Vision Pro：左右分栏，左 Files 右 Chat，Settings 为 toolbar 按钮
    private var splitLayout: some View {
        NavigationSplitView {
            FilesTabView(state: state)
        } detail: {
            ChatTabView(state: state, showSettingsInToolbar: true, onSettingsTap: { showSettingsSheet = true })
        }
    }
}

private struct FilePathWrapper: Identifiable {
    let path: String
    var id: String { path }
}

#Preview {
    ContentView()
}
