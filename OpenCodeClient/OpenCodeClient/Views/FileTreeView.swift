//
//  FileTreeView.swift
//  OpenCodeClient
//

import SwiftUI

struct FileTreeView: View {
    @Bindable var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isLoadingChildren: Set<String> = []

    /// Force iPad split behavior (preview in middle column instead of push).
    var forceSplitPreview: Bool = false

    /// iPad 分栏：点击文件更新预览栏；iPhone：在 Files Tab 内 push
    private var useSplitPreview: Bool {
        forceSplitPreview || sizeClass == .regular
    }

    var body: some View {
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
                } else {
                    if useSplitPreview {
                        Button {
                            state.previewFilePath = item.node.path
                        } label: {
                            FileRow(
                                node: item.node,
                                indent: item.indent,
                                status: state.fileStatusMap[item.node.path])
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: item.node.path) {
                            FileRow(
                                node: item.node,
                                indent: item.indent,
                                status: state.fileStatusMap[item.node.path])
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: String.self) { path in
            FileContentView(state: state, filePath: path)
        }
        .onAppear {
            if state.fileTreeRoot.isEmpty {
                Task { await state.loadFileTree() }
            }
        }
        .refreshable {
            await state.loadFileTree()
            await state.loadFileStatus()
        }
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
        return flatten(state.fileTreeRoot, indent: 0)
    }

    private func loadAndExpand(_ path: String) async {
        guard !isLoadingChildren.contains(path) else { return }
        isLoadingChildren.insert(path)
        state.toggleFileExpanded(path)
        if state.cachedChildren(for: path) == nil {
            _ = await state.loadFileChildren(path: path)
        }
        isLoadingChildren.remove(path)
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
