//
//  ChatTabView.swift
//  OpenCodeClient
//

import SwiftUI
import os
import os.lock
import PhotosUI
import VoiceFlowKit
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

private struct BottomMarkerMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatTabView: View {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "SpeechProfile"
    )

    static func shouldAutoScrollSpeechTranscript(isTranscribing: Bool, isRetryingSpeech: Bool) -> Bool {
        isTranscribing || isRetryingSpeech
    }

    /// Zero-padded turn stopwatch for the persistent status line: `MM:SS`
    /// below an hour, `HH:MM:SS` at or above. It counts up while the agent
    /// works and holds at the completion instant once the turn stops (the
    /// caller freezes the end time). Negative input (server/client clock skew,
    /// message timestamp slightly in the future) clamps to `00:00` rather than
    /// rendering a negative duration. Hours are not capped or truncated, so a
    /// very long-lived session reads `49:23:10` in full.
    static func elapsedStatusText(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Localized, spoken form of the same duration for VoiceOver, e.g.
    /// "3m 41s" / "1h 2m 3s". Keeps the raw `MM:SS` out of the screen reader,
    /// which would otherwise read it as a clock time. Falls back to a literal
    /// seconds string when the formatter yields nothing (e.g. exactly zero
    /// with drop-leading behavior).
    static func elapsedSpokenText(seconds: Int) -> String {
        let total = max(0, seconds)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        if let text = formatter.string(from: TimeInterval(total)), !text.isEmpty {
            return text
        }
        return "\(total)s"
    }

    @Bindable var state: AppState
    var showSettingsInToolbar: Bool = false
    var showSessionListInToolbar: Bool = true
    var showCreateSessionInToolbar: Bool = true
    var onSettingsTap: (() -> Void)?
    @State var inputText = ""
    @State private var hasMarkedText = false
    @State private var isSending = false
    @State private var isSyncingDraft = false
    @State private var showSessionList = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State var microphone = VoiceFlowMicrophone()
    @State var speechSession: VoiceFlowSession?
    @State var speechAudioSender: OrderedSpeechAudioSender?
    @State var speechStartID: UUID?
    @State var speechOriginSessionID: String?
    @State var activeSpeechStrategy: VoiceFlowRecordingStrategy = .gptLiveTranscribe
    @State var speechFinalizationID: UUID?
    @State var speechRetryID: UUID?
    @State var speechRetrySessionID: String?
    @State var speechHeartbeatTask: Task<Void, Never>?
    @State var speechEventTask: Task<Void, Never>?
    @State var recordingInputPrefix = ""
    @State var pendingSpeechAudioByOwner: [ChatSpeechOwner: PendingChatSpeechAudio] = [:]
    @State var completedSpeechDraftByOwner: [ChatSpeechOwner: String] = [:]
    @State var isRecording = false
    @State var isStartingRecording = false
    @State var isTranscribing = false
    @State var isRetryingSpeech = false
    @State var speechError: String?
    @State var speechRecoveryActive = false
    @State var speechAudioLevel: Float = 0
    @State var speechAudioLevelTask: Task<Void, Never>?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var imageAttachments: [ComposerImageAttachment] = []
    @State private var attachmentError: String?
    @State private var isLoadingAttachment = false
    @State private var inlinePreviewPath: String?
    @State private var inlinePreviewWorkspaceDirectory: String?
    @State private var pendingScrollTask: Task<Void, Never>?
    @State private var pendingBottomVisibilityTask: Task<Void, Never>?
    @State private var isNearBottom = true
    /// When the view last scrolled itself to the bottom; bottom-marker
    /// measurements inside the settle window after this are too early to
    /// trust (the animated snap has not landed yet).
    @State private var lastSelfScrollAt: Date?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private var useGridCards: Bool { sizeClass == .regular }

    private static var hasUITestF3TranscribingFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_F3_TRANSCRIBING_FIXTURE")
    }

    private static var hasUITestF3RetryFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_F3_RETRY_FIXTURE")
    }

    private var isShowingTranscribingUI: Bool {
        isTranscribing || Self.hasUITestF3TranscribingFixture
    }

    private var hasPreservedSpeechAudioForUI: Bool {
        pendingSpeechAudioByOwner[ChatSpeechOwner(sessionID: state.currentSessionID)] != nil
            || Self.hasUITestF3RetryFixture
    }

    private var composerPlaceholderText: String {
        if isRecording { return L10n.t(.chatSpeechTranscriptWillAppear) }
        if isShowingTranscribingUI { return L10n.t(.chatSpeechTranscribingHint) }
        if hasPreservedSpeechAudioForUI { return L10n.t(.chatSpeechPreservedAudio) }
        return L10n.t(.chatInputPlaceholder)
    }

    private var canSendNow: Bool {
        (ChatComposerSendGate.canSend(text: inputText, isSending: isSending, hasMarkedText: hasMarkedText) || (!imageAttachments.isEmpty && !isSending && !hasMarkedText))
            && !isRecording && !isShowingTranscribingUI && !isRetryingSpeech
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
        let visibleMessages = AppState.visibleMessages(
            state.messages,
            revertMessageID: state.currentSession?.revert?.messageID,
            pendingIDs: state.messageStore.pendingOptimisticMessageIDs
        )
        var result: [MessageGroupItem] = []
        var i = 0
        while i < visibleMessages.count {
            let msg = visibleMessages[i]
            if msg.info.isUser {
                result.append(.user(msg))
                i += 1
                continue
            }
            var assistantBatch: [MessageWithParts] = []
            while i < visibleMessages.count {
                let m = visibleMessages[i]
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

    private var voiceRailMode: VoiceRailWaveformView.Mode {
        if isRecording { return .active }
        if isShowingTranscribingUI || isRetryingSpeech { return .generating }
        return .idle
    }

    private var voiceRailColor: Color {
        if isRecording { return DesignColors.Brand.primary }
        if isShowingTranscribingUI || isRetryingSpeech { return DesignColors.Brand.primary }
        return DesignColors.Neutral.textTertiary
    }

    private var voiceRailTitle: String {
        if isRecording { return L10n.t(.chatSpeechListening) }
        if isShowingTranscribingUI { return L10n.t(.chatSpeechTranscribing) }
        if isRetryingSpeech { return L10n.t(.chatSpeechRetrySegment) }
        if hasPreservedSpeechAudioForUI { return L10n.t(.chatSpeechPreservedAudio) }
        return L10n.t(.chatSpeechTapToSpeak)
    }

    private var voiceStatusText: String? {
        if speechRecoveryActive { return L10n.t(.chatSpeechRecovering) }
        if isRecording { return L10n.t(.chatSpeechListening) }
        if isShowingTranscribingUI { return L10n.t(.chatSpeechTranscribing) }
        if isRetryingSpeech { return L10n.t(.chatSpeechRetrySegment) }
        if hasPreservedSpeechAudioForUI { return L10n.t(.chatSpeechPreservedAudio) }
        return nil
    }

    /// Session-level counters for the current session, shown persistently on
    /// the top line of the composer status bar: session-scoped data lives on
    /// the always-visible status bar rather than per-message footers. Icons
    /// keep the line compact: refresh = rounds, tools = tool calls, TOK text
    /// for tokens.
    private var sessionStats: (rounds: Int, toolCalls: Int, tokens: Int?, cacheHitRate: Double?)? {
        guard let sessionID = state.currentSessionID else { return nil }
        let stats = state.statsStore.stats(for: sessionID)
        return (
            stats.rounds,
            stats.toolCalls,
            state.sessionTotalTokens(sessionID: sessionID),
            state.sessionCacheHitRate(sessionID: sessionID)
        )
    }

    private func cacheHitRateText(_ rate: Double) -> String {
        "\(Int((rate * 100).rounded()))%"
    }

    /// Anchor for the persistent turn stopwatch: the `time.created` of the
    /// last user message in the current session. Derived from the already-
    /// loaded message window, so it needs no extra network request and
    /// survives restart / session switch for free.
    private var lastUserMessageDate: Date? {
        guard let sid = state.currentSessionID else { return nil }
        guard let msg = state.messages.last(where: { $0.info.sessionID == sid && $0.info.isUser }) else {
            return nil
        }
        // A missing/zero timestamp would otherwise anchor the stopwatch at the
        // Unix epoch and render an absurd duration; hide the segment instead.
        guard msg.info.time.created > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(msg.info.time.created) / 1000.0)
    }

    /// Frozen end time of the current turn's stopwatch, or nil while the turn
    /// is still running (or has only just been sent). The stopwatch therefore
    /// counts up while the agent works and holds at the completion instant
    /// once it stops; a new user message moves the anchor and resets it to
    /// zero. Matching by the latest user message id means a freshly sent
    /// prompt (no assistant output yet, status not yet busy) reads as running
    /// from zero rather than briefly showing the previous turn's value.
    private var currentTurnEndedAt: Date? {
        guard let lastUserID = lastUserMessageIDInCurrentSession else { return nil }
        guard runningTurnActivity == nil else { return nil }
        let completed = turnActivitiesForCurrentSession(.completedOnly).last
        return completed?.id == lastUserID ? completed?.endedAt : nil
    }

    @ViewBuilder
    private var sessionStatsLine: some View {
        if let stats = sessionStats {
            // The whole line ticks, not just the stopwatch segment: the
            // VoiceOver label must stay live, and a single accessibility
            // element can only be refreshed if it is rebuilt inside the
            // TimelineView. The per-second cost is a handful of small Texts
            // (cheaper than the transient row this replaced).
            TimelineView(.periodic(from: .now, by: 1)) { context in
                sessionStatsLineContent(stats: stats, now: context.date)
            }
        }
    }

    private func sessionStatsLineContent(
        stats: (rounds: Int, toolCalls: Int, tokens: Int?, cacheHitRate: Double?),
        now: Date
    ) -> some View {
        // Full width + leading so the single-line block is not centered
        // by the parent VStack (which would differ from the two-line
        // layout, where the transient row spans the width).
        HStack(spacing: DesignSpacing.xs) {
            sessionStatsIconLabel("arrow.triangle.2.circlepath", value: "\(stats.rounds)")
            Text("·").foregroundStyle(DesignColors.Neutral.textTertiary)
            sessionStatsIconLabel("wrench.and.screwdriver", value: "\(stats.toolCalls)")
            if let tokens = stats.tokens {
                Text("·").foregroundStyle(DesignColors.Neutral.textTertiary)
                Text("\(MessageRowView.compactTokenCount(tokens)) \(L10n.t(.statusTokensLabel))")
            }
            if let hitRate = stats.cacheHitRate {
                Text("·").foregroundStyle(DesignColors.Neutral.textTertiary)
                Text("\(L10n.t(.statusCacheHitsLabel)) \(cacheHitRateText(hitRate))")
            }
            if let anchor = lastUserMessageDate {
                Text("·").foregroundStyle(DesignColors.Neutral.textTertiary)
                Text(ChatTabView.elapsedStatusText(seconds: turnElapsedSeconds(anchor: anchor, now: now)))
                    .monospacedDigit()
            }
        }
        .font(DesignTypography.meta)
        .foregroundStyle(DesignColors.Neutral.textTertiary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(accessibilityLabel(stats: stats, now: now))
    }

    /// Choose the stopwatch end: the frozen completion instant when the turn
    /// has stopped, otherwise `now` so it keeps counting while the agent works.
    static func turnStopwatchEnd(frozenEnd: Date?, now: Date) -> Date {
        frozenEnd ?? now
    }

    /// Elapsed for the current turn: counts to `now` while the turn runs, and
    /// to the frozen completion instant once it stops.
    private func turnElapsedSeconds(anchor: Date, now: Date) -> Int {
        let end = ChatTabView.turnStopwatchEnd(frozenEnd: currentTurnEndedAt, now: now)
        return max(0, Int(end.timeIntervalSince(anchor)))
    }

    private func accessibilityLabel(
        stats: (rounds: Int, toolCalls: Int, tokens: Int?, cacheHitRate: Double?),
        now: Date
    ) -> String {
        var parts = [
            "\(stats.rounds) \(L10n.t(.statusRoundsLabel))",
            "\(stats.toolCalls) \(L10n.t(.statusToolsLabel))",
        ]
        if let tokens = stats.tokens {
            parts.append("\(MessageRowView.compactTokenCount(tokens)) \(L10n.t(.statusTokensLabel))")
        }
        if let hitRate = stats.cacheHitRate {
            parts.append("\(L10n.t(.statusCacheHitsLabel)) \(cacheHitRateText(hitRate))")
        }
        if let anchor = lastUserMessageDate {
            parts.append("\(L10n.t(.statusSinceLastPromptLabel)) \(ChatTabView.elapsedSpokenText(seconds: turnElapsedSeconds(anchor: anchor, now: now)))")
        }
        return parts.joined(separator: ", ")
    }

    private func sessionStatsIconLabel(_ systemImage: String, value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(value).monospacedDigit()
        }
    }

    private var composerStatusText: String? {
        let agentStatus = state.isBusy ? (runningTurnActivity?.text ?? L10n.t(.chatAgentRunning)) : nil
        let parts = [agentStatus, voiceStatusText].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var voiceRailTransportIcon: String {
        if isRecording { return "stop.circle.fill" }
        if isShowingTranscribingUI || isRetryingSpeech { return "circle.dotted" }
        if hasPreservedSpeechAudioForUI { return "arrow.clockwise" }
        return "mic.fill"
    }

    /// Adaptive composer status bar: one line when only the persistent
    /// session counters are present, expanding to two when there is also
    /// transient per-turn state (agent activity, voice, abort). Top line =
    /// session counters incl. the time-since-last-prompt stopwatch; bottom
    /// line = transient state. The per-turn elapsed readout used to live on
    /// the bottom line but moved to the always-visible top line, so it no
    /// longer disappears (and duplicates) once the turn completes.
    private var quietComposerStatus: some View {
        // 6pt gap: xs (4) read as cramped between the two lines.
        VStack(alignment: .leading, spacing: 6) {
            sessionStatsLine
            if hasTransientComposerStatus {
                quietComposerStatusRow()
            }
        }
        .padding(.horizontal, DesignSpacing.xs)
        .padding(.top, DesignSpacing.xs)
        .padding(.bottom, DesignSpacing.xs)
    }

    /// The transient (bottom) line only renders when it has content; an
    /// empty line would just add height to the always-visible composer block.
    private var hasTransientComposerStatus: Bool {
        composerStatusText != nil || state.isBusy
    }

    private func quietComposerStatusRow() -> some View {
        HStack(spacing: DesignSpacing.sm) {
            if state.isBusy {
                Circle()
                    .fill(DesignColors.Brand.gold)
                    .frame(width: 6, height: 6)
                    .shadow(color: DesignColors.Brand.gold.opacity(0.25), radius: 4)
            }

            Text(composerStatusText ?? "")
                .font(DesignTypography.meta)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if state.isBusy {
                Menu {
                    Button(role: .destructive) {
                        Task { await state.abortSession() }
                    } label: {
                        Label(L10n.t(.chatAbortAgent), systemImage: "stop.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(DesignTypography.meta.weight(.semibold))
                        .foregroundStyle(DesignColors.Neutral.textTertiary)
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("agent-interrupt-menu")
                .accessibilityLabel(L10n.t(.chatAbortAgent))
            }
        }
    }

    /// The status block stays up whenever there is anything to say: the
    /// persistent session counters (top line) or transient turn state
    /// (bottom line). Without this the counters would vanish while idle.
    private var shouldShowComposerStatus: Bool {
        composerStatusText != nil || sessionStats != nil
    }

    private var voiceRailTrailingAction: some View {
        Group {
            if isShowingTranscribingUI {
                Button {
                    guard !Self.hasUITestF3TranscribingFixture else { return }
                    Task { await abortSpeechRecognition() }
                } label: {
                    Text(L10n.t(.chatSpeechStopWaiting))
                        .font(DesignTypography.meta.weight(.semibold))
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, 7)
                        .background {
                            Capsule().fill(DesignColors.Neutral.textSecondary.opacity(0.10))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("speech-stop-waiting")
            } else if hasPreservedSpeechAudioForUI {
                Button {
                    guard !Self.hasUITestF3RetryFixture else { return }
                    clearPreservedSpeechAudio()
                } label: {
                    Text(L10n.t(.chatSpeechDiscardAudio))
                        .font(DesignTypography.meta.weight(.semibold))
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, 7)
                        .background {
                            Capsule().fill(DesignColors.Neutral.textSecondary.opacity(0.10))
                        }
                }
                .disabled(isRetryingSpeech || isStartingRecording || isSending)
                .buttonStyle(.plain)
                .accessibilityIdentifier("speech-discard-audio")
            }
        }
    }

    private var voiceRail: some View {
        HStack(spacing: DesignSpacing.sm) {
            Button {
                if hasPreservedSpeechAudioForUI {
                    guard !Self.hasUITestF3RetryFixture else { return }
                    Task { await retryPreservedSpeechAudio() }
                } else {
                    Task { await toggleRecording() }
                }
            } label: {
                ZStack {
                    if isStartingRecording || isRetryingSpeech {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: voiceRailTransportIcon)
                            .font(DesignControls.composerActionIconFont.weight(.semibold))
                            .foregroundStyle(isRecording ? Color.red : DesignColors.Brand.primary)
                    }
                }
                .frame(width: DesignControls.composerActionButtonSize, height: DesignControls.composerActionButtonSize)
                .background {
                    Circle().fill((isRecording ? Color.red : DesignColors.Brand.primary).opacity(0.14))
                }
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.lift)
            }
            .disabled(isSending || isShowingTranscribingUI || isStartingRecording || isRetryingSpeech)
            .buttonStyle(.plain)
            .accessibilityIdentifier(hasPreservedSpeechAudioForUI ? "speech-retry-segment" : "speech-transport")
            .accessibilityLabel(hasPreservedSpeechAudioForUI ? L10n.t(.chatSpeechRetrySegment) : voiceRailTitle)

            VoiceRailWaveformView(mode: voiceRailMode, color: voiceRailColor, level: speechAudioLevel)
                .frame(height: 22)
                .accessibilityIdentifier("speech-waveform")

            voiceRailTrailingAction
        }
        .padding(.horizontal, DesignSpacing.xs)
        .padding(.top, DesignSpacing.xs)
        .padding(.bottom, 6)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Docked file preview (iPhone): fills the whole screen except the
                // composer strip at the bottom, which stays interactive so voice
                // recording and typing keep working while the file is open.
                if let previewPath = inlinePreviewPath {
                    ChatInlineFilePreview(
                        state: state,
                        filePath: previewPath,
                        workspaceDirectory: inlinePreviewWorkspaceDirectory,
                        onClose: {
                            withAnimation(DesignAnimation.spring) {
                                inlinePreviewPath = nil
                                inlinePreviewWorkspaceDirectory = nil
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ChatToolbarView(
                        state: state,
                        showSessionList: $showSessionList,
                        showRenameAlert: $showRenameAlert,
                        renameText: $renameText,
                        showSettingsInToolbar: showSettingsInToolbar,
                        showSessionListInToolbar: showSessionListInToolbar,
                        showCreateSessionInToolbar: showCreateSessionInToolbar,
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
                                    // viewport height minus the content padding (16 on
                                    // each side) and the 1pt bottom marker, so the
                                    // block fills the viewport and the bottom anchor
                                    // keeps it at its previous top position
                                    emptySessionStateView(viewportHeight: scrollGeometry.size.height - 33)
                                } else {
                                    ForEach(chatItems) { item in
                                        Group {
                                            switch item {
                                            case .group(let group):
                                                switch group {
                                                case .user(let msg):
                                                    let workspaceDirectory = workspaceDirectory(for: msg.info.sessionID)
                                                    MessageRowView(
                                                        state: state,
                                                        message: msg,
                                                        sessionTodos: state.sessionTodos[msg.info.sessionID] ?? [],
                                                          workspaceDirectory: workspaceDirectory,
                                                          onOpenResolvedPath: { openFileInChat($0) },
                                                          onOpenMarkdownResolvedPath: { openFileInChat($0, workspaceDirectory: workspaceDirectory) },
                                                          onOpenFilesTab: openFilesTab,
                                                          onForkFromMessage: { messageID in
                                                             Task { await state.forkSession(messageID: messageID) }
                                                         },
                                                         onEditFromMessage: { messageID in
                                                             Task {
                                                                 guard let draft = await state.editFromMessage(messageID: messageID) else { return }
                                                                 inputText = draft
                                                             }
                                                         }
                                                     )
                                                case .assistantMerged(let msgs):
                                                    if let first = msgs.first {
                                                        let merged = MessageWithParts(info: first.info, parts: msgs.flatMap(\.parts))
                                                        let workspaceDirectory = workspaceDirectory(for: merged.info.sessionID)
                                                        MessageRowView(
                                                            state: state,
                                                            message: merged,
                                                            sessionTodos: state.sessionTodos[merged.info.sessionID] ?? [],
                                                              workspaceDirectory: workspaceDirectory,
                                                              onOpenResolvedPath: { openFileInChat($0) },
                                                              onOpenMarkdownResolvedPath: { openFileInChat($0, workspaceDirectory: workspaceDirectory) },
                                                              onOpenFilesTab: openFilesTab,
                                                             onForkFromMessage: { messageID in
                                                                 Task { await state.forkSession(messageID: messageID) }
                                                             },
                                                             onEditFromMessage: { messageID in
                                                                 Task {
                                                                     guard let draft = await state.editFromMessage(messageID: messageID) else { return }
                                                                     inputText = draft
                                                                 }
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
                        .opencodeScrollDismissesKeyboard()
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
                        // Per-session scroll identity: switching sessions tears down
                        // the scroll view instead of reusing it, so the previous
                        // session's contentOffset can't survive into the new
                        // session's (different) content and drop the view in the
                        // middle of the conversation. defaultScrollAnchor(.bottom)
                        // gives every fresh session view a bottom-anchored start;
                        // the reactive isNearBottom mechanism still follows live
                        // updates after that.
                        .defaultScrollAnchor(.bottom)
                        .id(state.currentSessionID)
                    }
                    }
                }

                 VStack(spacing: 0) {
                    if shouldShowComposerStatus {
                        quietComposerStatus
                    }

                    voiceRail

                    if !imageAttachments.isEmpty || isLoadingAttachment || attachmentError != nil {
                        attachmentStrip
                    }

                    HStack(alignment: .bottom, spacing: DesignSpacing.sm) {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 4,
                            matching: .images
                        ) {
                            ZStack {
                                if isLoadingAttachment {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "photo")
                                        .font(DesignControls.composerActionIconFont)
                                }
                            }
                            .frame(width: DesignControls.composerPrimaryActionButtonSize, height: DesignControls.composerPrimaryActionButtonSize)
                            .foregroundStyle(DesignColors.Brand.primary)
                            .background(DesignColors.Brand.primary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
                        }
                        .disabled(isLoadingAttachment || isSending)
                        .accessibilityIdentifier("chat-attach-image")

                        ZStack(alignment: .topLeading) {
                            ChatComposerTextView(
                                text: $inputText,
                                hasMarkedText: $hasMarkedText,
                                placeholder: L10n.t(.chatInputPlaceholder),
                                autoScrollToBottomOnTextChange: Self.shouldAutoScrollSpeechTranscript(
                                    isTranscribing: isTranscribing,
                                    isRetryingSpeech: isRetryingSpeech
                                ),
                                onSubmit: sendCurrentInput
                            )
                            .frame(
                                minHeight: DesignControls.composerTextMinHeight,
                                maxHeight: DesignControls.composerTextMaxHeight
                            )
                            .accessibilityIdentifier("chat-input")

                            if inputText.isEmpty {
                                Text(composerPlaceholderText)
                                    .foregroundStyle(DesignColors.Neutral.textTertiary)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }

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
                                        .font(DesignControls.composerActionIconFont.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: DesignControls.composerPrimaryActionButtonSize, height: DesignControls.composerPrimaryActionButtonSize)
                            .background {
                                RoundedRectangle(cornerRadius: DesignCorners.medium)
                                    .fill(canSendNow ? DesignColors.Brand.primary : DesignColors.Brand.primary.opacity(0.35))
                            }
                            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: DesignCorners.medium))
                            .hoverEffect(.lift)
                        }
                        .accessibilityIdentifier("chat-send")
                        .disabled(!canSendNow)
                        .padding(.bottom, 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(colorScheme == .dark ? DesignColors.Neutral.composerDark : DesignColors.Neutral.composerLight)
                .clipShape(RoundedRectangle(cornerRadius: DesignCorners.large))
                .padding(.horizontal, DesignControls.composerContainerHorizontalPadding)
                .padding(.vertical, 5)
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
            .onAppear {
                Task { @MainActor in
                    syncDraftFromState(sessionID: state.currentSessionID)
                }
            }
            .onChange(of: state.currentSessionID) { oldID, newID in
                let draftText = inputText
                state.setDraftText(draftText, for: oldID)
                syncDraftFromState(sessionID: newID)
                isNearBottom = true
                pendingBottomVisibilityTask?.cancel()
                pendingBottomVisibilityTask = nil
                if inlinePreviewPath != nil {
                    withAnimation(DesignAnimation.spring) {
                        inlinePreviewPath = nil
                        inlinePreviewWorkspaceDirectory = nil
                    }
                }
                Task { @MainActor in
                    await stopSpeechForNavigation()
                }
            }
            .onChange(of: inputText) { _, newValue in
                guard !isSyncingDraft else { return }
                let draftSessionID = state.currentSessionID
                Task { @MainActor in
                    await Task.yield()
                    guard !isSyncingDraft,
                          state.currentSessionID == draftSessionID,
                          inputText == newValue else { return }
                    state.setDraftText(newValue, for: draftSessionID)
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task { await loadSelectedPhotos(newItems) }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .background else { return }
                Task { await stopSpeechForBackground() }
            }
            .onChange(of: sizeClass) { _, newValue in
                // Docked preview is chat-local; migrate it to the iPad middle
                // column when the layout switches to regular width.
                guard newValue == .regular, let path = inlinePreviewPath else { return }
                state.previewFilePath = path
                state.previewFileWorkspaceDirectory = inlinePreviewWorkspaceDirectory
                inlinePreviewPath = nil
                inlinePreviewWorkspaceDirectory = nil
            }
        }
    }

    private func syncDraftFromState(sessionID: String?) {
        isSyncingDraft = true
        if sessionID == nil,
           let completedDraft = completedSpeechDraftByOwner[ChatSpeechOwner(sessionID: nil)] {
            inputText = completedDraft
        } else {
            inputText = state.draftText(for: sessionID)
        }
        isSyncingDraft = false
    }

    private func scheduleScrollToBottom(using proxy: ScrollViewProxy) {
        lastSelfScrollAt = Date()
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
            let nearBottom = ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: bottomMarkerMinY,
                viewportHeight: viewportHeight
            )
            // A "far from bottom" reading captured while our own snap is
            // still settling must not latch the flag off — that stale
            // reading used to block every later event-driven auto-scroll
            // until the user switched sessions.
            if ChatScrollBehavior.shouldApplyBottomMeasurement(
                measuredNearBottom: nearBottom,
                lastSelfScrollAt: lastSelfScrollAt,
                now: Date()
            ) {
                isNearBottom = nearBottom
            }
        }
    }

    private func sendCurrentInput() {
        guard canSendNow else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = imageAttachments

        inputText = ""
        imageAttachments = []
        selectedPhotoItems = []
        hasMarkedText = false
        isSending = true
        Task {
            let success = await state.sendMessage(text, attachments: attachments)
            isSending = false
            if !success {
                inputText = text
                imageAttachments = attachments
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSpacing.sm) {
                ForEach(imageAttachments) { attachment in
                    ComposerAttachmentThumbnail(attachment: attachment) {
                        imageAttachments.removeAll { $0.id == attachment.id }
                    }
                }
                if isLoadingAttachment {
                    ProgressView()
                        .frame(width: 54, height: 54)
                }
                if let attachmentError {
                    Text(attachmentError)
                        .font(DesignTypography.micro)
                        .foregroundStyle(DesignColors.Semantic.error)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("chat-attachment-strip")
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        attachmentError = nil
        isLoadingAttachment = true
        defer {
            isLoadingAttachment = false
            selectedPhotoItems = []
        }

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let attachment = try ComposerImageTranscoder.makeAttachment(from: data)
                imageAttachments.append(attachment)
            } catch {
                attachmentError = error.localizedDescription
            }
        }
    }

    /// 内容变化时用于触发自动滚动。签名含最后一条消息的累计文本长度：流式
    /// delta 只增长既有 part 的 text（parts.count 不变），没有这一项，长文本
    /// 回复期间 onChange 永不触发，视图不再跟随到底部。
    private var scrollAnchor: String {
        let lastMessage = state.messages.last.map { message in
            ChatScrollBehavior.LastMessageFingerprint(
                id: message.info.id,
                partCount: message.parts.count,
                textLength: message.parts.reduce(0) { $0 + ($1.text?.count ?? 0) },
                completed: message.info.time.completed
            )
        }
        return ChatScrollBehavior.scrollSignature(
            pendingPermissions: state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }.count,
            pendingQuestions: state.pendingQuestions.filter { $0.sessionID == state.currentSessionID }.count,
            messageCount: state.messages.count,
            lastMessage: lastMessage,
            sessionID: state.currentSessionID ?? "",
            status: state.currentSessionStatus?.type ?? "",
            activity: runningTurnActivity.map {
                let state = ($0.state == .running) ? "running" : "completed"
                return "\($0.id)-\($0.text)-\(state)"
            } ?? ""
        )
    }

    /// Empty-state block that fills the viewport (minus content padding and the
    /// bottom marker). With the per-session bottom-anchored scroll view this keeps
    /// the empty states at their previous top position instead of pinning the
    /// short content to the bottom edge of the chat area.
    @ViewBuilder
    private func emptySessionStateView(viewportHeight: CGFloat) -> some View {
        Group {
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
        .frame(minHeight: max(viewportHeight, 0), alignment: .topLeading)
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

    private func workspaceDirectory(for sessionID: String) -> String? {
        state.sessions.first(where: { $0.id == sessionID })?.directory ?? state.currentSession?.directory
    }

    private func openFileInChat(_ resolvedPath: String, workspaceDirectory: String? = nil) {
        guard !resolvedPath.isEmpty else { return }
        if sizeClass == .regular {
            state.previewFilePath = resolvedPath
            state.previewFileWorkspaceDirectory = workspaceDirectory
            state.fileToOpenInFilesTab = nil
            state.fileToOpenInFilesTabWorkspaceDirectory = nil
        } else {
            // iPhone: dock the preview inside chat instead of jumping to the
            // Files tab — keeps the composer (mic / waveform / text box)
            // interactive while the file is open.
            withAnimation(DesignAnimation.spring) {
                inlinePreviewPath = resolvedPath
                inlinePreviewWorkspaceDirectory = workspaceDirectory
            }
            state.fileToOpenInFilesTab = nil
            state.fileToOpenInFilesTabWorkspaceDirectory = nil
        }
    }

    private func openFilesTab() {
        state.selectedTab = RootTab.files.rawValue
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

private struct ComposerAttachmentThumbnail: View {
    let attachment: ComposerImageAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: attachment.thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
            } else {
                RoundedRectangle(cornerRadius: DesignCorners.medium)
                    .fill(DesignColors.Neutral.text.opacity(0.08))
                    .frame(width: 54, height: 54)
                    .overlay(Image(systemName: "photo"))
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, DesignColors.Neutral.textSecondary)
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel(L10n.t(.attachmentRemoveImageAccessibilityLabel))
        }
        .accessibilityIdentifier("chat-attachment-thumbnail")
    }
}

private enum ComposerImageTranscoder {
    static let maxDimension: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.82
    static let maxByteSize = 5 * 1024 * 1024

    enum TranscodeError: LocalizedError {
        case invalidImage
        case tooLarge(Int)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return L10n.t(.attachmentImageReadFailed)
            case .tooLarge(let bytes):
                return L10n.t(.attachmentImageTooLargeAfterCompression, ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            }
        }
    }

    static func makeAttachment(from data: Data) throws -> ComposerImageAttachment {
        guard let image = UIImage(data: data) else { throw TranscodeError.invalidImage }
        let resized = resize(image, maxDimension: maxDimension)
        guard let jpeg = resized.jpegData(compressionQuality: jpegQuality) else { throw TranscodeError.invalidImage }
        guard jpeg.count <= maxByteSize else { throw TranscodeError.tooLarge(jpeg.count) }
        let thumb = resize(resized, maxDimension: 240).jpegData(compressionQuality: 0.75) ?? jpeg
        let base64 = jpeg.base64EncodedString()
        let id = UUID()
        return ComposerImageAttachment(
            id: id,
            filename: "image-\(id.uuidString.prefix(8)).jpg",
            mime: "image/jpeg",
            dataURL: "data:image/jpeg;base64,\(base64)",
            thumbnailData: thumb,
            byteSize: jpeg.count
        )
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private extension View {
    @ViewBuilder
    func opencodeScrollDismissesKeyboard() -> some View {
        #if os(visionOS)
        self
        #else
        self.scrollDismissesKeyboard(.immediately)
        #endif
    }
}

/// Docked file preview panel for iPhone chat. Fills the whole screen except
/// the composer strip at the bottom so the composer (mic, waveform, text box)
/// stays fully interactive while a file is open — no modal sheet covering it.
/// Reuses `FileContentView` for rendering; lifecycle (open/close) is owned by
/// `ChatTabView` via `inlinePreviewPath`.
private struct ChatInlineFilePreview: View {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "FilePreviewSwipe"
    )

    @Bindable var state: AppState
    let filePath: String
    let workspaceDirectory: String?
    let onClose: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var overlayEnabled: Bool { sizeClass != .regular }

    var body: some View {
        VStack(spacing: 0) {
            FileContentView(
                state: state,
                filePath: filePath,
                workspaceDirectory: workspaceDirectory
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        ChatInlineFilePreview.logger.info("filePreviewSwipe close via toolbar xmark")
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityIdentifier("inline-preview-close")
                    .accessibilityLabel(L10n.t(.appClose))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .leading) {
            LeadingEdgeSwipeCatcher(
                isEnabled: overlayEnabled,
                onEvent: { event in
                    ChatInlineFilePreview.logger.info("\(event, privacy: .public)")
                },
                onClose: {
                    ChatInlineFilePreview.logger.info("filePreviewSwipe close via edge swipe")
                    onClose()
                }
            )
            .frame(width: FilePreviewEdgeSwipeBehavior.edgeThreshold)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .onAppear {
            ChatInlineFilePreview.logger.info(
                "filePreviewSwipe appear path=\(filePath, privacy: .public) sizeClass=\(String(describing: sizeClass), privacy: .public) overlay=\(overlayEnabled, privacy: .public)"
            )
        }
        .onChange(of: sizeClass) { _, newValue in
            ChatInlineFilePreview.logger.info(
                "filePreviewSwipe sizeClass=\(String(describing: newValue), privacy: .public) overlay=\(newValue != .regular, privacy: .public)"
            )
        }
        .accessibilityIdentifier("chat-inline-file-preview")
    }
}

/// UIKit hit target for the left-edge dismiss strip. SwiftUI `Color.clear`
/// overlays do not reliably win hit-testing over `WKWebView`, so the
/// preview close gesture never even starts. A real `UIView` claims the
/// leftmost 32pt and keeps tracking after the finger leaves that strip.
private struct LeadingEdgeSwipeCatcher: UIViewRepresentable {
    var isEnabled: Bool
    var onEvent: (String) -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onEvent: onEvent, onClose: onClose)
    }

    func makeUIView(context: Context) -> FilePreviewEdgeSwipeHitView {
        let view = FilePreviewEdgeSwipeHitView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = isEnabled
        view.onTouchBegan = { point in
            context.coordinator.noteTouchBegan(point)
        }
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        return view
    }

    func updateUIView(_ uiView: FilePreviewEdgeSwipeHitView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onEvent = onEvent
        context.coordinator.onClose = onClose
        uiView.isUserInteractionEnabled = isEnabled
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    final class Coordinator: NSObject {
        var isEnabled: Bool
        var onEvent: (String) -> Void
        var onClose: () -> Void
        weak var pan: UIPanGestureRecognizer?
        private var touchStart: CGPoint?
        private var lastLoggedStep = -1

        init(isEnabled: Bool, onEvent: @escaping (String) -> Void, onClose: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onEvent = onEvent
            self.onClose = onClose
        }

        func emit(_ message: String) {
            onEvent(message)
        }

        func noteTouchBegan(_ point: CGPoint) {
            touchStart = point
            emit(
                "filePreviewSwipe touchBegan x=\(LeadingEdgeSwipeCatcher.fmt(point.x)) y=\(LeadingEdgeSwipeCatcher.fmt(point.y)) enabled=\(isEnabled)"
            )
        }

        /// Pan `.began` fires after the finger has already moved. Using that
        /// location as the edge origin falsely rejects real left-edge starts
        /// (`touchBegan x=7` then `began startX=73`). Measure from touch-down.
        private func swipeState(in view: UIView, gesture: UIPanGestureRecognizer) -> (start: CGPoint, translation: CGSize) {
            let current = gesture.location(in: view)
            let start = touchStart ?? current
            return (
                start,
                CGSize(width: current.x - start.x, height: current.y - start.y)
            )
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let state = swipeState(in: view, gesture: gesture)
            switch gesture.state {
            case .began:
                lastLoggedStep = 0
                let panX = gesture.location(in: view).x
                emit(
                    "filePreviewSwipe began startX=\(LeadingEdgeSwipeCatcher.fmt(state.start.x)) panX=\(LeadingEdgeSwipeCatcher.fmt(panX)) enabled=\(isEnabled)"
                )
            case .changed:
                let step = Int(abs(state.translation.width) / 36)
                guard step != lastLoggedStep else { return }
                lastLoggedStep = step
                let decision = EdgeSwipeGeometry.decision(
                    startLocation: state.start,
                    translation: state.translation
                )
                emit(
                    "filePreviewSwipe changed startX=\(LeadingEdgeSwipeCatcher.fmt(state.start.x)) dx=\(LeadingEdgeSwipeCatcher.fmt(state.translation.width)) dy=\(LeadingEdgeSwipeCatcher.fmt(state.translation.height)) decision=\(decision.rawValue)"
                )
            case .ended, .cancelled, .failed:
                let decision = EdgeSwipeGeometry.decision(
                    startLocation: state.start,
                    translation: state.translation
                )
                emit(
                    "filePreviewSwipe \(gesture.state == .ended ? "ended" : "cancelled") startX=\(LeadingEdgeSwipeCatcher.fmt(state.start.x)) dx=\(LeadingEdgeSwipeCatcher.fmt(state.translation.width)) dy=\(LeadingEdgeSwipeCatcher.fmt(state.translation.height)) decision=\(decision.rawValue) enabled=\(isEnabled)"
                )
                if gesture.state == .ended, isEnabled, decision == .accept {
                    onClose()
                }
                touchStart = nil
            default:
                break
            }
        }
    }
}

private final class FilePreviewEdgeSwipeHitView: UIView {
    var onTouchBegan: ((CGPoint) -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, bounds.contains(point) else {
            return nil
        }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self) {
            onTouchBegan?(point)
        }
        super.touchesBegan(touches, with: event)
    }
}

private struct VoiceRailWaveformView: View {
    enum Mode {
        case idle
        case active
        case generating
    }

    var mode: Mode
    var color: Color
    var level: Float = 0

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 5
    @State private var history: [Float] = Array(repeating: 0.02, count: 64)
    @State private var lastTick: TimeInterval = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: mode == .idle)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let centerY = size.height / 2
                let barCount = max(1, Int((size.width + barSpacing) / (barWidth + barSpacing)))
                let bars = currentBars(at: t, count: barCount)

                for index in 0..<bars.count {
                    let height = max(2, bars[index] * (size.height - 2))
                    let x = CGFloat(index) * (barWidth + barSpacing)
                    let rect = CGRect(
                        x: x,
                        y: centerY - height / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: min(2, height / 2)), with: .color(color))
                }
            }
            .onChange(of: timeline.date) {
                if mode == .active {
                    advanceHistory(at: t)
                } else if mode == .idle && history.contains(where: { $0 > 0.03 }) {
                    history = history.map { $0 * 0.6 }
                }
            }
        }
        .opacity(mode == .idle ? 0.55 : 1)
    }

    private func advanceHistory(at t: TimeInterval) {
        guard t - lastTick >= 1.0 / 30.0 else { return }
        lastTick = t
        let sample = max(Float(0.04), min(level, 1))
        history.removeFirst()
        history.append(sample)
    }

    private func currentBars(at t: TimeInterval, count: Int) -> [CGFloat] {
        switch mode {
        case .idle:
            return Array(repeating: 0.03, count: count)
        case .active:
            if history.count >= count {
                return history.suffix(count).map { CGFloat($0) }
            }
            return Array(repeating: 0.03, count: count - history.count) + history.map { CGFloat($0) }
        case .generating:
            let position = (t * 12.0).truncatingRemainder(dividingBy: Double(count))
            return (0..<count).map { index in
                let distance = min(
                    abs(Double(index) - position),
                    Double(count) - abs(Double(index) - position)
                )
                let intensity = max(0, 1 - distance / 3)
                return CGFloat(0.05 + intensity * 0.85)
            }
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
