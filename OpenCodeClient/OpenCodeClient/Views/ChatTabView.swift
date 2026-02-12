//
//  ChatTabView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI

struct ChatTabView: View {
    @Bindable var state: AppState
    var showSettingsInToolbar: Bool = false
    var onSettingsTap: (() -> Void)?
    @State private var inputText = ""
    @State private var isSending = false
    @State private var showSessionList = false
    @State private var showRenameAlert = false
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await state.createSession()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                        Button {
                            renameText = state.currentSession?.title ?? ""
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                        Button {
                            showSessionList = true
                        } label: {
                            Image(systemName: "list.bullet.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Array(state.modelPresets.enumerated()), id: \.element.id) { index, preset in
                            Button {
                                state.selectedModelIndex = index
                            } label: {
                                Text(preset.displayName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        state.selectedModelIndex == index
                                            ? AnyShapeStyle(Color.accentColor.gradient)
                                            : AnyShapeStyle(Color(.systemGray5))
                                    )
                                    .foregroundColor(state.selectedModelIndex == index ? .white : .secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if showSettingsInToolbar, let onSettingsTap {
                            Button {
                                onSettingsTap()
                            } label: {
                                Image(systemName: "gear")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }) { perm in
                                PermissionCardView(permission: perm) { approved in
                                    Task { await state.respondPermission(perm, approved: approved) }
                                }
                            }
                            if !state.currentTodos.isEmpty {
                                SessionTodoCardView(todos: state.currentTodos)
                            }
                        ForEach(state.messages, id: \.info.id) { msg in
                            MessageRowView(message: msg, state: state)
                        }
                        if let streamingPart = streamingReasoningPart {
                            StreamingReasoningView(part: streamingPart, state: state)
                        }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .textSelection(.enabled)
                    .onChange(of: scrollAnchor) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Divider()
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask anything...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )

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
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

                    if state.isBusy {
                        Button {
                            Task { await state.abortSession() }
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle(state.currentSession?.title ?? "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let status = state.currentSessionStatus {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 6, height: 6)
                            Text(statusLabel(status))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
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
            ForEach(message.parts.filter { !$0.isReasoning }, id: \.id) { part in
                if part.isText {
                    markdownText(part.text ?? "")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
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

/// 仅在 streaming 时显示，think 完成后消失。无 sync 栏，灰色字体打字机效果。
struct StreamingReasoningView: View {
    let part: Part
    @Bindable var state: AppState

    private var displayText: String {
        let key = "\(part.messageID):\(part.id)"
        return state.streamingPartTexts[key] ?? part.text ?? ""
    }

    var body: some View {
        if !displayText.isEmpty {
            Text(displayText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
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
                if let reason = part.toolReason ?? part.metadata?.title, !reason.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reason")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(reason)
                            .font(.caption2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                if part.tool == "todowrite" {
                    let todos = part.toolTodos.isEmpty ? (state.sessionTodos[part.sessionID] ?? []) : part.toolTodos
                    if !todos.isEmpty {
                        TodoListInlineView(todos: todos)
                    }
                }
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
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.blue.opacity(0.7))
                    .font(.caption)
                Text(part.tool ?? "tool")
                    .fontWeight(.medium)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ToolPartView] openFile path=\(p)")
        state.fileToOpenInFilesTab = p
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
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.orange.opacity(0.7))
                Text("\(fileCount) file\(fileCount == 1 ? "" : "s") changed")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        state.fileToOpenInFilesTab = p
        state.selectedTab = 1
    }
}

struct PermissionCardView: View {
    let permission: PendingPermission
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange.gradient)
                    .font(.title3)
                Text("Permission Required")
                    .font(.subheadline.weight(.semibold))
            }
            Text(permission.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    onRespond(true)
                } label: {
                    Text("Approve")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button {
                    onRespond(false)
                } label: {
                    Text("Reject")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

struct SessionTodoCardView: View {
    let todos: [TodoItem]
    @State private var isExpanded = false

    private var completed: Int {
        todos.filter { $0.isCompleted }.count
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            TodoListInlineView(todos: todos)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .foregroundStyle(.blue.opacity(0.7))
                Text("Task List")
                    .fontWeight(.semibold)
                Text("\(completed)/\(todos.count)")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TodoListInlineView: View {
    let todos: [TodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(todos) { todo in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        .font(.caption)
                        .padding(.top, 1)
                    Text(todo.content)
                        .font(.caption2)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .strikethrough(todo.isCompleted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.top, 4)
    }
}
