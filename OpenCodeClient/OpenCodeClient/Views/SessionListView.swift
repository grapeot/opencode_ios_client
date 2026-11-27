//
//  SessionListView.swift
//  OpenCodeClient
//

import SwiftUI

struct SessionListView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var activeExpanded = true
    @State private var archivedExpanded = false
    @State private var mutatingSessionID: String?
    @State private var actionError: String?
    @State private var showCreateDisabledAlert = false
    @State private var archiveSelection = SessionArchiveSelection()

    private var isSelecting: Bool { archiveSelection.scope == state.sessionArchiveScope }
    private var headerActionWidth: CGFloat { state.canCreateSession ? 88 : 108 }

    private var activeNodes: [SessionNode] {
        state.sessionTree(archived: false)
    }

    private var archivedNodes: [SessionNode] {
        state.sessionTree(archived: true)
    }

    var body: some View {
        let presentations = state.sessionIndicatorPresentations
        // One tree derivation per render; the archived tree only when it can show.
        let activeNodes = self.activeNodes
        let archivedNodes = archivedExpanded || activeNodes.isEmpty ? self.archivedNodes : []
        VStack(spacing: 0) {
            HStack {
                Button(L10n.t(isSelecting ? .commonCancel : .sessionsClose)) {
                    if isSelecting { archiveSelection.cancel() } else { dismiss() }
                }
                .disabled(archiveSelection.isRunning)
                .frame(width: headerActionWidth, alignment: .leading)

                Spacer()

                Text(isSelecting ? L10n.t(.sessionsBatchSelected, archiveSelection.selected.count) : L10n.t(.sessionsTitle))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DesignColors.Neutral.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer()

                HStack(spacing: 8) {
                    if !isSelecting {
                        SessionArchiveSelectButton(disabled: !state.isConnected || activeNodes.isEmpty || mutatingSessionID != nil) {
                            activeExpanded = true
                            archiveSelection.begin(in: state.sessionArchiveScope)
                        }
                        Button {
                            Task {
                                await state.createSession()
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .regular))
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
                .frame(width: headerActionWidth, alignment: .trailing)
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.top, DesignSpacing.lg)
            .padding(.bottom, DesignSpacing.md)

            Group {
                if activeNodes.isEmpty && archivedNodes.isEmpty && !state.mayHaveUnloadedArchivedSessions {
                    ContentUnavailableView(
                        L10n.t(.sessionsEmptyTitle),
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text(L10n.t(.sessionsEmptyDescription))
                    )
                } else {
                    List {
                        SessionSectionHeader(title: L10n.t(.sessionsActive), isExpanded: activeExpanded, canToggle: !isSelecting) {
                            activeExpanded.toggle()
                        }

                        if activeExpanded || isSelecting {
                            sessionNodes(activeNodes, archived: false, presentations: presentations)
                        }

                        if !isSelecting {
                            SessionSectionHeader(title: L10n.t(.sessionsArchived), isExpanded: archivedExpanded) {
                                archivedExpanded.toggle()
                            }
                            if archivedExpanded {
                                sessionNodes(archivedNodes, archived: true, presentations: presentations)
                                ArchivedSessionsPagingRow(state: state)
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
                    .accessibilityIdentifier("session-list")
                    .refreshable {
                        guard !archiveSelection.isRunning else { return }
                        await state.refreshSessions()
                        if archivedExpanded { await state.loadArchivedSessions(reset: true) }
                    }
                    .disabled(archiveSelection.isRunning)
                }
            }
            SessionArchiveBar(selection: archiveSelection, state: state)
        }
        .modifier(SessionArchiveSuccessOverlay(selection: archiveSelection))
        .interactiveDismissDisabled(archiveSelection.isRunning)
        .onChange(of: state.sessionArchiveScope) { archiveSelection.scopeChanged() }
        .onChange(of: archivedExpanded) { _, expanded in
            if expanded { Task { await state.loadArchivedSessions() } }
        }
        .onChange(of: state.archivedSessionDirectory) {
            if archivedExpanded { Task { await state.loadArchivedSessions() } }
        }
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
        .task {
            await state.refreshSessions()
        }
        .modifier(SessionStatusRefresh(state: state))
        .alert(L10n.t(.chatCreateDisabledHint), isPresented: $showCreateDisabledAlert) {
            Button(L10n.t(.commonOk)) {}
        }
    }

    private func selectSession(_ session: Session) {
        state.selectSession(session)
        dismiss()
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
                    hasChildren: !node.children.isEmpty || state.mayHaveUnloadedChildren(session),
                    isCollapsed: !state.expandedSessionIDs.contains(session.id),
                    archiveChecked: isSelecting ? archiveSelection.selected.contains(session.id) : nil,
                    onSelect: {
                        if isSelecting { archiveSelection.toggle(session.id) } else { selectSession(session) }
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

/// Archived rows page in from the server once the section is open. The
/// legacy window carries archived rows itself and shows nothing here.
struct ArchivedSessionsPagingRow: View {
    let state: AppState

    var body: some View {
        if state.isLoadingArchivedSessions {
            LoadMoreSessionsRow(isLoading: true) {}
        } else if state.canLoadMoreArchivedSessions {
            LoadMoreSessionsRow(isLoading: false) {
                Task { await state.loadArchivedSessions() }
            }
        }
    }
}

struct SessionSectionHeader: View {
    let title: String
    let isExpanded: Bool
    var canToggle = true
    let onToggle: () -> Void
    var archiveAccessory: SessionArchiveSelectButton? = nil

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Button(action: onToggle) {
                HStack(spacing: DesignSpacing.sm) {
                    Text(title)
                        .font(DesignTypography.meta.weight(.semibold))
                        .foregroundStyle(DesignColors.Neutral.textSecondary)

                    Spacer()

                    if canToggle {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(DesignTypography.micro.weight(.semibold))
                            .foregroundStyle(DesignColors.Neutral.textTertiary)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canToggle)
            archiveAccessory
        }
        .textCase(nil)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

struct LoadMoreSessionsRow: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSpacing.sm) {
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "ellipsis.circle")
                    Text(L10n.t(.sessionsLoadMore))
                }
                Spacer()
            }
            .font(DesignTypography.body.weight(.semibold))
            .foregroundStyle(DesignColors.Brand.primary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

struct SessionRowView: View {
    let session: Session
    let status: SessionStatus?
    var indicator: SessionIndicator? = nil
    var presentation: SessionIndicatorPresentation? = nil
    let isSelected: Bool
    let isMutating: Bool
    let isArchived: Bool
    var depth: Int = 0
    var hasChildren: Bool = false
    var isCollapsed: Bool = false
    var archiveChecked: Bool? = nil
    var titleLineLimit: Int = 1
    let onSelect: () -> Void
    var onToggleCollapse: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var scaledIndicatorColumnWidth = DesignControls.indicatorColumnWidth

    private var indicatorColumnWidth: CGFloat {
        min(max(scaledIndicatorColumnWidth, DesignControls.indicatorColumnWidth), DesignControls.indicatorColumnWidthMaximum)
    }
    
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
        HStack(alignment: .center, spacing: DesignSpacing.sm) {
            if let archiveChecked {
                Image(systemName: archiveChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(archiveChecked ? DesignColors.Brand.primary : DesignColors.Neutral.textSecondary)
                    .accessibilityHidden(true)
            }
            if hasChildren {
                Button {
                    onToggleCollapse?()
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(DesignTypography.micro)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -16)
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

            ZStack {
                if let indicator {
                    SessionIndicatorDot(indicator: indicator)
                        .accessibilityIdentifier("session-indicator-\(session.id)")
                }
            }
            .frame(width: indicatorColumnWidth)

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(session.title.isEmpty ? L10n.t(.sessionsUntitled) : session.title)
                    .font(depth > 0 ? DesignTypography.body : DesignTypography.headline)
                    .foregroundStyle(titleColor(depth: depth, isBusy: isBusy))
                    .lineLimit(titleLineLimit)
                    .fixedSize(horizontal: false, vertical: titleLineLimit > 1)
                    .accessibilityIdentifier("session-title-\(session.id)")

                HStack(spacing: DesignSpacing.sm) {
                    Text(formattedDate(session.time.updated))
                        .font(DesignTypography.meta)
                        .foregroundStyle(isArchived ? DesignColors.Neutral.textTertiary : DesignColors.Neutral.textSecondary)
                        .accessibilityIdentifier("session-time-\(session.id)")

                    if let presentation, presentation.hasDetails {
                        SessionExecutionDetails(presentation: presentation)
                            .accessibilityIdentifier("session-summary-\(session.id)")
                    }
                }
            }

            Spacer()

            if isMutating {
                ProgressView()
                    .controlSize(.small)
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
        .accessibilityAddTraits(archiveChecked == true ? .isSelected : [])
        .accessibilityIdentifier("session-row-\(session.id)")
    }

    private func formattedDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = L10n.currentLocale
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func titleColor(depth: Int, isBusy: Bool) -> Color {
        if isArchived { return DesignColors.Neutral.textSecondary }
        if depth > 0 { return DesignColors.Neutral.textSecondary }
        return DesignColors.Neutral.text
    }
}

struct SessionIndicatorDot: View {
    let indicator: SessionIndicator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @ScaledMetric(relativeTo: .headline) private var unreadSize = DesignControls.indicatorSize
    @ScaledMetric(relativeTo: .headline) private var emphasisSize = DesignControls.indicatorSizeEmphasis

    private var diameter: CGFloat {
        switch indicator {
        case .unread, .running:
            min(max(unreadSize, DesignControls.indicatorSize), DesignControls.indicatorSizeMaximum)
        case .needsYou, .failed:
            min(max(emphasisSize, DesignControls.indicatorSizeEmphasis), DesignControls.indicatorSizeEmphasisMaximum)
        }
    }

    private var color: Color {
        switch indicator {
        case .needsYou: DesignColors.Brand.gold
        case .failed: DesignColors.SessionIndicator.failed
        case .unread: DesignColors.Brand.primary
        case .running: colorScheme == .dark ? DesignColors.SessionIndicator.runningDark : DesignColors.SessionIndicator.runningLight
        }
    }

    private var label: String {
        switch indicator {
        case .needsYou: L10n.t(.sessionsIndicatorNeedsYou)
        case .failed: L10n.t(.sessionsIndicatorFailed)
        case .unread: L10n.t(.sessionsIndicatorUnread)
        case .running: SessionIndicatorCopy.executing
        }
    }

    var body: some View {
        Group {
            if indicator == .running {
                RunningIndicatorLayer(color: UIColor(color), animates: animates)
            } else {
            Circle()
                .fill(color)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private var animates: Bool {
        Self.shouldAnimate(isRunning: indicator == .running, visible: visible, active: scenePhase == .active, reduceMotion: effectiveReduceMotion)
    }

    private var effectiveReduceMotion: Bool {
        #if DEBUG
        reduceMotion || ProcessInfo.processInfo.arguments.contains("UITEST_REDUCE_MOTION")
        #else
        reduceMotion
        #endif
    }

    static func shouldAnimate(isRunning: Bool, visible: Bool, active: Bool, reduceMotion: Bool) -> Bool {
        isRunning && visible && active && !reduceMotion
    }

    static func runningAnimation() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1.0, 0.40, 1.0]
        animation.keyTimes = [0, 0.5, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        animation.duration = 2.6
        animation.repeatCount = .infinity
        animation.beginTime = CACurrentMediaTime() - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6)
        return animation
    }
}

/// Core Animation owns the frames; no SwiftUI state or tree derivation ticks.
private struct RunningIndicatorLayer: UIViewRepresentable {
    final class DotView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }
    }
    let color: UIColor
    let animates: Bool
    func makeUIView(context: Context) -> UIView {
        let view = DotView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        view.backgroundColor = color
        view.layer.masksToBounds = true
        view.layer.cornerCurve = .circular
        if animates && view.layer.animation(forKey: "running") == nil {
            let animation = SessionIndicatorDot.runningAnimation()
            view.layer.add(animation, forKey: "running")
        } else if !animates {
            view.layer.removeAnimation(forKey: "running")
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        view.layer.removeAllAnimations()
    }
}

enum SessionIndicatorCopy {
    private static var chinese: Bool { L10n.currentLocale.identifier.hasPrefix("zh") }
    static var executing: String { chinese ? "执行未结束" : "Execution active" }
    static var syncing: String { chinese ? "状态待同步" : "Status awaiting sync" }
    static func descendants(_ count: Int) -> String {
        chinese ? "\(count) 个后代执行未结束" : "\(count) descendants active"
    }
}

/// List-only compact detail, with a complete localized spoken count.
struct SessionExecutionDetails: View {
    let presentation: SessionIndicatorPresentation

    private var countLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
            Text(String(presentation.activeDescendantCount)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SessionIndicatorCopy.descendants(presentation.activeDescendantCount))
    }

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            if let text = presentation.statusText { Text(text).lineLimit(2) }
            if presentation.activeDescendantCount > 0 {
                countLabel
            }
        }
        .font(DesignTypography.meta)
        .foregroundStyle(DesignColors.Neutral.textSecondary)
    }
}

/// Shared sync boundary; simultaneous sidebar/composer tasks coalesce in AppState.
struct SessionStatusRefresh: ViewModifier {
    let state: AppState
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.task(id: "\(scenePhase)-\(state.currentHostProfileID)-\(state.effectiveProjectDirectory ?? state.serverCurrentProjectWorktree ?? "")") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await state.refreshVisibleSessionStatus()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: "\(scenePhase)-\(state.currentHostProfileID)-\(state.effectiveProjectDirectory ?? state.serverCurrentProjectWorktree ?? "")") {
            guard scenePhase == .active else { return }
            await state.runSessionStatusExpiryTicks()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                state.invalidateSessionStatusKnowledge()
            }
        }
    }
}

#if DEBUG
/// Synthetic, network-free visual evidence using production rows and composer.
struct SessionIndicatorFixtureView: View {
    @State private var state = makeState()
    @State private var showChat = ProcessInfo.processInfo.arguments.contains("UITEST_INDICATOR_COMPOSER")

    private static func makeState() -> AppState {
        let state = SessionScrollFixture.makeAppState()
        state.isConnected = true
        state.statusStreamConnected = true
        state.statusLastAttemptAt = .distantFuture
        func session(_ id: String, _ title: String, parent: String? = nil) -> Session {
            Session(id: id, slug: id, projectID: "fixture", directory: "/fixture", parentID: parent,
                    title: title, version: "1", time: .init(created: 0, updated: 200_000, archived: nil), share: nil, summary: nil)
        }
        state.sessions = [session("yellow", "Needs permission · child still active"),
                          session("red", "Unacknowledged failure · child active"),
                          session("hidden-yellow-child", "Permission branch", parent: "yellow"),
                          session("hidden-red-child", "Executing branch", parent: "red"),
                          session("running", "Parent and descendant executing"),
                          session("child", "Nested retry", parent: "running"),
                          session("blue", "Stopped · unread update"),
                          session("unknown", "Status not yet confirmed")]
        for i in 0..<9 { state.sessions.append(session("extra-\(i)", "Background session \(i + 1)")) }
        for session in state.sessions {
            state.statusConfirmedAt[session.id] = Date()
            state.sessionStatuses[session.id] = SessionStatus(type: "busy", attempt: nil, message: nil, next: nil)
        }
        state.sessionStatuses["blue"] = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)
        state.sessionStatuses["child"] = SessionStatus(type: "retry", attempt: 2, message: nil, next: nil)
        state.statusConfirmedAt["unknown"] = nil
        state.readStateStore.markFailed(sessionID: "red", at: Date())
        state.pendingPermissions = [PendingPermission(sessionID: "yellow", permissionID: "fixture", permission: "edit", patterns: [], allowAlways: false, tool: nil, description: "Synthetic permission")]
        state.currentSessionID = "running"
        if ProcessInfo.processInfo.arguments.contains("UITEST_INDICATOR_DISCONNECTED") { state.disconnectSSE() }
        return state
    }

    var body: some View {
        let presentations = state.sessionIndicatorPresentations
        NavigationStack {
            Group {
                if showChat {
                    ChatTabView(state: state)
                } else {
                    List(state.sessions.filter { !$0.id.hasPrefix("hidden-") }) { session in
                        SessionRowView(session: session, status: state.sessionStatuses[session.id],
                                       indicator: presentations[session.id]?.indicator,
                                       presentation: presentations[session.id],
                                       isSelected: session.id == state.currentSessionID, isMutating: false,
                                       isArchived: false, depth: session.parentID == nil ? 0 : 1,
                                       hasChildren: session.id == "running", onSelect: {})
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Offline indicator fixture")
            .toolbar {
                Button(showChat ? "List" : "Composer") { showChat.toggle() }
                    .accessibilityIdentifier("indicator-fixture-toggle")
                Button("Disconnect") { state.disconnectSSE() }
                    .accessibilityIdentifier("indicator-fixture-disconnect")
            }
        }
    }
}
#endif
