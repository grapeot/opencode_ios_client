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

    private let dividerHeight: CGFloat = 1
    // File tree defaults to collapsed: in practice the sidebar is used to pick
    // sessions, so sessions own the column and Files is a disclosure the user
    // expands only when they need to browse the workspace.
    @State private var filesExpanded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Button {
                    withAnimation(DesignAnimation.spring) { filesExpanded.toggle() }
                } label: {
                    HStack(spacing: DesignSpacing.sm) {
                        Image(systemName: filesExpanded ? "chevron.down" : "chevron.right")
                            .font(DesignTypography.micro)
                            .foregroundStyle(DesignColors.Neutral.textSecondary)
                        Text(L10n.t(.navFiles))
                            .font(DesignTypography.headline)
                            .foregroundStyle(DesignColors.Neutral.text)
                        Spacer()
                    }
                    .padding(.horizontal, DesignSpacing.lg)
                    .padding(.vertical, DesignSpacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if filesExpanded {
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
                        .frame(maxHeight: .infinity)
                        .refreshable {
                            await state.loadFileTree()
                            await state.loadFileStatus()
                        }

                    Divider()
                        .frame(height: dividerHeight)
                }

                SessionsSidebarList(state: state)
                    .frame(maxHeight: .infinity)
            }
            .navigationTitle(L10n.t(.navWorkspace))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SessionsSidebarList: View {
    @Bindable var state: AppState
    @State private var activeExpanded = true
    @State private var archivedExpanded = false
    @State private var mutatingSessionID: String?
    @State private var actionError: String?

    private var activeNodes: [SessionNode] {
        state.sessionTree(archived: false)
    }

    private var archivedNodes: [SessionNode] {
        state.sessionTree(archived: true)
    }

    var body: some View {
        List {
            Section {
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
        }
        .listStyle(.plain)
        .tint(DesignColors.Brand.primary)
        .refreshable {
            await state.refreshSessions()
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
}
