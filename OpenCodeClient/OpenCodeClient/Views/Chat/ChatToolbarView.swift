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

    /// `state.groupedModelPresetIndices` filtered by `modelSearchText`. A query matching the
    /// provider name (e.g. "anthropic") shows that provider's full lineup; otherwise it filters
    /// to models whose display name matches (e.g. "sonnet" across every provider that has one).
    /// Groups with zero matches are dropped entirely so search doesn't leave empty headers behind.
    private var filteredModelGroups: [(providerID: String, providerName: String, indices: [Int])] {
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return state.groupedModelPresetIndices }
        return state.groupedModelPresetIndices.compactMap { group in
            let indices = group.providerName.localizedCaseInsensitiveContains(query)
                ? group.indices
                : group.indices.filter { state.modelPresets[$0].displayName.localizedCaseInsensitiveContains(query) }
            guard !indices.isEmpty else { return nil }
            return (providerID: group.providerID, providerName: group.providerName, indices: indices)
        }
    }
    
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
                    Section(L10n.t(.configureModel)) {
                        ForEach(filteredModelGroups, id: \.providerID) { group in
                            if filteredModelGroups.count > 1 {
                                Text(group.providerName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            ForEach(group.indices, id: \.self) { index in
                                let preset = state.modelPresets[index]
                                Button {
                                    state.setSelectedModelIndex(index)
                                    showConfigSheet = false
                                } label: {
                                    HStack {
                                        Text(preset.displayName)
                                        Spacer()
                                        if state.selectedModelIndex == index {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(DesignColors.Brand.primary)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
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
                .searchable(text: $modelSearchText, prompt: L10n.t(.configureModelSearch))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t(.appDone)) {
                            showConfigSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .onDisappear { modelSearchText = "" }
        }
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
