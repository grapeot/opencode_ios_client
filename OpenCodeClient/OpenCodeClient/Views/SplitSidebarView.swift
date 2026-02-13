//
//  SplitSidebarView.swift
//  OpenCodeClient
//

import SwiftUI

/// iPad / Vision Pro split layout sidebar:
/// - Top: File tree
/// - Bottom: Sessions list (selecting switches the chat on the right)
struct SplitSidebarView: View {
    @Bindable var state: AppState

    private let minPaneHeight: CGFloat = 220
    private let dividerHeight: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let available = max(0, geo.size.height - dividerHeight)
                let half = max(minPaneHeight, available / 2)
                let filesHeight = half
                let sessionsHeight = max(minPaneHeight, available - half)

                VStack(spacing: 0) {
                    FileTreeView(state: state, forceSplitPreview: true)
                        .searchable(text: $state.fileSearchQuery, prompt: "Search files")
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
                        .frame(height: filesHeight)

                    Divider()
                        .frame(height: dividerHeight)

                    SessionsSidebarList(state: state)
                        .frame(height: sessionsHeight)
                }
            }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SessionsSidebarList: View {
    @Bindable var state: AppState

    var body: some View {
        List {
            Section("Sessions") {
                ForEach(state.sortedSessions) { session in
                    SessionRowView(
                        session: session,
                        status: state.sessionStatuses[session.id],
                        isSelected: state.currentSessionID == session.id
                    ) {
                        state.selectSession(session)
                    }
                }
            }
        }
        .listStyle(.plain)
        .tint(.secondary)
        .refreshable {
            await state.refreshSessions()
        }
    }
}
