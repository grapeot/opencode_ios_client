//
//  MessageRowView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI

struct MessageRowView: View {
    let message: MessageWithParts
    @Bindable var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var useGridCards: Bool { sizeClass == .regular }

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
        // Only layout non-reasoning parts here; reasoning streaming is handled separately.
        let parts = message.parts.filter { !$0.isReasoning }

        var blocks: [AssistantBlock] = []
        var buffer: [Part] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            blocks.append(.cards(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for part in parts {
            if part.isTool || part.isPatch {
                buffer.append(part)
                continue
            }

            // step-start/step-finish are currently rendered as separators elsewhere.
            // For iPad card grid density, do not break the current card flow.
            if part.isStepStart || part.isStepFinish {
                continue
            }

            if part.isText {
                flushBuffer()
                blocks.append(.text(part))
            } else {
                // Unknown/unsupported types: break card flow to avoid odd grid mixing.
                flushBuffer()
            }
        }

        flushBuffer()
        return blocks
    }

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if !text.isEmpty {
            Markdown(text)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
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
            ForEach(message.parts.filter { $0.isText }, id: \.id) { part in
                markdownText(part.text ?? "")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let model = message.info.model {
                Text("\(model.providerID)/\(model.modelID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
    }

    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(assistantBlocks) { block in
                switch block {
                case .text(let part):
                    markdownText(part.text ?? "")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .cards(let parts):
                    if useGridCards {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(parts, id: \.id) { part in
                                cardView(part)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(parts, id: \.id) { part in
                                cardView(part)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardView(_ part: Part) -> some View {
        if part.isTool {
            ToolPartView(part: part, state: state)
        } else if part.isPatch {
            PatchPartView(part: part, state: state)
        } else {
            EmptyView()
        }
    }
}
