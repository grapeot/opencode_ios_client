//
//  ChatToolbarView.swift
//  OpenCodeClient
//

import os
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
            state.rebuildPickerModelItems(reason: "open")
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
            ModelConfigSheet(state: state, isPresented: $showConfigSheet)
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

private struct ModelConfigSheet: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool

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
                    Button(L10n.t(.appDone)) {
                        isPresented = false
                    }
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
                Button {
                    isPresented = false
                    state.revealModelShortlistInSettings()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text(L10n.t(.configureModelEmptyShortlist))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.forward.circle.fill")
                            .font(.title2)
                    }
                    .foregroundStyle(DesignColors.Brand.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("configure-empty-shortlist")
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
        }
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
        case .model(let index, let preset):
            modelRow(index: index, preset: preset)
        }
    }

    private func providerHeaderRow(_ providerID: String) -> some View {
        let _ = AppState.logger.notice("DIAG render-header=\(providerID, privacy: .public)")
        return Text(state.providerDisplayNames[providerID] ?? providerID)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.top, 4)
            .accessibilityIdentifier("model-picker-header-\(providerID)")
    }

    private func modelRow(index: Int, preset: ModelPreset) -> some View {
        Button {
            state.setSelectedModelIndex(index)
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
                if state.selectedModelIndex == index {
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
