//
//  ContentView.swift
//  OpenCodeClient
//

import SwiftUI

struct ContentView: View {
    @State private var state = AppState()

    var body: some View {
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
            set: { state.fileToOpenInFilesTab = $0?.path }
        )) { wrapper in
            NavigationStack {
                FileContentView(state: state, filePath: wrapper.path)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                state.fileToOpenInFilesTab = nil
                            }
                        }
                    }
            }
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
