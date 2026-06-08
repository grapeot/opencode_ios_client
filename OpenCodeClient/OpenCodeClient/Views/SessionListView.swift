//
//  SessionListView.swift
//  OpenCodeClient
//

import SwiftUI

struct SessionListView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sessionSearchQuery = ""
    @State private var activeExpanded = true
    @State private var archivedExpanded = false
    @State private var mutatingSessionID: String?
    @State private var actionError: String?
    @State private var showCreateDisabledAlert = false

    private var activeNodes: [SessionNode] {
        state.sessionTree(archived: false, searchQuery: sessionSearchQuery)
    }

    private var archivedNodes: [SessionNode] {
        state.sessionTree(archived: true, searchQuery: sessionSearchQuery)
    }

    private var activeCount: Int {
        state.filteredSessions(archived: false, searchQuery: sessionSearchQuery).count
    }

    private var archivedCount: Int {
        state.filteredSessions(archived: true, searchQuery: sessionSearchQuery).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeCount == 0 && archivedCount == 0 {
                    ContentUnavailableView(
                        L10n.t(.sessionsEmptyTitle),
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text(L10n.t(.sessionsEmptyDescription))
                    )
                } else {
                    List {
                        SessionSectionHeader(title: L10n.t(.sessionsActive), count: activeCount, isExpanded: activeExpanded) {
                            activeExpanded.toggle()
                        }

                        if activeExpanded {
                            sessionNodes(activeNodes, archived: false)
                        }

                        SessionSectionHeader(title: L10n.t(.sessionsArchived), count: archivedCount, isExpanded: archivedExpanded) {
                            archivedExpanded.toggle()
                        }

                        if archivedExpanded {
                            sessionNodes(archivedNodes, archived: true)
                        }

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
            .searchable(text: $sessionSearchQuery, prompt: L10n.t(.sessionsSearch))
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
                    onSelect: { selectSession(session) },
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

struct SessionSectionHeader: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignSpacing.sm) {
                Text(title)
                    .font(DesignTypography.meta.weight(.semibold))
                    .foregroundStyle(DesignColors.Neutral.textSecondary)
                Spacer()
                Text("\(count)")
                    .font(DesignTypography.meta)
                    .foregroundStyle(DesignColors.Neutral.textTertiary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(DesignTypography.micro.weight(.semibold))
                    .foregroundStyle(DesignColors.Neutral.textSecondary)
            }
            .padding(.vertical, DesignSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

struct SessionRowView: View {
    let session: Session
    let status: SessionStatus?
    let isSelected: Bool
    let isMutating: Bool
    let isArchived: Bool
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
                .fill((isArchived ? DesignColors.Neutral.textTertiary : DesignColors.Brand.primary).opacity(DesignColors.Opacity.selectionFill))
                .overlay(alignment: .leading) {
                    if !isArchived {
                        Rectangle()
                            .fill(DesignColors.Brand.primary)
                            .frame(width: 3)
                    }
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
                    .foregroundStyle(titleColor(depth: depth, isBusy: isBusy))
                    .lineLimit(1)

                HStack(spacing: DesignSpacing.sm) {
                    Text(formattedDate(session.time.updated))
                        .font(DesignTypography.meta)
                        .foregroundStyle(isArchived ? DesignColors.Neutral.textTertiary : DesignColors.Neutral.textSecondary)

                    if let status {
                        Text(statusLabel(status))
                            .font(DesignTypography.meta)
                            .foregroundStyle(statusColor(status))
                    }
                }
            }

            Spacer()

            if isMutating {
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
            guard !isMutating else { return }
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

    private func titleColor(depth: Int, isBusy: Bool) -> Color {
        if isArchived { return DesignColors.Neutral.textTertiary }
        if depth > 0 { return DesignColors.Neutral.textSecondary }
        return DesignColors.Neutral.text
    }
}
