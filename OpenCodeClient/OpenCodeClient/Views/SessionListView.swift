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
                let displayState = SessionDisplayState.derive(
                    session: session,
                    status: status,
                    isBlocked: state.isSessionBlocked(session.id),
                    lastViewedAt: state.lastViewedAt(for: session.id),
                    now: Int(Date().timeIntervalSince1970 * 1000)
                )
                // Title summary only has messages for the currently-open session;
                // every other row falls back to the existing title inside the helper.
                let rowMessages = state.currentSessionID == session.id ? state.messages : []

                SessionRowView(
                    session: session,
                    status: status,
                    displayState: displayState,
                    blockKind: state.sessionBlockKind(session.id),
                    titleSummary: SessionTitleSummary.summary(for: session, messages: rowMessages),
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
    /// The derived state driving every per-row visual cue (bar / icon / dimming /
    /// trailing). Computed at the call site via `SessionDisplayState.derive`.
    var displayState: SessionDisplayState = .doneRead
    /// When `.needsYou`, which interaction is pending — picks the trailing label.
    var blockKind: AppState.SessionBlockKind? = nil
    /// Intent summary (or original title) from `SessionTitleSummary`.
    var titleSummary: String? = nil
    let isSelected: Bool
    let isDeleting: Bool
    var depth: Int = 0
    var hasChildren: Bool = false
    var isCollapsed: Bool = false
    let onSelect: () -> Void
    var onToggleCollapse: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    /// Drives the subtle running-state icon pulse.
    @State private var isPulsing = false

    // MARK: Display-state derived styling

    /// Stable name used in accessibility identifiers / values so UI tests can
    /// assert the row's state without inspecting colors.
    private var stateName: String {
        switch displayState {
        case .needsYou: return "needsYou"
        case .running: return "running"
        case .doneUnread: return "doneUnread"
        case .doneRead: return "doneRead"
        case .stale: return "stale"
        }
    }

    /// Leading status bar color + width. `nil` = no bar.
    ///
    /// The bar is reserved for the two states that genuinely need attention
    /// (needsYou / running). Done-unread does NOT get a bar — unread is carried
    /// by title weight instead (see `titleFont`), so the bar stays a scarce,
    /// high-signal cue rather than appearing on nearly every row.
    private var statusBar: (color: Color, width: CGFloat)? {
        switch displayState {
        case .needsYou: return (DesignColors.Brand.primary, 3)
        case .running: return (DesignColors.Brand.teal, 3)
        case .doneUnread, .doneRead, .stale: return nil
        }
    }

    /// Title color, per the state dimming ladder: attention/unread at full text,
    /// read recedes to secondary, stale to tertiary. This dimming is the time-
    /// depth axis — newer/unattended stays bright, old fades down.
    private var titleColor: Color {
        switch displayState {
        case .needsYou, .running, .doneUnread:
            return depth > 0 ? DesignColors.Neutral.textSecondary : DesignColors.Neutral.text
        case .doneRead:
            return DesignColors.Neutral.textSecondary
        case .stale:
            return DesignColors.Neutral.textTertiary
        }
    }

    /// Title weight IS the unread signal. Unread (and the two attention states)
    /// render in semibold headline; once read, the title drops to regular body.
    /// With no separate unread dot, a screenful of unread reads as a calm field
    /// of bolder titles rather than a field of blinking dots. Child rows stay
    /// body to preserve the tree's lighter treatment.
    private var titleFont: Font {
        if depth > 0 { return DesignTypography.body }
        switch displayState {
        case .needsYou, .running, .doneUnread:
            return DesignTypography.headline
        case .doneRead, .stale:
            return DesignTypography.body
        }
    }

    private var displayTitle: String {
        if let titleSummary, !titleSummary.isEmpty { return titleSummary }
        return session.title.isEmpty ? L10n.t(.sessionsUntitled) : session.title
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

    // MARK: Leading state icon

    @ViewBuilder
    private var stateIcon: some View {
        switch displayState {
        case .needsYou:
            Image(systemName: "bell.fill")
                .font(DesignTypography.meta)
                .foregroundStyle(DesignColors.Brand.primary)
        case .running:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(DesignColors.Brand.teal)
                .opacity(isPulsing ? 0.35 : 1.0)
                .animation(DesignAnimation.breathing, value: isPulsing)
                .onAppear { isPulsing = true }
        case .doneUnread, .doneRead, .stale:
            // Unread is carried by title weight, not a separate dot — keeps the
            // leading column to one signal (state) instead of stacking dot + bar.
            EmptyView()
        }
    }

    /// Only the two attention states get a leading icon. Unread reads through
    /// title weight, so it doesn't occupy the icon column.
    private var hasStateIcon: Bool {
        switch displayState {
        case .needsYou, .running: return true
        case .doneUnread, .doneRead, .stale: return false
        }
    }

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            // Column 1 — hierarchy (tree): expand chevron, child dot, or empty.
            // Always a fixed 12pt so this axis stays its own column and never
            // shares space with the state cue.
            Group {
                if hasChildren {
                    Button {
                        onToggleCollapse?()
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(DesignTypography.micro)
                            .foregroundStyle(DesignColors.Neutral.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session-toggle-\(session.id)")
                } else if depth > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DesignColors.Neutral.textTertiary)
                        .frame(width: 3, height: 3)
                } else {
                    Color.clear
                }
            }
            .frame(width: 12)

            // Column 2 — state cue: needsYou bell / running pulse, or an empty
            // reserved slot so every title aligns on the same vertical line
            // whether or not the row carries a state icon.
            Group {
                if hasStateIcon {
                    stateIcon
                        .accessibilityIdentifier("session-state-\(session.id)-\(stateName)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(displayTitle)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                HStack(spacing: DesignSpacing.sm) {
                    if case .running = displayState {
                        // Live elapsed timer, refreshed once a second, without
                        // owning a manual Timer (TimelineView pauses off-screen).
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(L10n.t(.sessionsStateRunning)) · \(elapsedText(sinceMS: session.time.updated, now: context.date))")
                                .font(DesignTypography.meta)
                                .foregroundStyle(trailingColor)
                        }
                    } else {
                        trailingText
                            .font(DesignTypography.meta)
                            .foregroundStyle(trailingColor)
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
        // The status bar is a thin leading rule layered on top of the row content
        // (and over the selection fill), color/width keyed off the display state.
        .listRowBackground(selectionBackground)
        .overlay(alignment: .leading) {
            if let statusBar {
                Rectangle()
                    .fill(statusBar.color)
                    .frame(width: statusBar.width)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-row-\(session.id)")
        .accessibilityValue(stateName)
    }

    // MARK: Trailing (time / status) text

    /// Static trailing text. `.running` renders its own live TimelineView in the
    /// body instead of using this branch.
    private var trailingText: Text {
        switch displayState {
        case .needsYou:
            let label = blockKind == .question
                ? L10n.t(.sessionsStateNeedsAnswer)
                : L10n.t(.sessionsStateNeedsAuth)
            return Text("\(label) · \(blockedDurationText)")
        case .running:
            return Text("\(L10n.t(.sessionsStateRunning)) · \(elapsedText(sinceMS: session.time.updated, now: Date()))")
        case .doneUnread, .doneRead, .stale:
            return Text(formattedDate(session.time.updated))
        }
    }

    private var trailingColor: Color {
        switch displayState {
        case .needsYou: return DesignColors.Brand.primary
        case .running: return DesignColors.Brand.teal
        case .doneUnread, .doneRead, .stale: return DesignColors.Neutral.textSecondary
        }
    }

    private func formattedDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale.current
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Coarse, live-enough blocked duration ("等了 Xm") since the session last
    /// updated — proxy for "how long it has been waiting on you".
    private var blockedDurationText: String {
        elapsedText(sinceMS: session.time.updated, now: Date())
    }

    private func elapsedText(sinceMS: Int, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince1970 - TimeInterval(sinceMS) / 1000)
        let seconds = Int(elapsed)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h\(minutes % 60)m"
    }
}
