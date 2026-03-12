//
//  ToolPartView.swift
//  OpenCodeClient
//

import SwiftUI

struct ToolPartView: View {
    let part: Part
    let sessionTodos: [TodoItem]
    let workspaceDirectory: String?
    let onOpenResolvedPath: (String) -> Void
    @State private var isExpanded: Bool
    @State private var showOpenFileSheet = false
    @State private var decodedImage: UIImage? = nil
    @State private var showImageSheet: Bool = false

    init(
        part: Part,
        sessionTodos: [TodoItem],
        workspaceDirectory: String?,
        onOpenResolvedPath: @escaping (String) -> Void
    ) {
        self.part = part
        self.sessionTodos = sessionTodos
        self.workspaceDirectory = workspaceDirectory
        self.onOpenResolvedPath = onOpenResolvedPath
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

    private var imageCandidatePaths: [String] {
        var candidates = part.filePathsForNavigation
        if let path = part.state?.pathFromInput, !path.isEmpty {
            candidates.append(path)
        }
        if let path = part.metadata?.path, !path.isEmpty {
            candidates.append(path)
        }
        return candidates
    }

    private var isImageFile: Bool {
        imageCandidatePaths.contains { ImageFileUtils.isImage($0) }
    }

    private var imageDisplayName: String {
        let raw = imageCandidatePaths.first(where: { ImageFileUtils.isImage($0) }) ?? "Image"
        return raw.split(separator: "/").last.map(String.init) ?? raw
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
                    let todos = part.toolTodos.isEmpty ? sessionTodos : part.toolTodos
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
                        if isImageFile {
                            if let img = decodedImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { showImageSheet = true }
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                    Text("Image file")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(output)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
        .task(id: part.id) {
            decodedImage = nil
            if isImageFile, let output = part.toolOutput {
                if let data = Data(base64Encoded: output), let img = UIImage(data: data) {
                    decodedImage = img
                } else {
                    let cleaned = output
                        .replacingOccurrences(of: "\n", with: "")
                        .replacingOccurrences(of: "\r", with: "")
                        .replacingOccurrences(of: " ", with: "")
                    if let data = Data(base64Encoded: cleaned), let img = UIImage(data: data) {
                        decodedImage = img
                    }
                }
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
        .sheet(isPresented: $showImageSheet) {
            if let img = decodedImage {
                NavigationStack {
                    ImageView(uiImage: img)
                        .navigationTitle(imageDisplayName)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                ShareLink(
                                    item: Image(uiImage: img),
                                    preview: SharePreview(imageDisplayName, image: Image(uiImage: img))
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    showImageSheet = false
                                }
                            }
                        }
                }
            }
        }
    }

    private func openFile(_ path: String) {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = PathNormalizer.resolveWorkspaceRelativePath(raw, workspaceDirectory: workspaceDirectory)
        guard !p.isEmpty else { return }
        onOpenResolvedPath(p)
    }
}
