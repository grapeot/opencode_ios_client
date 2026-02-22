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
                        .frame(height: filesHeight)
                        .refreshable {
                            await state.loadFileTree()
                            await state.loadFileStatus()
                        }

                    Divider()
                        .frame(height: dividerHeight)

                    SessionsSidebarList(state: state)
                        .frame(height: sessionsHeight)
                }
            }
            .navigationTitle(L10n.t(.navWorkspace))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SessionsSidebarList: View {
    @Bindable var state: AppState
    @State private var pendingDeleteSession: Session?
    @State private var deletingSessionID: String?
    @State private var deleteError: String?

    var body: some View {
        List {
            Section(L10n.t(.sessionsTitle)) {
                ForEach(state.sortedSessions) { session in
                    SessionRowView(
                        session: session,
                        status: state.sessionStatuses[session.id],
                        isSelected: state.currentSessionID == session.id,
                        isDeleting: deletingSessionID == session.id
                    ) {
                        state.selectSession(session)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDeleteSession = session
                        } label: {
                            Label(L10n.t(.sessionsDelete), systemImage: "trash")
                        }
                        .tint(.red)
                        .disabled(deletingSessionID != nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .tint(.secondary)
        .refreshable {
            await state.refreshSessions()
        }
        .alert(
            L10n.t(.sessionsDeleteConfirmTitle),
            isPresented: Binding(
                get: { pendingDeleteSession != nil },
                set: { if !$0 { pendingDeleteSession = nil } }
            ),
            presenting: pendingDeleteSession
        ) { session in
            Button(L10n.t(.commonCancel), role: .cancel) {}
            Button(L10n.t(.sessionsDelete), role: .destructive) {
                confirmDelete(session)
            }
        } message: { session in
            Text(L10n.t(.sessionsDeleteConfirmMessage))
        }
        .alert(
            L10n.t(.sessionsDeleteFailedTitle),
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button(L10n.t(.commonOk)) {
                deleteError = nil
            }
        } message: {
            if let deleteError {
                Text(deleteError)
            }
        }
    }

    private func confirmDelete(_ session: Session) {
        guard deletingSessionID == nil else { return }
        deletingSessionID = session.id
        Task {
            do {
                try await state.deleteSession(sessionID: session.id)
            } catch {
                deleteError = error.localizedDescription
            }
            deletingSessionID = nil
        }
    }
}
