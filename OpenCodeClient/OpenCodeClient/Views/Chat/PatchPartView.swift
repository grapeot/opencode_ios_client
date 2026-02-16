//
//  PatchPartView.swift
//  OpenCodeClient
//

import SwiftUI

struct PatchPartView: View {
    let part: Part
    @Bindable var state: AppState
    @State private var showOpenFileSheet = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let fileCount = part.files?.count ?? 0
        let accent = Color.orange
        Button {
            let paths = part.filePathsForNavigation
            if paths.count == 1 {
                openFile(paths[0])
            } else if paths.count > 1 {
                showOpenFileSheet = true
            } else {
                state.selectedTab = 1
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(accent)
                Text(L10n.patchFilesChanged(fileCount))
                    .fontWeight(.medium)
                    .foregroundStyle(accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(accent.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accent.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
