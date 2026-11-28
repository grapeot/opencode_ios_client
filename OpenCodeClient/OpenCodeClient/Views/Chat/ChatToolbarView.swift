//
//  ChatToolbarView.swift
//  OpenCodeClient
//

import SwiftUI
import UIKit

struct ChatToolbarView: View {
    @Bindable var state: AppState
    @Binding var showSessionList: Bool
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String
    var showSettingsInToolbar: Bool
    var showSessionListInToolbar: Bool = true
    var showCreateSessionInToolbar: Bool = true
    var onSettingsTap: (() -> Void)?
    var onFilesTap: (() -> Void)?
    var onRestoreSessions: (() -> Void)?
    var filesPinned: Binding<Bool>?
    
    @State private var showCreateDisabledAlert = false
    @State private var modelConfig: ModelConfigPresentation?
    @State private var showTodoPanel = false
    @State private var showQuotaPanel = false
    @State private var isOuterDisplay = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.effectiveLayout) private var effectiveLayout

    private var showsLayoutShortcut: Bool { sizeClass == .regular || onFilesTap != nil }
    
    var body: some View {
        platformBar
            .sheet(item: $modelConfig) { presentation in
                ModelConfigSheet(state: state, presentation: presentation) {
                    modelConfig = nil
                }
            }
    }

    @ViewBuilder
    private var platformBar: some View {
        // SwiftUI 8.0.85.29 is the first supported iOS 27.1 SDK module.
        #if canImport(SwiftUI, _version: 8.0.85.29)
        Group {
            if #available(iOS 27.1, *), isOuterDisplay {
                Color.clear.frame(height: 0)
                    .accessibilityHidden(true)
                    .toolbar { outerDisplayItems }
                    .toolbarVerticalCompressionBehavior(.prefersTabBar)
                    .sheet(isPresented: $showTodoPanel) { todoPanel }
                    .sheet(isPresented: $showQuotaPanel) {
                        AIUsageQuotaSheet(state: state, isPresented: $showQuotaPanel)
                    }
                    .alert(L10n.t(.chatCreateDisabledHint), isPresented: $showCreateDisabledAlert) {
                        Button(L10n.t(.commonOk)) {}
                    }
                    .task(id: state.aiUsageDashboardURL) {
                        guard state.isAIUsageQuotaConfigured else { return }
                        await state.refreshAIUsageQuotas()
                    }
            } else {
                horizontalBar
            }
        }
        .background {
            if #available(iOS 27.1, *) {
                ChatToolbarDisplayProbe(isOuterDisplay: $isOuterDisplay)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        #else
        horizontalBar
        #endif
    }

    private var horizontalBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSpacing.md) {
                sessionButtons
                Spacer(minLength: 0)
                layoutButton
                configButton
                AIUsageQuotaButton(state: state)
                todoButton
                ContextUsageButton(state: state)
                settingsButton
            }

            VStack(spacing: DesignSpacing.xs) {
                HStack(spacing: DesignSpacing.md) {
                    sessionButtons
                    Spacer(minLength: 0)
                    layoutButton
                    todoButton
                    ContextUsageButton(state: state)
                    settingsButton
                }
                HStack(spacing: DesignSpacing.md) {
                    configButton
                    Spacer(minLength: 0)
                    AIUsageQuotaButton(state: state)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, LayoutConstants.Spacing.spacious)
        .padding(.vertical, LayoutConstants.MessageList.verticalPadding)
    }

    #if canImport(SwiftUI, _version: 8.0.85.29)
    @available(iOS 27.1, *)
    @ToolbarContentBuilder
    private var outerDisplayItems: some ToolbarContent {
        if let onRestoreSessions {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onRestoreSessions) {
                    Label(L10n.t(.sidebarShowSessions), systemImage: "sidebar.left")
                }
            }
            .axisBehavior(.verticalPreferred)
        }
        if showSessionListInToolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSessionList = true } label: {
                    Label(L10n.t(.sessionsTitle), systemImage: "list.bullet")
                }
                .accessibilityIdentifier("chat-toolbar-session-list")
            }
            .axisBehavior(.verticalPreferred)
        }
        if showCreateSessionInToolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if state.canCreateSession { Task { await state.createSession() } }
                    else { showCreateDisabledAlert = true }
                } label: {
                    Label(L10n.t(.carNewSession), systemImage: "plus")
                }
                .accessibilityIdentifier("chat-toolbar-create-session")
            }
            .axisBehavior(.verticalPreferred)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: openModelConfig) {
                Label(state.selectedModel?.shortName ?? L10n.t(.configureModel), systemImage: "cpu")
            }
            .accessibilityIdentifier("chat-toolbar-model")
        }
        .axisBehavior(.verticalPreferred)
        .visibilityPriority(.high)
        ToolbarItem(placement: .topBarTrailing) {
            ContextUsageButton(state: state)
        }
        .axisBehavior(.verticalPreferred)
        .visibilityPriority(.high)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showTodoPanel = true } label: {
                    Label(L10n.t(.todoPanelTitle), systemImage: "checklist")
                }
                .accessibilityValue(todoBadge)
                .accessibilityIdentifier("chat-toolbar-todo")
                Button { beginRename() } label: {
                    Label(L10n.t(.chatRenameSession), systemImage: "pencil")
                }
                if state.isAIUsageQuotaConfigured, state.selectedModel?.primaryQuotaKey != nil {
                    Button {
                        showQuotaPanel = true
                        Task { await state.refreshAIUsageQuotas(force: true) }
                    } label: {
                        Label(L10n.t(.quotaTitle), systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .accessibilityIdentifier("chat-toolbar-quota")
                }
                layoutButton
                settingsButton
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel(L10n.t(.chatMoreActions))
            }
            .accessibilityIdentifier("chat-toolbar-more")
        }
        .axisBehavior(.verticalPreferred)
    }
    #endif
    
    // MARK: - Session Operation Buttons
    private var sessionButtons: some View {
        HStack(spacing: LayoutConstants.Toolbar.buttonSpacing) {
            if let onRestoreSessions {
                Button(action: onRestoreSessions) { Image(systemName: "sidebar.left") }
                    .accessibilityLabel(L10n.t(.sidebarShowSessions))
                    .accessibilityIdentifier("chat-restore-sessions")
            }
            if showSessionListInToolbar {
                Button {
                    showSessionList = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.body)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                }
                .accessibilityIdentifier("chat-toolbar-session-list")
            }

            Button {
                beginRename()
            } label: {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(DesignColors.Neutral.textSecondary)
            }

            if showCreateSessionInToolbar {
                Button {
                    Task { await state.createSession() }
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundColor(state.canCreateSession ? DesignColors.Brand.primary : DesignColors.Neutral.textTertiary)
                }
                .disabled(!state.canCreateSession)
                .accessibilityIdentifier("chat-toolbar-create-session")
            }

            if showCreateSessionInToolbar, !state.canCreateSession {
                Button {
                    showCreateDisabledAlert = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(DesignColors.Neutral.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .alert(L10n.t(.chatCreateDisabledHint), isPresented: $showCreateDisabledAlert) {
            Button(L10n.t(.commonOk)) {}
        }
    }

    private func beginRename() {
        renameText = state.currentSession?.title ?? ""
        showRenameAlert = true
    }
    
    @ViewBuilder
    private var layoutButton: some View {
        if showsLayoutShortcut {
            LayoutPreferenceMenu(state: state, onFilesTap: onFilesTap, filesPinned: filesPinned)
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if showSettingsInToolbar, let onSettingsTap {
            Button(action: onSettingsTap) {
                Image(systemName: "gear")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
    
    private var configButton: some View {
        Button(action: openModelConfig) {
            HStack(spacing: 4) {
                Text(state.selectedModel?.shortName ?? L10n.t(.configureModel))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(DesignColors.Brand.primary)
            .overlay(
                Capsule()
                    .stroke(DesignColors.Brand.primary.opacity(0.30), lineWidth: 1)
            )
        }
        .accessibilityIdentifier("chat-toolbar-model")
    }

    private func openModelConfig() {
        state.rebuildPickerModelItems(reason: "open")
        modelConfig = ModelConfigPresentation(
            closesOnModelSelection: effectiveLayout == .compact,
            hostID: state.currentHostProfileID,
            sessionID: state.currentSessionID
        )
    }

    // MARK: - Todo Button & Panel

    private var currentTodos: [TodoItem] {
        guard let sessionID = state.currentSessionID else { return [] }
        return state.sessionTodos[sessionID] ?? []
    }

    private var todoBadge: String {
        let total = currentTodos.count
        guard total > 0 else { return "" }
        let completed = currentTodos.count { $0.isCompleted }
        return "\(completed)/\(total)"
    }

    private var todoButton: some View {
        Button {
            showTodoPanel = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption)
                if !todoBadge.isEmpty {
                    Text(todoBadge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .accessibilityIdentifier("chat-toolbar-todo")
        .popover(isPresented: $showTodoPanel) { todoPanel }
    }

    private var todoPanel: some View {
        NavigationStack {
            todoPanelContent
                .navigationTitle(L10n.t(.todoPanelTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t(.appDone)) { showTodoPanel = false }
                    }
                }
        }
        .frame(idealWidth: 320, idealHeight: 400)
    }

    private var todoPanelContent: some View {
        TodoListPanel(todos: currentTodos)
    }
}

/// The public screen API has no outer/inner role. Match the Duo cover panel's
/// native resolution (Apple tech specs), not window size or toolbar direction.
private struct ChatToolbarDisplayProbe: UIViewRepresentable {
    @Binding var isOuterDisplay: Bool

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = { outer in
            if isOuterDisplay != outer { isOuterDisplay = outer }
        }
        view.checkDisplay()
    }

    final class ProbeView: UIView {
        var onChange: ((Bool) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            checkDisplay()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            checkDisplay()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            checkDisplay()
        }

        func checkDisplay() {
            // SwiftUI can call this while updating UIViewRepresentable.
            DispatchQueue.main.async { [weak self] in
                guard let self, let scene = self.window?.windowScene else { return }
                let size = scene.screen.nativeBounds.size
                self.onChange?(scene.traitCollection.userInterfaceIdiom == .phone
                    && min(size.width, size.height) == 1398
                    && max(size.width, size.height) == 2034)
            }
        }
    }
}

private struct ModelConfigPresentation: Identifiable {
    let id = UUID()
    let closesOnModelSelection: Bool
    let hostID: UUID
    let sessionID: String?
}

private struct ModelConfigSheet: View {
    @Bindable var state: AppState
    let presentation: ModelConfigPresentation
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                modelSections
                agentSection
            }
            .navigationTitle(L10n.t(.configureTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.appDone), action: close)
                        .accessibilityIdentifier("model-config-done")
                }
            }
            .onAppear { state.rebuildPickerModelItems(reason: "appear") }
            .onChange(of: state.modelSearchText) { _, _ in
                state.rebuildPickerModelItems(reason: "search")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var modelSections: some View {
        if state.modelShortlist.isEmpty {
            Section(L10n.t(.configureModel)) {
                settingsJumpRow(
                    title: L10n.t(.configureModelEmptyShortlist),
                    systemImage: "plus.circle.fill",
                    identifier: "configure-empty-shortlist"
                )
            }
        } else {
            Section {
                TextField(L10n.t(.configureModelSearchPlaceholder), text: $state.modelSearchText)
                    .autocorrectionDisabled()
            }
            Section(L10n.t(.configureModel)) {
                ForEach(state.pickerModelItems) { item in
                    pickerItemRow(item)
                }
            }
            if state.pickerModelItems.isEmpty {
                Section {
                    Text(L10n.t(.configureModelNoMatches))
                        .foregroundColor(.secondary)
                }
            }
            Section {
                settingsJumpRow(
                    title: L10n.t(.configureModelEditShortlist),
                    systemImage: "list.bullet.rectangle",
                    identifier: "configure-edit-shortlist"
                )
            }
        }
    }

    private func settingsJumpRow(title: String, systemImage: String, identifier: String) -> some View {
        Button {
            close()
            state.revealModelShortlistInSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title2)
            }
            .foregroundStyle(DesignColors.Brand.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var agentSection: some View {
        Section(L10n.t(.configureAgent)) {
            if state.isLoadingAgents {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if state.visibleAgents.isEmpty {
                Text(L10n.t(.configureNoAgents))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(state.visibleAgents.enumerated()), id: \.element.id) { index, agent in
                    agentRow(index: index, agent: agent)
                }
            }
        }
    }

    @ViewBuilder
    private func pickerItemRow(_ item: ModelPickerItem) -> some View {
        switch item {
        case .providerHeader(let providerID):
            providerHeaderRow(providerID)
        case .model(_, let preset):
            modelRow(preset)
        }
    }

    private func providerHeaderRow(_ providerID: String) -> some View {
        Text(state.providerDisplayNames[providerID] ?? providerID)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.top, 4)
            .accessibilityIdentifier("model-picker-header-\(providerID)")
    }

    private func modelRow(_ preset: ModelPreset) -> some View {
        Button {
            guard state.currentHostProfileID == presentation.hostID,
                  state.currentSessionID == presentation.sessionID else {
                close()
                return
            }
            guard let index = state.pickerModelPresets.firstIndex(where: { $0.id == preset.id }) else { return }
            state.setSelectedModelIndex(index)
            if presentation.closesOnModelSelection { close() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                    Text("\(state.providerDisplayNames[preset.providerID] ?? preset.providerID) / \(preset.modelID)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if state.selectedModel?.id == preset.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(DesignColors.Brand.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .accessibilityIdentifier("model-picker-row-\(preset.providerID)-\(preset.modelID)")
    }

    private func agentRow(index: Int, agent: AgentInfo) -> some View {
        Button {
            state.setSelectedAgentIndex(index)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(agent.shortName)
                    if let desc = agent.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if state.selectedAgentIndex == index {
                    Image(systemName: "checkmark")
                        .foregroundColor(DesignColors.Brand.primary)
                }
            }
        }
        .foregroundColor(.primary)
    }
}

struct LayoutPreferenceMenu: View {
    @Bindable var state: AppState
    var onFilesTap: (() -> Void)?
    var filesPinned: Binding<Bool>?
    @State private var showChoices = false

    var body: some View {
        Group {
            if let onFilesTap {
                Menu {
                    Picker(L10n.t(.settingsLayout), selection: $state.layoutPreference) {
                        Text(L10n.t(.settingsLayoutAutomatic)).tag(LayoutPreference.automatic)
                        Text(L10n.t(.settingsLayoutFocus)).tag(LayoutPreference.focus)
                    }
                    Section {
                        Button(L10n.t(.workspaceShowFiles), systemImage: "folder", action: onFilesTap)
                        if let filesPinned {
                            Toggle(L10n.t(.workspacePinFiles), isOn: filesPinned)
                        }
                    }
                } label: {
                    icon
                }
            } else {
                Button { showChoices = true } label: { icon }
                    .confirmationDialog(L10n.t(.settingsLayout), isPresented: $showChoices, titleVisibility: .visible) {
                        Button(L10n.t(.settingsLayoutAutomatic)) { state.layoutPreference = .automatic }
                        Button(L10n.t(.settingsLayoutFocus)) { state.layoutPreference = .focus }
                        Button(L10n.t(.commonCancel), role: .cancel) {}
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("layout-preference-menu")
        .accessibilityLabel(L10n.t(.settingsLayout))
    }

    private var icon: some View {
        Image(systemName: state.layoutPreference == .focus ? "iphone" : "rectangle.split.3x1")
            .font(.body)
            .frame(width: ComposerHitTarget.minimum, height: ComposerHitTarget.minimum)
            .contentShape(Rectangle())
    }
}
