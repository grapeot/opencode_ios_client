//
//  MessageRowView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI

struct MessageRowView: View {
    private static let markdownRenderCharacterLimit = 50_000
    private static let largeMessagePreviewCharacterLimit = 12_000

    @Bindable var state: AppState
    let message: MessageWithParts
    let sessionTodos: [TodoItem]
    let workspaceDirectory: String?
    let onOpenResolvedPath: (String) -> Void
    let onOpenFilesTab: () -> Void
    let onForkFromMessage: ((String) -> Void)?
    let onEditFromMessage: ((String) -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

    // iPhone packs tool/patch cards two-up to keep information density high;
    // iPad has room for a 3-up grid.
    private var cardGridColumnCount: Int { sizeClass == .regular ? 3 : 2 }
    private var cardGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DesignSpacing.sm), count: cardGridColumnCount)
    }

    private enum AssistantBlock: Identifiable {
        case text(Part)
        case cards([Part])
        case attachment(Part)

        var id: String {
            switch self {
            case .text(let p):
                return "text-\(p.id)"
            case .cards(let parts):
                let first = parts.first?.id ?? "nil"
                let last = parts.last?.id ?? "nil"
                return "cards-\(first)-\(last)"
            case .attachment(let part):
                return "attachment-\(part.id)"
            }
        }
    }

    // A "file operation" is a patch part, or a tool whose name matches one of the
    // file-op verbs (loose prefix match so aliases like "edit"/"write"/"read"/"patch"
    // and full forms like "edit_file"/"apply_patch" all count). These render as
    // file cards in the grid; everything else collapses into "N tool calls".
    // Classification lives in ToolCardClassifier so it can be unit-tested.
    private func isFileOperation(_ part: Part) -> Bool {
        ToolCardClassifier.isFileOperation(part)
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
            } else if part.isFile {
                flushBuffer()
                blocks.append(.attachment(part))
            } else {
                flushBuffer()
            }
        }

        flushBuffer()
        return blocks
    }

    @ViewBuilder
    private func markdownText(_ text: String, isUser: Bool) -> some View {
        let font = isUser ? DesignTypography.bodyProminent : DesignTypography.body
        if Self.isLargeMessage(text) {
            LargeMessagePreview(text: text, preview: Self.largeMessagePreview(text))
                .font(font)
                .textSelection(.enabled)
        } else if shouldRenderMarkdown(text) {
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
                        loadFileContent: { pathBytes in try await state.loadFileContent(pathBytes: pathBytes) },
                        workspaceDirectory: workspaceDirectory
                    )
                )
                .task(id: text) {
                    resolvedText = nil
                    let sourceText = text
                    let resolved = await MarkdownImageResolver.resolveImages(
                        in: sourceText,
                        workspaceDirectory: workspaceDirectory,
                        fetchContent: { path in try await state.loadFileContent(path: path) }
                    )
                    guard !Task.isCancelled, sourceText == text else { return }
                    resolvedText = resolved
            }
        }
    }

    private func shouldRenderMarkdown(_ text: String) -> Bool {
        Self.hasMarkdownSyntax(text)
    }

    static func isLargeMessage(_ text: String) -> Bool {
        text.count > markdownRenderCharacterLimit
    }

    static func largeMessagePreview(_ text: String) -> String {
        guard isLargeMessage(text) else { return text }
        return String(text.prefix(largeMessagePreviewCharacterLimit))
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

    private struct LargeMessagePreview: View {
        let text: String
        let preview: String

        var body: some View {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text(preview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Large message: showing first \(preview.count.formatted()) of \(text.count.formatted()) characters. Markdown rendering is skipped to keep the app responsive.")
                    .font(DesignTypography.micro)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if message.info.isUser {
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
                    ForEach(message.parts.filter { $0.isText }, id: \.id) { part in
                        markdownText(part.text ?? "", isUser: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    let attachments = message.parts.filter { $0.isFile }
                    if !attachments.isEmpty {
                        MessageAttachmentsGrid(parts: attachments)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignColors.Brand.primary.opacity(DesignColors.userMessageFill(for: colorScheme)))
            .clipShape(RoundedRectangle(cornerRadius: DesignCorners.large))

            HStack {
                // User messages don't carry a model line — the model belongs to
                // the assistant's reply, not to what the human said.
                Spacer()
                if onForkFromMessage != nil {
                    Menu {
                        if onEditFromMessage != nil {
                            Button {
                                onEditFromMessage?(message.info.id)
                            } label: {
                                Label("Edit from here", systemImage: "pencil")
                            }
                            .disabled(state.isBusy)
                        }

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
            // No "OpenCode" speaker title — the user's blue left-bar vs the
            // assistant's container-less reply already make it clear who's
            // speaking, so an extra blue label is redundant.
            ForEach(assistantBlocks) { block in
                switch block {
                case .text(let part):
                    markdownText(part.text ?? "", isUser: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .cards(let parts):
                    cardsBlock(parts)
                case .attachment(let part):
                    MessageAttachmentView(part: part)
                }
            }

            // Model footer: same caption2/tertiary "providerID/modelID" treatment as
            // the user message, placed at the end of the assistant turn.
            if let model = message.info.resolvedModel {
                Text("\(model.providerID)/\(model.modelID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
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

    // A buffered run of tool/patch parts becomes: a 2-up (iPhone) / 3-up (iPad)
    // grid of file cards for the file operations, plus a single collapsed
    // "N tool calls" row for everything else. Layout-first near-time order:
    // file cards cluster into the grid, other tools cluster into one row.
    @ViewBuilder
    private func cardsBlock(_ parts: [Part]) -> some View {
        let (fileParts, otherParts) = ToolCardClassifier.split(parts)

        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            if !fileParts.isEmpty {
                LazyVGrid(
                    columns: cardGridColumns,
                    alignment: .leading,
                    spacing: DesignSpacing.sm
                ) {
                    ForEach(fileParts, id: \.id) { part in
                        FileCardView(
                            part: part,
                            workspaceDirectory: workspaceDirectory,
                            onOpenResolvedPath: onOpenResolvedPath,
                            onOpenFilesTab: onOpenFilesTab
                        )
                    }
                }
            }
            if !otherParts.isEmpty {
                toolCallsRow(otherParts)
            }
        }
    }

    private func toolCallsRow(_ parts: [Part]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                ForEach(parts, id: \.id) { part in
                    ToolPartView(
                        part: part,
                        sessionTodos: sessionTodos,
                        workspaceDirectory: workspaceDirectory,
                        onOpenResolvedPath: onOpenResolvedPath
                    )
                }
            }
            .padding(.top, DesignSpacing.sm)
        } label: {
            Text("\(parts.count) tool calls")
                .font(DesignTypography.micro)
                .fontWeight(.medium)
                .foregroundStyle(DesignColors.Brand.primary)
        }
        .tint(DesignColors.Brand.primary)
        .padding(DesignSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for: colorScheme)))
        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
        .accessibilityIdentifier("toolcard.toolcalls")
    }
}

private struct MessageAttachmentsGrid: View {
    let parts: [Part]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: DesignSpacing.sm)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DesignSpacing.sm) {
            ForEach(parts, id: \.id) { part in
                MessageAttachmentView(part: part)
            }
        }
    }
}

private struct MessageAttachmentView: View {
    let part: Part
    @State private var showImage = false

    private var imageData: Data? {
        guard part.isImageAttachment, let url = part.url else { return nil }
        return Self.decodeDataURL(url)
    }

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Button {
                    showImage = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                        .overlay(alignment: .bottomLeading) {
                            Text(part.filename ?? "Image")
                                .font(DesignTypography.micro)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.black.opacity(0.45))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("message-attachment-image")
                .sheet(isPresented: $showImage) {
                    NavigationStack {
                        ImageView(uiImage: image)
                            .navigationTitle(part.filename ?? "Image")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showImage = false }
                                }
                            }
                    }
                }
            } else {
                HStack(spacing: DesignSpacing.sm) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(DesignColors.Brand.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.filename ?? "Attachment")
                            .font(DesignTypography.meta)
                            .lineLimit(1)
                        if let mime = part.mime {
                            Text(mime)
                                .font(DesignTypography.micro)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(DesignSpacing.cardPadding)
                .background(DesignColors.Neutral.text.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                .accessibilityIdentifier("message-attachment-file")
            }
        }
    }

    private static func decodeDataURL(_ url: String) -> Data? {
        guard let comma = url.firstIndex(of: ",") else { return nil }
        let metadata = url[..<comma]
        guard metadata.contains(";base64") else { return nil }
        let raw = url[url.index(after: comma)...]
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Data(base64Encoded: raw)
    }
}
