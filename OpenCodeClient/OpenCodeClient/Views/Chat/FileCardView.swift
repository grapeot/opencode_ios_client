//
//  FileCardView.swift
//  OpenCodeClient
//

import SwiftUI

/// A compact file card for file-operation tools (patch / edit / write / read).
/// Quiet Tech styling: neutral surface body, single blue accent on the file icon,
/// monospace basename, chevron to navigate. Fits the 2-up (iPhone) / 3-up (iPad)
/// card grid alongside the merged "N tool calls" row.
struct FileCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let part: Part
    let workspaceDirectory: String?
    let onOpenResolvedPath: (String) -> Void
    let onOpenFilesTab: () -> Void
    @State private var showOpenFileSheet = false

    /// Prefer an explicit path; fall back to the first navigable path so the card
    /// always has a label even when metadata.path is absent.
    private var displayPath: String? {
        if let p = part.metadata?.path, !p.isEmpty { return p }
        if let p = part.state?.pathFromInput, !p.isEmpty { return p }
        return part.filePathsForNavigation.first
    }

    private var basename: String {
        guard let path = displayPath, !path.isEmpty else { return "file" }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    var body: some View {
        let accent = DesignColors.Brand.primary
        Button {
            let paths = part.filePathsForNavigation
            if paths.count == 1 {
                openFile(paths[0])
            } else if paths.count > 1 {
                showOpenFileSheet = true
            } else {
                onOpenFilesTab()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(accent)
                    .font(.caption)
                Text(basename)
                    .font(DesignTypography.microMono)
                    .foregroundStyle(DesignColors.Neutral.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(DesignTypography.micro)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSpacing.cardPadding)
            .background(DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for: colorScheme)))
            .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolcard.file.\(basename)")
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
        let p = PathNormalizer.resolveWorkspaceRelativePath(raw, workspaceDirectory: workspaceDirectory)
        guard !p.isEmpty else { return }
        onOpenResolvedPath(p)
    }
}
