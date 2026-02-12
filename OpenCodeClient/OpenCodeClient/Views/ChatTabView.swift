//
//  ChatTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct ChatTabView: View {
    @Bindable var state: AppState
    @State private var inputText = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let status = state.currentSessionStatus {
                    HStack {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)
                        Text(statusLabel(status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(state.messages, id: \.info.id) { msg in
                            MessageRowView(message: msg)
                        }
                    }
                    .padding()
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)

                    Button {
                        Task {
                            let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            inputText = ""
                            isSending = true
                            let success = await state.sendMessage(text)
                            isSending = false
                            if !success {
                                inputText = text
                            }
                        }
                    } label: {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

                    if state.isBusy {
                        Button {
                            Task { await state.abortSession() }
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(state.currentSession?.title ?? "Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("New") {
                        Task { await state.createSession() }
                    }
                }
            }
            .alert("发送失败", isPresented: Binding(
                get: { state.sendError != nil },
                set: { if !$0 { state.sendError = nil } }
            )) {
                Button("确定") { state.sendError = nil }
            } message: {
                if let error = state.sendError {
                    Text(error)
                }
            }
        }
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status.type {
        case "busy": return .blue
        case "error": return .red
        default: return .green
        }
    }

    private func statusLabel(_ status: SessionStatus) -> String {
        switch status.type {
        case "busy": return "Busy"
        case "retry": return "Retrying..."
        default: return "Idle"
        }
    }
}

struct MessageRowView: View {
    let message: MessageWithParts

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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.parts.filter { $0.isText }, id: \.id) { part in
                Text(part.text ?? "")
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)

            if let model = message.info.model {
                Text("\(model.providerID)/\(model.modelID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assistantMessageView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.parts, id: \.id) { part in
                if part.isText {
                    Text(part.text ?? "")
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if part.isTool {
                    HStack {
                        Image(systemName: "wrench.fill")
                        Text(part.tool ?? "tool")
                        Text(part.state ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
}
