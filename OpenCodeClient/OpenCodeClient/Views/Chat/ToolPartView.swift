//
//  ToolPartView.swift
//  OpenCodeClient
//

import SwiftUI

struct ToolPartView: View {
    let part: Part
    @Bindable var state: AppState
    @State private var isExpanded: Bool
    @State private var showOpenFileSheet = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(part: Part, state: AppState) {
        self.part = part
        self.state = state
        self._isExpanded = State(initialValue: part.stateDisplay?.lowercased() == "running")
    }

    private var toolDisplayName: String {
        let raw = part.tool ?? "tool"
        if raw == "apply_patch" { return "patch" }
        return raw
    }

    private var toolAccentColor: Color {
        if part.tool == "todowrite" { return .green }
        return .accentColor
    }

    private var toolBackgroundColor: Color {
        toolAccentColor.opacity(0.07)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let reason = part.toolReason ?? part.metadata?.title, !reason.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.toolReason))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(reason)
                            .font(.caption2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if part.tool == "todowrite" {
                    let todos = part.toolTodos.isEmpty ? (state.sessionTodos[part.sessionID] ?? []) : part.toolTodos
                    if !todos.isEmpty {
                        TodoListInlineView(todos: todos)
                    }
                }
                if part.tool != "todowrite",
                   let input = part.toolInputSummary ?? part.metadata?.input,
                   !input.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.toolCommandInput))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(input)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let path = part.metadata?.path {
                    LabeledContent(L10n.t(.toolPath), value: path)
                }
                if part.tool != "todowrite",
                   let output = part.toolOutput,
                   !output.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.toolOutput))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(output)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !part.filePathsForNavigation.isEmpty {
                    ForEach(part.filePathsForNavigation, id: \.self) { path in
                        Button {
                            openFile(path)
                        } label: {
                            Label(L10n.toolOpenFileLabel(path: path), systemImage: "folder.badge.plus")
                                .font(.caption2)
                        }
                    }
                }
            }
            .font(.caption2)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(toolAccentColor)
                    .font(.caption)
                Text(toolDisplayName)
                    .fontWeight(.medium)
                    .foregroundStyle(toolAccentColor)
                if let reason = part.toolReason ?? part.metadata?.title, !reason.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(reason)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else if let status = part.stateDisplay, !status.isEmpty {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
                if part.stateDisplay?.lowercased() == "running" {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                Spacer()
                if !part.filePathsForNavigation.isEmpty {
                    Button {
                        if part.filePathsForNavigation.count == 1 {
                            openFile(part.filePathsForNavigation[0])
                        } else {
                            showOpenFileSheet = true
                        }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption2)
        }
        .onChange(of: part.stateDisplay) { _, newValue in
            if newValue?.lowercased() == "completed" {
                isExpanded = false
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(toolBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(toolAccentColor.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if !part.filePathsForNavigation.isEmpty {
                ForEach(part.filePathsForNavigation, id: \.self) { path in
                    Button(L10n.toolOpenFileLabel(path: path)) {
                        openFile(path)
                    }
                }
            }
        }
        .confirmationDialog(L10n.t(.toolOpenFile), isPresented: $showOpenFileSheet) {
            ForEach(part.filePathsForNavigation, id: \.self) { path in
                Button(L10n.toolOpenFileLabel(path: path)) {
                    openFile(path)
                }
            }
            Button(L10n.t(.commonCancel), role: .cancel) {}
        } message: {
            Text(L10n.t(.toolSelectFile))
        }
    }

    private func openFile(_ path: String) {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = PathNormalizer.resolveWorkspaceRelativePath(raw, workspaceDirectory: state.currentSession?.directory)
        guard !p.isEmpty else { return }
        if sizeClass == .regular {
            state.previewFilePath = p
            state.fileToOpenInFilesTab = nil
        } else {
            state.fileToOpenInFilesTab = p
            state.selectedTab = 1
        }
    }
}
