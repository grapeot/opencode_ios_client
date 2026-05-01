//
//  MessageRowView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI

struct MessageRowView: View {
    @Bindable var state: AppState
    let message: MessageWithParts
    let sessionTodos: [TodoItem]
    let workspaceDirectory: String?
    let onOpenResolvedPath: (String) -> Void
    let onOpenFilesTab: () -> Void
    let onForkFromMessage: ((String) -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var cardGridColumnCount: Int { sizeClass == .regular ? 3 : 2 }
    private var cardGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DesignSpacing.sm), count: cardGridColumnCount)
    }

    private enum AssistantBlock: Identifiable {
        case text(Part)
        case cards([Part])

        var id: String {
            switch self {
            case .text(let p):
                return "text-\(p.id)"
            case .cards(let parts):
                let first = parts.first?.id ?? "nil"
                let last = parts.last?.id ?? "nil"
                return "cards-\(first)-\(last)"
            }
        }
    }

    private var assistantBlocks: [AssistantBlock] {
        var blocks: [AssistantBlock] = []
        var buffer: [Part] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            blocks.append(.cards(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for part in message.parts {
            if part.isReasoning { continue }
            if part.isTool || part.isPatch {
                buffer.append(part)
                continue
            }
            if part.isStepStart || part.isStepFinish { continue }
            if part.isText {
                flushBuffer()
                blocks.append(.text(part))
            } else {
                flushBuffer()
            }
        }

        flushBuffer()
        return blocks
    }

    private var userTextParts: [Part] {
        message.parts.filter { $0.isText }
    }

    private var userFileParts: [Part] {
        message.parts.filter { $0.isFile }
    }

    @ViewBuilder
    private func markdownText(_ text: String, isUser: Bool) -> some View {
        let font = isUser ? DesignTypography.bodyProminent : DesignTypography.body
        if shouldRenderMarkdown(text) {
            ResolvedMarkdownView(text: text, state: state, workspaceDirectory: workspaceDirectory)
                .font(font)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(font)
                .textSelection(.enabled)
        }
    }

    private struct ResolvedMarkdownView: View {
        let text: String
        let state: AppState
        let workspaceDirectory: String?
        @State private var resolvedText: String?
        
        var body: some View {
            Markdown(resolvedText ?? text)
                .markdownImageProvider(
                    WorkspaceMarkdownImageProvider(
                        loadFileContent: { path in try await state.loadFileContent(path: path) },
                        workspaceDirectory: workspaceDirectory
                    )
                )
                .task {
                    resolvedText = await MarkdownImageResolver.resolveImages(
                        in: text,
                        workspaceDirectory: workspaceDirectory,
                        fetchContent: { path in try await state.loadFileContent(path: path) }
                    )
                }
        }
    }

    private func shouldRenderMarkdown(_ text: String) -> Bool {
        Self.hasMarkdownSyntax(text)
    }

    static func hasMarkdownSyntax(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let markdownSignals = [
            "```", "`", "**", "__", "#", "- ", "* ", "+ ", "1. ",
            "[", "](", "> ", "|", "~~"
        ]
        if markdownSignals.contains(where: { trimmed.contains($0) }) {
            return true
        }

        return trimmed.contains("\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if message.info.isUser {
                Divider()
                    .padding(.vertical, 4)
                userMessageView
            } else {
                assistantMessageView
            }
        }
    }

    private var userMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DesignColors.Brand.primary)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(userTextParts, id: \.id) { part in
                        markdownText(part.text ?? "", isUser: true)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, userFileParts.isEmpty ? 10 : 6)
                    }

                    if !userFileParts.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                            ForEach(userFileParts, id: \.id) { part in
                                UserAttachmentRow(part: part)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignColors.Brand.primary.opacity(DesignColors.userMessageFill(for: colorScheme)))
            .clipShape(RoundedRectangle(cornerRadius: DesignCorners.large))

            HStack {
                if let model = message.info.resolvedModel {
                    Text("\(model.providerID)/\(model.modelID)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if onForkFromMessage != nil {
                    Menu {
                        Button {
                            onForkFromMessage?(message.info.id)
                        } label: {
                            Label("Fork from here", systemImage: "arrow.triangle.branch")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.leading, 4)
        }
    }

    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(assistantBlocks) { block in
                switch block {
                case .text(let part):
                    markdownText(part.text ?? "", isUser: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .cards(let parts):
                    LazyVGrid(
                        columns: cardGridColumns,
                        alignment: .leading,
                        spacing: DesignSpacing.sm
                    ) {
                        ForEach(parts, id: \.id) { part in
                            cardView(part)
                        }
                    }
                }
            }
            if let err = message.info.errorMessageForDisplay {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(DesignColors.Semantic.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignColors.Semantic.error.opacity(DesignColors.surfaceFill(for: colorScheme)))
                    .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func cardView(_ part: Part) -> some View {
        if part.isTool {
            ToolPartView(
                part: part,
                sessionTodos: sessionTodos,
                workspaceDirectory: workspaceDirectory,
                onOpenResolvedPath: onOpenResolvedPath
            )
        } else if part.isPatch {
            PatchPartView(
                part: part,
                workspaceDirectory: workspaceDirectory,
                onOpenResolvedPath: onOpenResolvedPath,
                onOpenFilesTab: onOpenFilesTab
            )
        } else {
            EmptyView()
        }
    }
}

private struct UserAttachmentRow: View {
    let part: Part

    private var iconName: String {
        guard let mime = part.mime?.lowercased() else { return "paperclip" }
        if mime.hasPrefix("image/") { return "photo" }
        if mime == "application/pdf" { return "doc.richtext" }
        return "doc.text"
    }

    private var detail: String {
        guard let mime = part.mime?.lowercased() else { return "" }
        if mime.hasPrefix("image/") { return L10n.t(.chatAttachmentImageLabel) }
        if mime == "application/pdf" { return L10n.t(.chatAttachmentPDFLabel) }
        return L10n.t(.chatAttachmentTextLabel)
    }

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(DesignColors.Brand.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.displayFilename)
                    .font(DesignTypography.micro)
                    .lineLimit(1)
                Text(detail)
                    .font(DesignTypography.micro)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
    }
}
