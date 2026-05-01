//
//  ChatTabView.swift
//  OpenCodeClient
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os
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

private enum ChatAttachmentPicker {
    static let allowedFileTypes: [UTType] = [
        .image,
        .pdf,
        .text,
        .plainText,
        .sourceCode,
        .json,
        .xml,
        .commaSeparatedText,
        .tabSeparatedText,
    ]

    static func byteLimit(for kind: ChatAttachmentKind) -> Int {
        switch kind {
        case .image, .pdf:
            return 8 * 1024 * 1024
        case .text:
            return 1 * 1024 * 1024
        }
    }

    static func isTextType(_ type: UTType, filename: String) -> Bool {
        if type.conforms(to: .text) || type.conforms(to: .plainText) || type.conforms(to: .sourceCode) {
            return true
        }
        if type.conforms(to: .json) || type.conforms(to: .xml) || type.conforms(to: .commaSeparatedText) || type.conforms(to: .tabSeparatedText) {
            return true
        }

        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ["txt", "md", "mdx", "json", "yaml", "yml", "xml", "csv", "log", "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java", "c", "cpp", "h", "hpp", "sh", "zsh", "toml", "ini"].contains(ext)
    }
}

private struct AttachmentChipView: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    private var label: String {
        switch attachment.kind {
        case .image:
            return L10n.t(.chatAttachmentImageLabel)
        case .pdf:
            return L10n.t(.chatAttachmentPDFLabel)
        case .text:
            return L10n.t(.chatAttachmentTextLabel)
        }
    }

    private var iconName: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .pdf:
            return "doc.richtext"
        case .text:
            return "doc.text"
        }
    }

    var body: some View {
        HStack(spacing: DesignSpacing.xs) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(DesignColors.Brand.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(DesignTypography.micro)
                    .lineLimit(1)
                Text(label)
                    .font(DesignTypography.micro)
                    .foregroundStyle(.secondary)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(.chatAttachmentRemove))
        }
        .padding(.horizontal, DesignSpacing.sm)
        .padding(.vertical, 6)
        .background(DesignColors.Brand.primary.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DesignColors.Brand.primary.opacity(DesignColors.Opacity.borderStroke), lineWidth: 1)
        )
    }
}

enum ChatScrollBehavior {
    static let followThreshold: CGFloat = 80

    static func shouldAutoScroll(
        bottomMarkerMinY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat = followThreshold
    ) -> Bool {
        bottomMarkerMinY <= viewportHeight + threshold
    }
}

enum SessionListEdgeSwipeBehavior {
    static let edgeThreshold: CGFloat = 32
    static let minimumHorizontalTranslation: CGFloat = 72
    static let maximumVerticalTranslation: CGFloat = 56

    static func shouldOpenSessionList(startLocation: CGPoint, translation: CGSize) -> Bool {
        guard startLocation.x <= edgeThreshold else { return false }
        guard translation.width >= minimumHorizontalTranslation else { return false }
        return abs(translation.height) <= maximumVerticalTranslation
    }
}

private struct BottomMarkerMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatTabView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "SpeechProfile"
    )

    static func mergedSpeechInput(prefix: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return cleanedTranscript }
        return prefix + " " + cleanedTranscript
    }

    @Bindable var state: AppState
    var showSettingsInToolbar: Bool = false
    var onSettingsTap: (() -> Void)?
    @State private var inputText = ""
    @State private var hasMarkedText = false
    @State private var isSending = false
    @State private var isSyncingDraft = false
    @State private var showSessionList = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var recorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var speechError: String?
    @State private var showAttachmentOptions = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingScrollTask: Task<Void, Never>?
    @State private var pendingBottomVisibilityTask: Task<Void, Never>?
    @State private var isNearBottom = true
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var useGridCards: Bool { sizeClass == .regular }
    private var currentComposerAttachments: [ComposerAttachment] {
        state.showAttachmentButton ? state.composerAttachments(for: state.currentSessionID) : []
    }
    private var canSendCurrentMessage: Bool {
        ChatComposerSendGate.canSend(
            text: inputText,
            hasAttachments: !currentComposerAttachments.isEmpty,
            isSending: isSending,
            hasMarkedText: hasMarkedText
        )
    }

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

    private var currentQuestions: [QuestionRequest] {
        state.pendingQuestions.filter { $0.sessionID == state.currentSessionID }
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
        let activityByUserID: [String: TurnActivity] = activities.reduce(into: [:]) { result, activity in
            result[activity.id] = activity
        }

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
                    GeometryReader { scrollGeometry in
                        ScrollView {
                            VStack(alignment: .leading, spacing: DesignSpacing.messageVertical) {
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
                                        Group {
                                            switch item {
                                            case .group(let group):
                                                switch group {
                                                case .user(let msg):
                                                    MessageRowView(
                                                        state: state,
                                                        message: msg,
                                                        sessionTodos: state.sessionTodos[msg.info.sessionID] ?? [],
                                                        workspaceDirectory: state.currentSession?.directory,
                                                        onOpenResolvedPath: openFileInChat,
                                                        onOpenFilesTab: openFilesTab,
                                                        onForkFromMessage: { messageID in
                                                            Task { await state.forkSession(messageID: messageID) }
                                                        }
                                                    )
                                                case .assistantMerged(let msgs):
                                                    if let first = msgs.first {
                                                        let merged = MessageWithParts(info: first.info, parts: msgs.flatMap(\.parts))
                                                        MessageRowView(
                                                            state: state,
                                                            message: merged,
                                                            sessionTodos: state.sessionTodos[merged.info.sessionID] ?? [],
                                                            workspaceDirectory: state.currentSession?.directory,
                                                            onOpenResolvedPath: openFileInChat,
                                                            onOpenFilesTab: openFilesTab,
                                                            onForkFromMessage: { messageID in
                                                                Task { await state.forkSession(messageID: messageID) }
                                                            }
                                                        )
                                                    }
                                                }
                                            case .activity(let a):
                                                TurnActivityRowView(activity: a)
                                            }
                                        }
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    }
                                }
                                if let streamingPart = state.streamingReasoningPart {
                                    StreamingReasoningView(part: streamingPart, state: state)
                                        .padding(.top, 6)
                                }

                                if useGridCards {
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: DesignSpacing.sm), count: 3),
                                        alignment: .leading,
                                        spacing: DesignSpacing.sm
                                    ) {
                                        ForEach(currentPermissions) { perm in
                                            PermissionCardView(permission: perm) { response in
                                                Task { await state.respondPermission(perm, response: response) }
                                            }
                                        }
                                    }
                                    ForEach(currentQuestions) { question in
                                        QuestionCardView(
                                            request: question,
                                            onReply: { answers in
                                                Task { await state.respondQuestion(question, answers: answers) }
                                            },
                                            onReject: {
                                                Task { await state.rejectQuestion(question) }
                                            }
                                        )
                                    }
                                } else {
                                    ForEach(currentPermissions) { perm in
                                        PermissionCardView(permission: perm) { response in
                                            Task { await state.respondPermission(perm, response: response) }
                                        }
                                    }
                                    ForEach(currentQuestions) { question in
                                        QuestionCardView(
                                            request: question,
                                            onReply: { answers in
                                                Task { await state.respondQuestion(question, answers: answers) }
                                            },
                                            onReject: {
                                                Task { await state.rejectQuestion(question) }
                                            }
                                        )
                                    }
                                }

                                if let a = runningTurnActivity {
                                    TurnActivityRowView(activity: a)
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                                    .background(
                                        GeometryReader { bottomGeometry in
                                            Color.clear.preference(
                                                key: BottomMarkerMinYPreferenceKey.self,
                                                value: bottomGeometry.frame(in: .named("chatScrollView")).minY
                                            )
                                        }
                                    )
                            }
                            .padding()
                        }
                        .coordinateSpace(name: "chatScrollView")
                        .refreshable {
                            await state.loadOlderMessagesForCurrentSession()
                        }
                        .scrollDismissesKeyboard(.immediately)
                        .onPreferenceChange(BottomMarkerMinYPreferenceKey.self) { bottomMarkerMinY in
                            scheduleBottomVisibilityUpdate(
                                bottomMarkerMinY: bottomMarkerMinY,
                                viewportHeight: scrollGeometry.size.height
                            )
                        }
                        .onChange(of: scrollAnchor) { _, _ in
                            guard isNearBottom else { return }
                            scheduleScrollToBottom(using: proxy)
                        }
                        .onDisappear {
                            pendingScrollTask?.cancel()
                            pendingScrollTask = nil
                            pendingBottomVisibilityTask?.cancel()
                            pendingBottomVisibilityTask = nil
                        }
                        .overlay(alignment: .leading) {
                            if sizeClass != .regular {
                                Color.clear
                                    .frame(width: SessionListEdgeSwipeBehavior.edgeThreshold)
                                    .contentShape(Rectangle())
                                    .gesture(sessionListEdgeSwipeGesture)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }

                Divider()
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    if state.showAttachmentButton, !currentComposerAttachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DesignSpacing.sm) {
                                ForEach(currentComposerAttachments) { attachment in
                                    AttachmentChipView(attachment: attachment) {
                                        state.removeComposerAttachment(id: attachment.id, for: state.currentSessionID)
                                    }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    HStack(alignment: .bottom, spacing: DesignSpacing.md) {
                        if state.showAttachmentButton {
                            Button {
                                showAttachmentOptions = true
                            } label: {
                                Image(systemName: "paperclip")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(DesignColors.Brand.primary)
                                    .frame(width: 32, height: 32)
                                    .background(Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignCorners.medium)
                                            .stroke(DesignColors.Brand.primary.opacity(DesignColors.Opacity.borderStroke), lineWidth: 1.5)
                                    )
                            }
                            .accessibilityLabel(L10n.t(.chatChooseAttachment))
                            .disabled(isSending)
                        }

                        ZStack(alignment: .topLeading) {
                            ChatComposerTextView(
                                text: $inputText,
                                hasMarkedText: $hasMarkedText,
                                placeholder: L10n.t(.chatInputPlaceholder),
                                onSubmit: sendCurrentInput
                            )
                            .frame(minHeight: 32, maxHeight: 100)
                            .accessibilityIdentifier("chat-input")

                            if inputText.isEmpty {
                                Text(L10n.t(.chatInputPlaceholder))
                                    .foregroundStyle(.secondary)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(colorScheme == .dark ? DesignColors.Neutral.composerDark : DesignColors.Neutral.composerLight)
                        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.large))

                        VStack(spacing: DesignSpacing.sm) {
                            Button {
                                Task { await toggleRecording() }
                            } label: {
                                ZStack {
                                    if isTranscribing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "mic.fill")
                                            .font(.callout)
                                            .foregroundStyle(isRecording ? .white : DesignColors.Brand.primary)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .background(isRecording ? Color.red : (isTranscribing ? (colorScheme == .dark ? DesignColors.Neutral.surfaceDark : DesignColors.Neutral.surfaceLight) : Color.clear))
                                .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignCorners.medium)
                                        .stroke(
                                            isRecording ? Color.clear : DesignColors.Brand.primary.opacity(DesignColors.Opacity.borderStroke),
                                            lineWidth: 1.5
                                        )
                                )
                            }
                            .disabled(isSending || isTranscribing)

                            Button {
                                sendCurrentInput()
                            } label: {
                                ZStack {
                                    if isSending {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "arrow.up")
                                            .font(.body.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .background(DesignColors.Brand.primary)
                                .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                            }
                            .disabled(!canSendCurrentMessage || isRecording || isTranscribing)

                            if state.isBusy {
                                Button {
                                    Task { await state.abortSession() }
                                } label: {
                                    Image(systemName: "stop.fill")
                                        .font(.body.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.red)
                                        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle(state.currentSession?.title ?? L10n.t(.appChat))
            .navigationBarTitleDisplayMode(.inline)
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
            .confirmationDialog(L10n.t(.chatAttachmentMenuTitle), isPresented: $showAttachmentOptions, titleVisibility: .visible) {
                Button(L10n.t(.chatChooseImage)) {
                    showPhotoPicker = true
                }
                Button(L10n.t(.chatChooseFile)) {
                    showFileImporter = true
                }
                Button(L10n.t(.commonCancel), role: .cancel) {}
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 5,
                matching: .images
            )
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: ChatAttachmentPicker.allowedFileTypes,
                allowsMultipleSelection: true
            ) { result in
                handleImportedFiles(result)
            }
            .onAppear {
                syncDraftFromState(sessionID: state.currentSessionID)
            }
            .onChange(of: state.currentSessionID) { oldID, newID in
                let draftText = inputText
                Task { @MainActor in
                    state.setDraftText(draftText, for: oldID)
                    syncDraftFromState(sessionID: newID)
                    isNearBottom = true
                    pendingBottomVisibilityTask?.cancel()
                    pendingBottomVisibilityTask = nil
                }
            }
            .onChange(of: inputText) { _, newValue in
                guard !isSyncingDraft else { return }
                state.setDraftText(newValue, for: state.currentSessionID)
            }
            .onChange(of: selectedPhotoItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task {
                    await importPhotoAttachments(newValue)
                    await MainActor.run {
                        selectedPhotoItems = []
                    }
                }
            }
        }
    }

    private func syncDraftFromState(sessionID: String?) {
        isSyncingDraft = true
        inputText = state.draftText(for: sessionID)
        isSyncingDraft = false
    }

    private func scheduleScrollToBottom(using proxy: ScrollViewProxy) {
        pendingScrollTask?.cancel()
        let shouldAnimate = !state.isBusy

        pendingScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            if shouldAnimate {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func scheduleBottomVisibilityUpdate(bottomMarkerMinY: CGFloat, viewportHeight: CGFloat) {
        pendingBottomVisibilityTask?.cancel()
        pendingBottomVisibilityTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
            isNearBottom = ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: bottomMarkerMinY,
                viewportHeight: viewportHeight
            )
        }
    }

    private func sendCurrentInput() {
        guard canSendCurrentMessage else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousAttachments = currentComposerAttachments

        inputText = ""
        hasMarkedText = false
        isSending = true
        Task {
            let success = await state.sendMessage(text)
            isSending = false
            if !success {
                inputText = text
                if state.showAttachmentButton {
                    state.clearComposerAttachments(for: state.currentSessionID)
                    state.appendComposerAttachments(previousAttachments, for: state.currentSessionID)
                }
            }
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await importFileAttachments(urls)
            }
        case .failure:
            state.sendError = L10n.t(.chatAttachmentReadFailed)
        }
    }

    private func importPhotoAttachments(_ items: [PhotosPickerItem]) async {
        var attachments: [ComposerAttachment] = []

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run { state.sendError = L10n.t(.chatAttachmentReadFailed) }
                    continue
                }
                let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .png
                if let attachment = makeAttachment(
                    data: data,
                    filename: generatedFilename(for: .image, type: type),
                    type: type,
                    fallbackKind: .image
                ) {
                    attachments.append(attachment)
                }
            } catch {
                await MainActor.run { state.sendError = L10n.t(.chatAttachmentReadFailed) }
            }
        }

        await MainActor.run {
            state.appendComposerAttachments(attachments, for: state.currentSessionID)
        }
    }

    private func importFileAttachments(_ urls: [URL]) async {
        var attachments: [ComposerAttachment] = []

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let type = inferredType(for: url)
                if let attachment = makeAttachment(
                    data: data,
                    filename: url.lastPathComponent,
                    type: type,
                    fallbackKind: nil
                ) {
                    attachments.append(attachment)
                }
            } catch {
                await MainActor.run { state.sendError = L10n.t(.chatAttachmentReadFailed) }
            }
        }

        await MainActor.run {
            state.appendComposerAttachments(attachments, for: state.currentSessionID)
        }
    }

    private func makeAttachment(
        data: Data,
        filename: String,
        type: UTType,
        fallbackKind: ChatAttachmentKind?
    ) -> ComposerAttachment? {
        let kind = attachmentKind(for: type, filename: filename) ?? fallbackKind
        guard let kind else {
            state.sendError = L10n.t(.chatAttachmentUnsupportedFileType)
            return nil
        }

        let byteLimit = ChatAttachmentPicker.byteLimit(for: kind)
        guard data.count <= byteLimit else {
            state.sendError = L10n.t(.chatAttachmentFileTooLarge)
            return nil
        }

        let mimeType = resolvedMimeType(for: type, kind: kind, filename: filename)
        let encoded = data.base64EncodedString()
        return ComposerAttachment(
            id: UUID().uuidString,
            filename: filename,
            mimeType: mimeType,
            dataURL: "data:\(mimeType);base64,\(encoded)",
            kind: kind,
            byteCount: data.count
        )
    }

    private func inferredType(for url: URL) -> UTType {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type
        }
        return .data
    }

    private func generatedFilename(for kind: ChatAttachmentKind, type: UTType) -> String {
        let ext = type.preferredFilenameExtension ?? {
            switch kind {
            case .image: return "png"
            case .pdf: return "pdf"
            case .text: return "txt"
            }
        }()
        return "attachment-\(UUID().uuidString.prefix(8)).\(ext)"
    }

    private func attachmentKind(for type: UTType, filename: String) -> ChatAttachmentKind? {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if ChatAttachmentPicker.isTextType(type, filename: filename) { return .text }
        return nil
    }

    private func resolvedMimeType(for type: UTType, kind: ChatAttachmentKind, filename: String) -> String {
        if let mime = type.preferredMIMEType {
            return mime
        }
        switch kind {
        case .image:
            let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" { return "image/jpeg" }
            if ext == "gif" { return "image/gif" }
            if ext == "webp" { return "image/webp" }
            return "image/png"
        case .pdf:
            return "application/pdf"
        case .text:
            return "text/plain"
        }
    }

    private func toggleRecording() async {
        if isRecording {
            let stopStart = ProcessInfo.processInfo.systemUptime
            guard let url = recorder.stop() else {
                isRecording = false
                Self.logger.error("[SpeechProfile] recorder stop failed: missing file URL")
                return
            }
            isRecording = false
            let fileBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            Self.logger.notice("[SpeechProfile] recorder stopped ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - stopStart) * 1000)), privacy: .public) file=\(url.lastPathComponent, privacy: .public) bytes=\(fileBytes, privacy: .public)")

            isTranscribing = true
            defer { isTranscribing = false }
            let prefix = inputText
            let transcribeStart = ProcessInfo.processInfo.systemUptime
            do {
                let transcript = try await state.transcribeAudio(audioFileURL: url) { partial in
                    Task { @MainActor in
                        inputText = Self.mergedSpeechInput(prefix: prefix, transcript: partial)
                    }
                }
                let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.notice("[SpeechProfile] chat transcribe done ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - transcribeStart) * 1000)), privacy: .public) chars=\(cleaned.count, privacy: .public)")
                inputText = Self.mergedSpeechInput(prefix: prefix, transcript: cleaned)
            } catch {
                Self.logger.error("[SpeechProfile] chat transcribe failed ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - transcribeStart) * 1000)), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                inputText = prefix
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

            let permissionStart = ProcessInfo.processInfo.systemUptime
            let allowed = await recorder.requestPermission()
            Self.logger.notice("[SpeechProfile] microphone permission allowed=\(allowed, privacy: .public) ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - permissionStart) * 1000)), privacy: .public)")
            guard allowed else {
                speechError = L10n.t(.chatMicrophoneDenied)
                return
            }
            let startRecordingStart = ProcessInfo.processInfo.systemUptime
            do {
                try recorder.start()
                isRecording = true
                Self.logger.notice("[SpeechProfile] recorder started ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - startRecordingStart) * 1000)), privacy: .public)")
            } catch {
                Self.logger.error("[SpeechProfile] recorder start failed error=\(error.localizedDescription, privacy: .public)")
                speechError = error.localizedDescription
            }
        }
    }

    /// 内容变化时用于触发自动滚动
    private var scrollAnchor: String {
        let perm = state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }.count
        let questionCount = state.pendingQuestions.filter { $0.sessionID == state.currentSessionID }.count
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
        return "\(perm)-\(questionCount)-\(messageCount)-\(lastMessageSignature)-\(streamKeyCount)-\(streamCharCount)-\(streamingReasoningID)-\(sid)-\(status)-\(activity)"
    }

    @ViewBuilder
    private var emptySessionStateView: some View {
        if state.currentSessionID == nil {
            VStack(spacing: DesignSpacing.md) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignColors.Brand.primary.opacity(0.2))
                Text(L10n.t(.chatSelectSessionFirst))
                    .font(DesignTypography.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        } else if isCurrentSessionBusy {
            // If busy but there is no user turn yet, show a lightweight placeholder.
            if lastUserMessageIDInCurrentSession == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.t(.chatSessionBusyMessage))
                        .font(DesignTypography.meta)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 18)
            }
        } else {
            VStack(spacing: DesignSpacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignColors.Brand.gold.opacity(0.3))
                Text(L10n.t(.chatNoMessages))
                    .font(DesignTypography.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        }
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status.type {
        case "busy": return DesignColors.Brand.primary
        case "error": return DesignColors.Semantic.error
        default: return DesignColors.Semantic.success
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

    private var sessionListEdgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard sizeClass != .regular else { return }
                guard !showSessionList else { return }
                guard SessionListEdgeSwipeBehavior.shouldOpenSessionList(
                    startLocation: value.startLocation,
                    translation: value.translation
                ) else { return }
                showSessionList = true
            }
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

        return HStack(spacing: DesignSpacing.sm) {
            Image(systemName: activity.state == .running ? "clock" : "checkmark.circle")
                .font(DesignTypography.micro)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
            Text(text)
                .font(DesignTypography.micro)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
            Spacer(minLength: 12)
            Text(elapsed)
                .font(DesignTypography.micro)
                .monospacedDigit()
                .foregroundStyle(DesignColors.Neutral.textTertiary)
        }
        .padding(.vertical, DesignSpacing.sm)
    }
}
