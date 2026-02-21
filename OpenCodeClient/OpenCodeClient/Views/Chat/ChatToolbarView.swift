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
    var onSettingsTap: (() -> Void)?
    
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
            Button {
                showSessionList = true
            } label: {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.accentColor)
            }
            
            Button {
                renameText = state.currentSession?.title ?? ""
                showRenameAlert = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.accentColor)
            }
            
            Button {
                Task {
                    await state.createSession()
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    // MARK: - Right Side Buttons (Model + Agent + Settings)
    private var rightButtons: some View {
        HStack(spacing: LayoutConstants.Toolbar.modelButtonSpacing) {
            modelMenu
            agentMenu
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
    
    // MARK: - Model Selection Menu
    private var modelMenu: some View {
        Menu {
            ForEach(Array(state.modelPresets.enumerated()), id: \.element.id) { index, preset in
                Button {
                    state.setSelectedModelIndex(index)
                } label: {
                    HStack {
                        Text(preset.displayName)
                        if state.selectedModelIndex == index {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(useCompactLabels ? (state.selectedModel?.shortName ?? "Model") : (state.selectedModel?.displayName ?? "Model"))
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.accentColor.gradient)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
    }
    
    // MARK: - Agent Selection Menu
    private var agentMenu: some View {
        Menu {
            if state.isLoadingAgents {
                ProgressView()
            } else if state.visibleAgents.isEmpty {
                Text("No agents available")
            } else {
                ForEach(Array(state.visibleAgents.enumerated()), id: \.element.id) { index, agent in
                    Button {
                        state.setSelectedAgentIndex(index)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(agent.shortName)
                                if !useCompactLabels, let desc = agent.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            if state.selectedAgentIndex == index {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(useCompactLabels ? (state.selectedAgent?.shortName ?? "Agent") : (state.selectedAgent?.name ?? "Agent"))
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.systemGray5))
            .foregroundColor(.secondary)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
    }
}
