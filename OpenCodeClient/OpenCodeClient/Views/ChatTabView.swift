//
//  ChatTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct ChatTabView: View {
    @Bindable var state: AppState
    @State private var inputText = ""
    @State private var isSending = false
    @State private var showSessionList = false
    @State private var showRenameAlert = false
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await state.createSession()
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                        }
                        Button {
                            renameText = state.currentSession?.title ?? ""
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .font(.title3)
                        }
                        Button {
                            showSessionList = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Array(state.modelPresets.enumerated()), id: \.element.id) { index, preset in
                            Button {
                                state.selectedModelIndex = index
                            } label: {
                                Text(preset.displayName)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(state.selectedModelIndex == index ? Color.accentColor : Color.gray.opacity(0.2))
                                    .foregroundColor(state.selectedModelIndex == index ? .white : .primary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }) { perm in
                                PermissionCardView(permission: perm) { approved in
                                    Task { await state.respondPermission(perm, approved: approved) }
                                }
                            }
                        ForEach(state.messages, id: \.info.id) { msg in
                            MessageRowView(message: msg, state: state)
                        }
                        if let streamingPart = streamingReasoningPart {
                            StreamingReasoningView(part: streamingPart)
                        }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .onChange(of: scrollAnchor) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
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
            .sheet(isPresented: $showSessionList) {
                SessionListView(state: state)
            }
            .alert("发送失败", isPresented: Binding(
                get: { state.sendError != nil },
                set: { if !$0 { state.sendError = nil } }
            )) {
                Button("确定") { state.sendError = nil }
            }             message: {
                if let error = state.sendError {
                    Text(error)
                }
            }
            .alert("重命名 Session", isPresented: $showRenameAlert) {
                TextField("标题", text: $renameText)
                Button("取消", role: .cancel) { showRenameAlert = false }
                Button("确定") {
                    guard let id = state.currentSessionID else { return }
                    Task { await state.updateSessionTitle(sessionID: id, title: renameText) }
                    showRenameAlert = false
                }
            } message: {
                Text("输入新标题")
            }
        }
    }

    /// 仅在 streaming 时显示：当 session busy 且最后一条 assistant 消息的最后一个 part 是 reasoning
    private var streamingReasoningPart: Part? {
        guard state.isBusy else { return nil }
        guard let lastMsg = state.messages.last, lastMsg.info.isAssistant else { return nil }
        guard let lastPart = lastMsg.parts.last, lastPart.isReasoning else { return nil }
        return lastPart
    }

    /// 内容变化时用于触发自动滚动
    private var scrollAnchor: String {
        let perm = state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }.count
        let msg = state.messages.map { "\($0.info.id)-\($0.parts.count)" }.joined(separator: "|")
        return "\(perm)-\(msg)"
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
    @Bindable var state: AppState

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if !text.isEmpty, let attr = try? AttributedString(markdown: text) {
            Text(attr)
        } else {
            Text(text)
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.parts.filter { $0.isText }, id: \.id) { part in
                markdownText(part.text ?? "")
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
            ForEach(message.parts.filter { !$0.isReasoning }, id: \.id) { part in
                if part.isText {
                    markdownText(part.text ?? "")
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if part.isTool {
                    ToolPartView(part: part, state: state)
                } else if part.isStepStart {
                    EmptyView()
                } else if part.isStepFinish {
                    EmptyView()
                } else if part.isPatch {
                    PatchPartView(part: part, state: state)
                }
            }
        }
    }
}

/// 仅在 streaming 时显示，think 完成后消失
struct StreamingReasoningView: View {
    let part: Part

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((part.text ?? "").isEmpty ? "Thinking..." : (part.text ?? ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .padding(.trailing, 16)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(8)
    }
}

struct ToolPartView: View {
    let part: Part
    @Bindable var state: AppState
    @State private var isExpanded: Bool
    @State private var showOpenFileSheet = false

    init(part: Part, state: AppState) {
        self.part = part
        self.state = state
        self._isExpanded = State(initialValue: part.stateDisplay?.lowercased() == "running")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let input = part.toolInputSummary ?? part.metadata?.input, !input.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command / Input")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(input)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                if let path = part.metadata?.path {
                    LabeledContent("Path", value: path)
                }
                if let output = part.toolOutput, !output.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(output)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                if !part.filePathsForNavigation.isEmpty {
                    ForEach(part.filePathsForNavigation, id: \.self) { path in
                        Button {
                            openFile(path)
                        } label: {
                            Label("在 File Tree 中打开 \(path)", systemImage: "folder.badge.plus")
                                .font(.caption2)
                        }
                    }
                }
            }
            .font(.caption2)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wrench.fill")
                Text(part.tool ?? "tool")
                if let reason = part.toolReason ?? part.metadata?.title, !reason.isEmpty {
                    Text(": \(reason)")
                        .foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .contextMenu {
            if !part.filePathsForNavigation.isEmpty {
                ForEach(part.filePathsForNavigation, id: \.self) { path in
                    Button("在 File Tree 中打开 \(path)") {
                        openFile(path)
                    }
                }
            }
        }
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
        print("[ToolPartView] openFile path=\(path)")
        state.fileToOpenInFilesTab = path
        state.selectedTab = 1
    }
}

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
            HStack {
                Image(systemName: "doc.text")
                Text("\(fileCount) file(s) changed")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
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
        state.fileToOpenInFilesTab = path
        state.selectedTab = 1
    }
}

struct PermissionCardView: View {
    let permission: PendingPermission
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Permission required")
                    .font(.headline)
            }
            Text(permission.description)
                .font(.subheadline)
            HStack(spacing: 8) {
                Button("Approve") {
                    onRespond(true)
                }
                .buttonStyle(.borderedProminent)
                Button("Reject") {
                    onRespond(false)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(8)
    }
}
