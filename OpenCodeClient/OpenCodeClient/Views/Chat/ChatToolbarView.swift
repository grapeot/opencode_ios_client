//
//  ChatToolbarView.swift
//  OpenCodeClient
//

import SwiftUI

struct ChatToolbarView: View {
    @Bindable var state: AppState
    @Binding var showSessionList: Bool
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String
    var showSettingsInToolbar: Bool
    var showSessionListInToolbar: Bool = true
    var showCreateSessionInToolbar: Bool = true
    var onSettingsTap: (() -> Void)?
    
    @State private var showCreateDisabledAlert = false
    @State private var showConfigSheet = false
    @State private var showTodoPanel = false
    @State private var modelSearchText = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var useCompactLabels: Bool {
#if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone
#else
        return false
#endif
    }
    
    var body: some View {
        HStack {
            sessionButtons
            Spacer()
            rightButtons
        }
        .padding(.horizontal, LayoutConstants.Spacing.spacious)
        .padding(.vertical, LayoutConstants.MessageList.verticalPadding)
    }
    
    // MARK: - Session Operation Buttons
    private var sessionButtons: some View {
        HStack(spacing: LayoutConstants.Toolbar.buttonSpacing) {
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
                renameText = state.currentSession?.title ?? ""
                showRenameAlert = true
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
    
    // MARK: - Right Side Buttons (Model + Agent + Settings)
    private var rightButtons: some View {
        HStack(spacing: DesignSpacing.md) {
            configButton
            AIUsageQuotaButton(state: state)
            todoButton
            ContextUsageButton(state: state)
            
            if showSettingsInToolbar, let onSettingsTap {
                Button {
                    onSettingsTap()
                } label: {
                    Image(systemName: "gear")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
    }
    
    private var configButton: some View {
        Button {
            showConfigSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(state.selectedModel?.shortName ?? L10n.t(.configureModel))
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2)
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
        .sheet(isPresented: $showConfigSheet) {
            NavigationStack {
                List {
                    // Sections are built inline (not inside a custom view) so
                    // List sees the section structure directly; wrapping
                    // Sections in an intermediate View renders them as one
                    // unstyled row (blank models, broken taps).
                    if state.dynamicModelPresets.isEmpty {
                        Section(L10n.t(.configureModel)) {
                            ForEach(Array(state.pickerModelPresets.enumerated()), id: \.element.id) { index, preset in
                                modelRow(index: index, preset: preset)
                            }
                        }
                    } else {
                        Section {
                            TextField(L10n.t(.configureModelSearchPlaceholder), text: $modelSearchText)
                                .autocorrectionDisabled()
                        }
                        ForEach(modelGroups, id: \.providerID) { group in
                            Section(
                                header: Text(state.providerDisplayNames[group.providerID] ?? group.providerID)
                            ) {
                                ForEach(group.entries, id: \.preset.id) { entry in
                                    modelRow(index: entry.index, preset: entry.preset)
                                }
                            }
                        }
                        if modelGroups.isEmpty {
                            Section {
                                Text(L10n.t(.configureModelNoMatches))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

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
                    }
                }
                .navigationTitle(L10n.t(.configureTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t(.appDone)) {
                            showConfigSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Model Picker

    /// Picker entries grouped by provider, each carrying its index into the
    /// FULL pickerModelPresets array (not the filtered one), so selection
    /// stays correct while a search filter is active.
    private var modelGroups: [(providerID: String, entries: [(index: Int, preset: ModelPreset)])] {
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Enumerate the full list first, then filter — indices stay stable.
        let filtered = state.pickerModelPresets.enumerated().filter { _, preset in
            query.isEmpty
                || preset.displayName.lowercased().contains(query)
                || preset.modelID.lowercased().contains(query)
                || preset.providerID.lowercased().contains(query)
        }
        var byProvider: [String: [(Int, ModelPreset)]] = [:]
        var order: [String] = []
        for (idx, preset) in filtered {
            let pid = preset.providerID
            if byProvider[pid] == nil { order.append(pid) }
            byProvider[pid]?.append((idx, preset))
        }
        return order.map { ($0, byProvider[$0] ?? []) }
    }

    private func modelRow(index: Int, preset: ModelPreset) -> some View {
        Button {
            state.setSelectedModelIndex(index)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                    if preset.displayName != preset.modelID {
                        Text(preset.modelID)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if state.selectedModelIndex == index {
                    Image(systemName: "checkmark")
                        .foregroundColor(DesignColors.Brand.primary)
                }
            }
        }
        .foregroundColor(.primary)
        .accessibilityIdentifier("model-picker-row-\(preset.providerID)-\(preset.modelID)")
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
        .popover(isPresented: $showTodoPanel) {
            NavigationStack {
                todoPanelContent
                    .navigationTitle(L10n.t(.todoPanelTitle))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.t(.appDone)) {
                                showTodoPanel = false
                            }
                        }
                    }
            }
            .frame(idealWidth: 320, idealHeight: 400)
        }
    }

    private var todoPanelContent: some View {
        TodoListPanel(todos: currentTodos)
    }
}
