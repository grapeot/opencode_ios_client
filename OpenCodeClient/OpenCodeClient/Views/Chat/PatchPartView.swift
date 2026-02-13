//
//  PatchPartView.swift
//  OpenCodeClient
//

import SwiftUI

struct PatchPartView: View {
    let part: Part
    @Bindable var state: AppState
    @State private var showOpenFileSheet = false

    var body: some View {
        let fileCount = part.files?.count ?? 0
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
                    .foregroundStyle(.orange.opacity(0.7))
                Text("\(fileCount) file\(fileCount == 1 ? "" : "s") changed")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .confirmationDialog("打开文件", isPresented: $showOpenFileSheet) {
            ForEach(part.filePathsForNavigation, id: \.self) { path in
                Button("在 File Tree 中打开 \(path)") {
                    openFile(path)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择要打开的文件")
        }
    }

    private func openFile(_ path: String) {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = PathNormalizer.resolveWorkspaceRelativePath(raw, workspaceDirectory: state.currentSession?.directory)
        guard !p.isEmpty else { return }
        state.fileToOpenInFilesTab = p
        state.selectedTab = 1
    }
}
