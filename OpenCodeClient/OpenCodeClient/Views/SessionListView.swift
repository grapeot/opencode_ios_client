//
//  SessionListView.swift
//  OpenCodeClient
//

import SwiftUI

struct SessionListView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeleteSession: Session?
    @State private var deletingSessionID: String?
    @State private var deleteError: String?
    @State private var showCreateDisabledAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if state.sidebarSessions.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.sessionsEmptyTitle),
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text(L10n.t(.sessionsEmptyDescription))
                    )
                } else {
                    List {
                        sessionNodes(state.sessionTree)

                        if state.isLoadingMoreSessions {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                        } else if state.canLoadMoreSessions, let lastSessionID = state.sidebarSessions.last?.id {
                            Color.clear
                                .frame(height: 1)
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    Task { await state.loadMoreSessions() }
                                }
                                .id("load-more-\(lastSessionID)")
                        }
                    }
                    .accessibilityIdentifier("session-list")
                    .refreshable {
                        await state.refreshSessions()
                    }
                }
            }
            .navigationTitle(L10n.t(.sessionsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t(.sessionsClose)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await state.createSession()
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!state.canCreateSession)
                        .foregroundColor(state.canCreateSession ? DesignColors.Brand.primary : DesignColors.Neutral.textTertiary)

                        if !state.canCreateSession {
                            Button {
                                showCreateDisabledAlert = true
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
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
        .task {
            await state.refreshSessions()
        }
        .alert(L10n.t(.chatCreateDisabledHint), isPresented: $showCreateDisabledAlert) {
            Button(L10n.t(.commonOk)) {}
        }
    }

    private func selectSession(_ session: Session) {
        state.selectSession(session)
        dismiss()
    }

    private func sessionNodes(_ nodes: [SessionNode], depth: Int = 0) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                let session = node.session
                let status = state.sessionStatuses[session.id]

                SessionRowView(
                    session: session,
                    status: status,
                    isSelected: state.currentSessionID == session.id,
                    isDeleting: deletingSessionID == session.id,
                    depth: depth,
                    hasChildren: !node.children.isEmpty,
                    isCollapsed: !state.expandedSessionIDs.contains(session.id),
                    onSelect: { selectSession(session) },
                    onToggleCollapse: { state.toggleSessionExpanded(session.id) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDeleteSession = session
                    } label: {
                        Label(L10n.t(.sessionsDelete), systemImage: "trash")
                    }
                    .tint(.red)
                    .disabled(deletingSessionID != nil)
                }

                if state.expandedSessionIDs.contains(session.id) {
                    sessionNodes(node.children, depth: depth + 1)
                }
            }
        )
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

struct SessionRowView: View {
    let session: Session
    let status: SessionStatus?
    let isSelected: Bool
    let isDeleting: Bool
    var depth: Int = 0
    var hasChildren: Bool = false
    var isCollapsed: Bool = false
    let onSelect: () -> Void
    var onToggleCollapse: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    
    private var isBusy: Bool {
        guard let status else { return false }
        return status.type == "busy" || status.type == "retry"
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: DesignCorners.medium)
                .fill(DesignColors.Brand.primary.opacity(DesignColors.Opacity.selectionFill))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(DesignColors.Brand.primary)
                        .frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
        } else {
            Color.clear
        }
    }

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            if hasChildren {
                Button {
                    onToggleCollapse?()
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(DesignTypography.micro)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(width: 12)
                .accessibilityIdentifier("session-toggle-\(session.id)")
            } else if depth > 0 {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DesignColors.Neutral.textTertiary)
                    .frame(width: 3, height: 3)
                    .padding(.leading, 4.5)
            } else {
                Color.clear
                    .frame(width: 12)
            }

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(session.title.isEmpty ? L10n.t(.sessionsUntitled) : session.title)
                    .font(depth > 0 ? DesignTypography.body : DesignTypography.headline)
                    .foregroundStyle(depth > 0 ? DesignColors.Neutral.textSecondary : (isBusy ? DesignColors.Brand.primary : DesignColors.Neutral.text))
                    .lineLimit(1)

                HStack(spacing: DesignSpacing.sm) {
                    Text(formattedDate(session.time.updated))
                        .font(DesignTypography.meta)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)

                    if let status {
                        Text(statusLabel(status))
                            .font(DesignTypography.meta)
                            .foregroundStyle(statusColor(status))
                    }
                }
            }

            Spacer()

            if isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignColors.Brand.primary.opacity(0.6))
            }
        }
        .padding(.vertical, DesignSpacing.sm)
        .padding(.leading, CGFloat(depth) * DesignSpacing.xl)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDeleting else { return }
            onSelect()
        }
        // Selected row: a single rounded fill with the accent bar baked into its
        // left edge. Drawing the bar as part of the background (rather than a
        // separate overlay) keeps it clipped to the rounded corners, so it can't
        // poke out past the pill or collide with the expand/indent of child rows.
        .listRowBackground(selectionBackground)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-row-\(session.id)")
    }

    private func formattedDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale.current
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func statusLabel(_ status: SessionStatus) -> String {
        switch status.type {
        case "busy": return L10n.t(.sessionsStatusBusy)
        case "retry": return L10n.t(.sessionsStatusRetry)
        default: return L10n.t(.sessionsStatusIdle)
        }
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status.type {
        case "busy", "retry": return DesignColors.Brand.primary
        default: return DesignColors.Neutral.textSecondary
        }
    }
}
