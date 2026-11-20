//
//  FileTreeView.swift
//  OpenCodeClient
//

import SwiftUI

struct FileTreeView: View {
    @Bindable var state: AppState
    @Environment(\.effectiveLayout) private var effectiveLayout
    @State private var isLoadingChildren: Set<String> = []

    /// Force iPad split behavior (preview in middle column instead of push).
    var forceSplitPreview: Bool = false
    var onFileSelect: ((String) -> Void)?

    /// Regular workspace previews in the middle column; compact pushes.
    private var useSplitPreview: Bool {
        onFileSelect != nil || forceSplitPreview || effectiveLayout == .regular
    }

    var body: some View {
        Group {
            switch state.fileSearchListState {
            case .tree:
                treeList
            case .loading:
                ProgressView(L10n.t(.appLoading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("file-search-loading")
            case .empty:
                ContentUnavailableView(L10n.t(.fileNoContent), systemImage: "magnifyingglass")
                    .accessibilityIdentifier("file-search-empty")
            case .failed(let message):
                ContentUnavailableView(
                    L10n.t(.appError),
                    systemImage: "exclamationmark.triangle",
                    description: Text(message ?? "")
                )
                .accessibilityIdentifier("file-search-failed")
            case .results(let paths):
                searchResultList(paths)
            }
        }
        .navigationDestination(for: String.self) { path in
            FileContentView(
                state: state,
                filePath: path,
                workspaceDirectory: pinnedPushWorkspace,
                boundSessionID: nil
            )
        }
        .onAppear {
            state.discardUnownedFileSearch()
        }
        .onChange(of: state.captureHostRequestSnapshot()) { _, _ in
            state.discardUnownedFileSearch()
            Task { await state.ensureFileRootMatchesCurrentScope() }
        }
        .onChange(of: state.effectiveProjectDirectory) { _, _ in
            state.discardUnownedFileSearch()
            Task { await state.ensureFileRootMatchesCurrentScope() }
        }
    }

    private var openedWorkspaceDirectory: String {
        state.effectiveProjectDirectory ?? ""
    }

    private var pinnedPushWorkspace: String {
        state.filesNavigationWorkspace ?? openedWorkspaceDirectory
    }

    private var treeList: some View {
        List {
            ForEach(visibleNodes, id: \.path) { item in
                if item.node.type == "directory" {
                    DirectoryRow(
                        state: state,
                        node: item.node,
                        indent: item.indent,
                        isLoading: isLoadingChildren.contains(item.node.path))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await loadAndExpand(item.node.path) }
                    }
                } else if useSplitPreview {
                    Button {
                        openFile(item.node.path)
                    } label: {
                        FileRow(
                            node: item.node,
                            indent: item.indent,
                            status: state.fileStatusMap[item.node.path])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("file-tree-row-\(item.node.path)")
                } else {
                    NavigationLink(value: item.node.path) {
                        FileRow(
                            node: item.node,
                            indent: item.indent,
                            status: state.fileStatusMap[item.node.path])
                    }
                    .accessibilityIdentifier("file-tree-row-\(item.node.path)")
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("file-tree")
        .onAppear {
            Task { await state.ensureFileRootMatchesCurrentScope() }
        }
        .refreshable {
            await state.loadFileTree()
            await state.loadFileStatus()
        }
    }

    private func searchResultList(_ paths: [String]) -> some View {
        List {
            ForEach(paths, id: \.self) { path in
                if useSplitPreview {
                    Button {
                        openFile(path)
                    } label: {
                        SearchResultRow(path: path)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("file-search-result-\(path)")
                } else {
                    NavigationLink(value: path) {
                        SearchResultRow(path: path)
                    }
                    .accessibilityIdentifier("file-search-result-\(path)")
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("file-search-results")
    }

    private func openFile(_ path: String) {
        if let onFileSelect { onFileSelect(path) }
        else { state.presentFilesColumnPreview(path: path, workspaceDirectory: openedWorkspaceDirectory) }
    }

    private var visibleNodes: [TreeNodeItem] {
        func flatten(_ nodes: [FileNode], indent: Int) -> [TreeNodeItem] {
            var result: [TreeNodeItem] = []
            for node in nodes {
                result.append(TreeNodeItem(node: node, indent: indent))
                if node.type == "directory", state.isFileExpanded(node.path),
                   let children = state.cachedChildren(for: node.path) {
                    result.append(contentsOf: flatten(children, indent: indent + 1))
                }
            }
            return result
        }
        return flatten(state.visibleFileTreeRoot, indent: 0)
    }

    private func loadAndExpand(_ path: String) async {
        guard !isLoadingChildren.contains(path) else { return }
        let willExpand = !state.isFileExpanded(path)
        let cached = state.cachedChildren(for: path)
        state.toggleFileExpanded(path)
        guard willExpand, cached == nil else { return }
        isLoadingChildren.insert(path)
        _ = await state.loadFileChildren(path: path)
        isLoadingChildren.remove(path)
    }
}

private struct SearchResultRow: View {
    let path: String

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(DesignColors.Neutral.text)
            Text(path)
                .font(DesignTypography.body)
                .lineLimit(1)
            Spacer()
        }
    }
}

struct TreeNodeItem {
    let node: FileNode
    let indent: Int
    var path: String { node.path }
}

struct DirectoryRow: View {
    @Bindable var state: AppState
    let node: FileNode
    let indent: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: state.isFileExpanded(node.path) ? "chevron.down" : "chevron.right")
                .font(DesignTypography.micro)
                .frame(width: 12)
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Image(systemName: "folder.fill")
                .foregroundStyle(DesignColors.Brand.gold)
            Text(node.name)
                .font(DesignTypography.body)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, CGFloat(indent) * DesignSpacing.lg)
    }
}

struct FileRow: View {
    let node: FileNode
    let indent: Int
    let status: String?

    private var statusColor: Color {
        switch status {
        case "added": return DesignColors.Semantic.success
        case "deleted": return DesignColors.Semantic.error
        case "modified", "untracked": return DesignColors.Semantic.warning
        default: return DesignColors.Neutral.text
        }
    }

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "chevron.right")
                .font(DesignTypography.micro)
                .opacity(0)
                .frame(width: 12)
            Image(systemName: "doc.text")
                .foregroundStyle(statusColor)
            Text(node.name)
                .font(DesignTypography.body)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, CGFloat(indent) * DesignSpacing.lg)
    }
}
