//
//  FileCardView.swift
//  OpenCodeClient
//

import SwiftUI

/// A compact file card for file-operation tools (patch / edit / write / read).
/// Quiet Tech styling: neutral surface body, single blue accent on the file icon,
/// monospace basename, chevron to navigate. Fits the 2-up (iPhone) / 3-up (iPad)
/// card grid alongside the merged "N tool calls" row.
///
/// When the part is a `read` of a *directory* (the server reports
/// `<type>directory</type>` in its output), the card switches to a folder icon and
/// tapping it expands the directory contents inline — opening a folder in the file
/// preview never worked, so we render the `<entries>…</entries>` the server already
/// returned instead of making a new API call.
struct FileCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let part: Part
    let workspaceDirectory: String?
    let onOpenResolvedPath: (String) -> Void
    let onOpenFilesTab: () -> Void
    @State private var showOpenFileSheet = false
    @State private var showFolderSheet = false

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

    /// True when this read targeted a directory; flips icon + tap behavior.
    private var isDirectoryRead: Bool {
        ToolCardClassifier.isDirectoryRead(part)
    }

    private var folderEntries: [ToolCardClassifier.DirectoryEntry] {
        ToolCardClassifier.parseDirectoryEntries(part.toolOutput)
    }

    private var isReadOnlyFileTool: Bool {
        guard let tool = part.tool?.lowercased() else { return false }
        return ToolCardClassifier.readToolPrefixes.contains { tool.hasPrefix($0) }
    }

    private var fileAccessibilityIdentifier: String {
        isReadOnlyFileTool ? "toolcard.read.\(basename)" : "toolcard.write.\(basename)"
    }

    private var fileAccessibilityLabel: String {
        isReadOnlyFileTool ? "Read file \(basename)" : "Write file \(basename)"
    }

    private var fileAccent: Color {
        isReadOnlyFileTool ? DesignColors.Neutral.textSecondary : DesignColors.Brand.primary
    }

    var body: some View {
        if isDirectoryRead {
            folderCard
        } else {
            fileCard
        }
    }

    // MARK: - File card (unchanged behavior)

    private var fileCard: some View {
        return Button {
            let paths = part.filePathsForNavigation
            if paths.count == 1 {
                openFile(paths[0])
            } else if paths.count > 1 {
                showOpenFileSheet = true
            } else {
                onOpenFilesTab()
            }
        } label: {
            cardLabel(iconName: "doc.text", accent: fileAccent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(fileAccessibilityIdentifier)
        .accessibilityLabel(fileAccessibilityLabel)
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

    // MARK: - Folder card (directory read → show contents)

    private var folderCard: some View {
        return Button {
            showFolderSheet = true
        } label: {
            cardLabel(iconName: "folder.fill", accent: fileAccent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolcard.folder.\(basename)")
        .accessibilityLabel("Read directory \(basename)")
        .sheet(isPresented: $showFolderSheet) {
            FolderContentsSheet(
                folderName: basename,
                folderPath: displayPath,
                entries: folderEntries
            )
        }
    }

    private func cardLabel(iconName: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
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

    private func openFile(_ path: String) {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = PathNormalizer.resolveWorkspaceRelativePath(raw, workspaceDirectory: workspaceDirectory)
        guard !p.isEmpty else { return }
        onOpenResolvedPath(p)
    }
}

/// Sheet listing the contents of a read directory. Pure presentation over the
/// already-parsed `<entries>` — no network. Subdirectories sort above files,
/// each name keyed by its own folder/document icon.
private struct FolderContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let folderName: String
    let folderPath: String?
    let entries: [ToolCardClassifier.DirectoryEntry]

    private var sortedEntries: [ToolCardClassifier.DirectoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedEntries.isEmpty {
                    ContentUnavailableView(
                        "Empty folder",
                        systemImage: "folder",
                        description: Text("This directory has no entries.")
                    )
                } else {
                    List(sortedEntries) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                                .foregroundStyle(DesignColors.Brand.primary)
                                .font(.body)
                                .frame(width: 22)
                            Text(entry.name)
                                .font(DesignTypography.microMono)
                                .foregroundStyle(DesignColors.Neutral.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .accessibilityIdentifier("toolcard.folder.entry.\(entry.name)")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(folderName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.commonOk)) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("toolcard.folder.sheet.\(folderName)")
    }
}
