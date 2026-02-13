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
    
    private var useCompactModelLabels: Bool {
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
                Task { await state.summarizeSession() }
            } label: {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.accentColor)
            }
            .help("Compact session（压缩历史，避免 token 超限）")
            
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
    
    // MARK: - Right Side Buttons (Model + Settings)
    private var rightButtons: some View {
        HStack(spacing: LayoutConstants.Toolbar.modelButtonSpacing) {
            modelSelectionButtons
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
    
    // MARK: - Model Selection Buttons
    private var modelSelectionButtons: some View {
        ForEach(Array(state.modelPresets.enumerated()), id: \.element.id) { index, preset in
            Button {
                state.setSelectedModelIndex(index)
            } label: {
                Text(useCompactModelLabels ? preset.compactLabel : preset.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        state.selectedModelIndex == index
                            ? AnyShapeStyle(Color.accentColor.gradient)
                            : AnyShapeStyle(Color(.systemGray5))
                    )
                    .foregroundColor(state.selectedModelIndex == index ? .white : .secondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private extension ModelPreset {
    var compactLabel: String {
        switch modelID {
        case "gpt-5.2": return "GPT"
        case "gpt-5.3-codex": return "Codex"
        case "anthropic/claude-opus-4-6": return "Opus"
        case "glm-5": return "GLM"
        default:
            return displayName
        }
    }
}
