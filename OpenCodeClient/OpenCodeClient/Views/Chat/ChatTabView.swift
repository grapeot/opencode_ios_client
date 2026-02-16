//
//  ChatTabView.swift
//  OpenCodeClient
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum MessageGroupItem: Identifiable {
    case user(MessageWithParts)
    case assistantMerged([MessageWithParts])

    var id: String {
        switch self {
        case .user(let m): return "user-\(m.info.id)"
        case .assistantMerged(let msgs): return "assistant-\(msgs.map(\.info.id).joined(separator: "-"))"
        }
    }

    var messageIDs: [String] {
        switch self {
        case .user(let m): return [m.info.id]
        case .assistantMerged(let msgs): return msgs.map { $0.info.id }
        }
    }
}

struct ChatTabView: View {
    @Bindable var state: AppState
    var showSettingsInToolbar: Bool = false
    var onSettingsTap: (() -> Void)?
    @State private var inputText = ""
    @State private var isSending = false
    @State private var isSyncingDraft = false
    @State private var showSessionList = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var recorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var speechError: String?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var useGridCards: Bool { sizeClass == .regular }

    fileprivate struct TurnActivity: Identifiable {
        enum State {
            case running
            case completed
        }

        let id: String  // userMessageID
        let state: State
        let text: String
        let startedAt: Date
        let endedAt: Date?

        func elapsedSeconds(now: Date = Date()) -> Int {
            let end = endedAt ?? now
            return max(0, Int(end.timeIntervalSince(startedAt)))
        }

        func elapsedString(now: Date = Date()) -> String {
            let secs = elapsedSeconds(now: now)
            return String(format: "%d:%02d", secs / 60, secs % 60)
        }
    }

    private enum ChatItem: Identifiable {
        case group(MessageGroupItem)
        case activity(TurnActivity)

        var id: String {
            switch self {
            case .group(let g): return "g-\(g.id)"
            case .activity(let a): return "a-\(a.id)"
            }
        }
    }

    private var currentPermissions: [PendingPermission] {
        state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }
    }

    private var isCurrentSessionBusy: Bool {
        guard let status = state.currentSessionStatus else { return false }
        return status.type == "busy" || status.type == "retry"
    }

    private var lastUserMessageIDInCurrentSession: String? {
        guard let sid = state.currentSessionID else { return nil }
        return state.messages.last(where: { $0.info.sessionID == sid && $0.info.isUser })?.info.id
    }

    private enum TurnActivityMode {
        case completedOnly
        case runningOnly
    }

    private func turnActivitiesForCurrentSession(_ mode: TurnActivityMode) -> [TurnActivity] {
        guard let sid = state.currentSessionID else { return [] }
        let msgs = state.messages

        var userIndices: [Int] = []
        userIndices.reserveCapacity(64)
        for (i, m) in msgs.enumerated() {
            if m.info.sessionID == sid, m.info.isUser {
                userIndices.append(i)
            }
        }
        if userIndices.isEmpty { return [] }

        let lastUserID = lastUserMessageIDInCurrentSession

        var result: [TurnActivity] = []
        result.reserveCapacity(userIndices.count)

        for (pos, ui) in userIndices.enumerated() {
            let userMsg = msgs[ui]
            let nextUserIndex = (pos + 1 < userIndices.count) ? userIndices[pos + 1] : msgs.count

            var lastAssistant: Message? = nil
            var lastCompletedAssistant: Message? = nil
            for j in (ui + 1)..<nextUserIndex {
                let m = msgs[j]
                if m.info.isAssistant {
                    lastAssistant = m.info
                    if m.info.time.completed != nil {
                        lastCompletedAssistant = m.info
                    }
                }
            }

            let startedAt = Date(timeIntervalSince1970: Double(userMsg.info.time.created) / 1000.0)

            let completedAt: Date? = {
                guard let completed = lastCompletedAssistant?.time.completed else { return nil }
                return Date(timeIntervalSince1970: Double(completed) / 1000.0)
            }()
            let fallbackEndAt: Date? = {
                guard let created = lastAssistant?.time.created else { return nil }
                return Date(timeIntervalSince1970: Double(created) / 1000.0)
            }()
            let endedAt = completedAt ?? fallbackEndAt

            let isLatestTurn = (userMsg.info.id == lastUserID)
            let isRunning = isLatestTurn && isCurrentSessionBusy

            switch mode {
            case .runningOnly:
                guard isRunning else { continue }
                result.append(
                    TurnActivity(
                        id: userMsg.info.id,
                        state: .running,
                        text: state.activityTextForSession(sid),
                        startedAt: startedAt,
                        endedAt: nil
                    )
                )
            case .completedOnly:
                guard !isRunning else { continue }
                // Only show a completed row if we have at least one assistant message for this turn.
                guard lastAssistant != nil else { continue }
                result.append(
                    TurnActivity(
                        id: userMsg.info.id,
                        state: .completed,
                        text: L10n.t(.chatTurnCompleted),
                        startedAt: startedAt,
                        endedAt: endedAt
                    )
                )
            }
        }

        return result
    }

    private var chatItems: [ChatItem] {
        // Completed activity rows interleaved after each assistant turn.
        let activities = turnActivitiesForCurrentSession(.completedOnly)
        let activityByUserID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })

        var items: [ChatItem] = []
        var currentUserID: String? = nil
        var seenAssistantForCurrentUser = false
        for group in messageGroups {
            switch group {
            case .user(let msg):
                if let uid = currentUserID,
                   seenAssistantForCurrentUser,
                   let a = activityByUserID[uid] {
                    items.append(.activity(a))
                }
                currentUserID = msg.info.id
                seenAssistantForCurrentUser = false
                items.append(.group(group))
            case .assistantMerged:
                if currentUserID != nil {
                    seenAssistantForCurrentUser = true
                }
                items.append(.group(group))
            }
        }

        if let uid = currentUserID,
           seenAssistantForCurrentUser,
           let a = activityByUserID[uid] {
            items.append(.activity(a))
        }
        return items
    }

    private var runningTurnActivity: TurnActivity? {
        turnActivitiesForCurrentSession(.runningOnly).last
    }

    private var showLoadMoreHint: Bool {
        state.isCurrentSessionHistoryTruncated || state.isLoadingOlderMessagesInCurrentSession
    }

    /// 合并同一 assistant turn 的连续 step-only 消息，使 tool 卡片在一个 grid 内连续显示
    private var messageGroups: [MessageGroupItem] {
        var result: [MessageGroupItem] = []
        var i = 0
        while i < state.messages.count {
            let msg = state.messages[i]
            if msg.info.isUser {
                result.append(.user(msg))
                i += 1
                continue
            }
            var assistantBatch: [MessageWithParts] = []
            while i < state.messages.count {
                let m = state.messages[i]
                if m.info.isUser { break }
                assistantBatch.append(m)
                i += 1
                if m.parts.contains(where: { $0.isText }) { break }
            }
            if !assistantBatch.isEmpty {
                result.append(.assistantMerged(assistantBatch))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatToolbarView(
                    state: state,
                    showSessionList: $showSessionList,
                    showRenameAlert: $showRenameAlert,
                    renameText: $renameText,
                    showSettingsInToolbar: showSettingsInToolbar,
                    onSettingsTap: onSettingsTap
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if showLoadMoreHint {
                                HStack(spacing: 8) {
                                    if state.isLoadingOlderMessagesInCurrentSession {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(
                                        state.isLoadingOlderMessagesInCurrentSession
                                            ? L10n.t(.chatLoadingMoreHistory)
                                            : L10n.t(.chatPullToLoadMore)
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 2)
                            }

                            if messageGroups.isEmpty {
                                emptySessionStateView
                            } else {
                                ForEach(chatItems) { item in
                                    switch item {
                                    case .group(let group):
                                        switch group {
                                        case .user(let msg):
                                            MessageRowView(
                                                message: msg,
                                                sessionTodos: state.sessionTodos[msg.info.sessionID] ?? [],
                                                workspaceDirectory: state.currentSession?.directory,
                                                onOpenResolvedPath: openFileInChat,
                                                onOpenFilesTab: openFilesTab
                                            )
                                        case .assistantMerged(let msgs):
                                            let merged = MessageWithParts(info: msgs.first!.info, parts: msgs.flatMap(\.parts))
                                            MessageRowView(
                                                message: merged,
                                                sessionTodos: state.sessionTodos[merged.info.sessionID] ?? [],
                                                workspaceDirectory: state.currentSession?.directory,
                                                onOpenResolvedPath: openFileInChat,
                                                onOpenFilesTab: openFilesTab
                                            )
                                        }
                                    case .activity(let a):
                                        TurnActivityRowView(activity: a)
                                    }
                                }
                            }
                            if let streamingPart = state.streamingReasoningPart {
                                StreamingReasoningView(part: streamingPart, state: state)
                                    .padding(.top, 6)
                            }

                            // Permissions should be at the bottom so auto-scroll makes them visible.
                            // Keep them above the activity row.
                            if useGridCards {
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                                    alignment: .leading,
                                    spacing: 10
                                ) {
                                    ForEach(currentPermissions) { perm in
                                        PermissionCardView(permission: perm) { response in
                                            Task { await state.respondPermission(perm, response: response) }
                                        }
                                    }
                                }
                            } else {
                                ForEach(currentPermissions) { perm in
                                    PermissionCardView(permission: perm) { response in
                                        Task { await state.respondPermission(perm, response: response) }
                                    }
                                }
                            }

                            // Running activity should be at the very bottom.
                            if let a = runningTurnActivity {
                                TurnActivityRowView(activity: a)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding()
                    }
                    .refreshable {
                        await state.loadOlderMessagesForCurrentSession()
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: scrollAnchor) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                 Divider()
                 HStack(alignment: .bottom, spacing: 10) {
                    TextField(L10n.t(.chatInputPlaceholder), text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...8)
                        .submitLabel(.send)
                        .onSubmit {
                            sendCurrentInput()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )

                    VStack(spacing: 8) {
                        Button {
                            Task { await toggleRecording() }
                        } label: {
                            if isTranscribing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: isRecording ? "mic.circle.fill" : "mic.circle")
                                    .font(.title)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(isRecording ? .red : .secondary)
                            }
                        }
                        .disabled(isSending || isTranscribing)

                        Button {
                            sendCurrentInput()
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
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || isRecording || isTranscribing)

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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle(state.currentSession?.title ?? L10n.t(.appChat))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if state.isBusy {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .sheet(isPresented: $showSessionList) {
                SessionListView(state: state)
            }
            .alert(L10n.t(.chatSendFailed), isPresented: Binding(
                get: { state.sendError != nil },
                set: { if !$0 { state.sendError = nil } }
            )) {
                Button(L10n.t(.commonOk)) { state.sendError = nil }
            }             message: {
                if let error = state.sendError {
                    Text(error)
                }
            }
            .alert(L10n.t(.chatRenameSession), isPresented: $showRenameAlert) {
                TextField(L10n.t(.chatTitleField), text: $renameText)
                Button(L10n.t(.commonCancel), role: .cancel) { showRenameAlert = false }
                Button(L10n.t(.commonOk)) {
                    guard let id = state.currentSessionID else { return }
                    Task { await state.updateSessionTitle(sessionID: id, title: renameText) }
                    showRenameAlert = false
                }
            } message: {
                Text(L10n.t(.chatRenameSessionPlaceholder))
            }
            .alert(L10n.t(.chatSpeechTitle), isPresented: Binding(
                get: { speechError != nil },
                set: { if !$0 { speechError = nil } }
            )) {
                Button(L10n.t(.commonOk)) { speechError = nil }
            } message: {
                Text(speechError ?? "")
            }
            .onAppear {
                syncDraftFromState(sessionID: state.currentSessionID)
            }
            .onChange(of: state.currentSessionID) { oldID, newID in
                state.setDraftText(inputText, for: oldID)
                syncDraftFromState(sessionID: newID)
            }
            .onChange(of: inputText) { _, newValue in
                guard !isSyncingDraft else { return }
                state.setDraftText(newValue, for: state.currentSessionID)
            }
        }
    }

    private func syncDraftFromState(sessionID: String?) {
        isSyncingDraft = true
        inputText = state.draftText(for: sessionID)
        isSyncingDraft = false
    }

    private func sendCurrentInput() {
        guard !isSending else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        isSending = true
        Task {
            let success = await state.sendMessage(text)
            isSending = false
            if !success {
                inputText = text
            }
        }
    }

    private func toggleRecording() async {
        if isRecording {
            guard let url = recorder.stop() else {
                isRecording = false
                return
            }
            isRecording = false
            isTranscribing = true
            defer { isTranscribing = false }
            do {
                let transcript = try await state.transcribeAudio(audioFileURL: url)
                let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    if inputText.isEmpty {
                        inputText = cleaned
                    } else {
                        inputText += " " + cleaned
                    }
                }
            } catch {
                speechError = error.localizedDescription
            }
        } else {
            let token = state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty {
                speechError = L10n.t(.chatSpeechTokenMissing)
                return
            }
            if state.isTestingAIBuilderConnection {
                speechError = L10n.t(.chatSpeechTesting)
                return
            }
            guard state.aiBuilderConnectionOK else {
                speechError = L10n.t(.chatSpeechNotPassed)
                return
            }

            let allowed = await recorder.requestPermission()
            guard allowed else {
                speechError = L10n.t(.chatMicrophoneDenied)
                return
            }
            do {
                try recorder.start()
                isRecording = true
            } catch {
                speechError = error.localizedDescription
            }
        }
    }

    /// 内容变化时用于触发自动滚动
    private var scrollAnchor: String {
        let perm = state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }.count
        let messageCount = state.messages.count
        let lastMessage = state.messages.last
        let lastMessageSignature = {
            guard let lastMessage else { return "none" }
            return "\(lastMessage.info.id)-\(lastMessage.parts.count)-\(lastMessage.info.time.completed ?? -1)"
        }()
        let streamKeyCount = state.streamingPartTexts.count
        let streamCharCount = state.streamingPartTexts.values.reduce(into: 0) { partial, text in
            partial += text.count
        }
        let streamingReasoningID = state.streamingReasoningPart?.id ?? ""
        let sid = state.currentSessionID ?? ""
        let status = state.currentSessionStatus?.type ?? ""
        let activity = runningTurnActivity.map {
            let state = ($0.state == .running) ? "running" : "completed"
            return "\($0.id)-\($0.text)-\(state)"
        } ?? ""
        return "\(perm)-\(messageCount)-\(lastMessageSignature)-\(streamKeyCount)-\(streamCharCount)-\(streamingReasoningID)-\(sid)-\(status)-\(activity)"
    }

    @ViewBuilder
    private var emptySessionStateView: some View {
        if state.currentSessionID == nil {
            Text(L10n.t(.chatSelectSessionFirst))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
        } else if isCurrentSessionBusy {
            // If busy but there is no user turn yet, show a lightweight placeholder.
            if lastUserMessageIDInCurrentSession == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.t(.chatSessionBusyMessage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 18)
            }
        } else {
            Text(L10n.t(.chatNoMessages))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
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
        case "busy": return L10n.t(.chatSessionStatusBusy)
        case "retry": return L10n.t(.chatSessionStatusRetrying)
        default: return L10n.t(.chatSessionStatusIdle)
        }
    }

    private func openFileInChat(_ resolvedPath: String) {
        guard !resolvedPath.isEmpty else { return }
        if sizeClass == .regular {
            state.previewFilePath = resolvedPath
            state.fileToOpenInFilesTab = nil
        } else {
            state.fileToOpenInFilesTab = resolvedPath
            state.selectedTab = 1
        }
    }

    private func openFilesTab() {
        state.selectedTab = 1
    }
}

private struct TurnActivityRowView: View {
    let activity: ChatTabView.TurnActivity

    var body: some View {
        Group {
            if activity.state == .running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    row(now: context.date)
                }
            } else {
                row(now: Date())
            }
        }
    }

    private func row(now: Date) -> some View {
        let elapsed = activity.elapsedString(now: now)
        let text = activity.text

        return HStack(spacing: 8) {
            Image(systemName: activity.state == .running ? "clock" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(elapsed)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4).opacity(0.6), lineWidth: 0.5)
        )
    }
}
