//
//  MessageStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
final class MessageStore {
    enum MessagePartUpdateOutcome {
        case ignored
        case appended(sessionID: String)
        case finalized(sessionID: String)
    }

    var messages: [MessageWithParts] = []
    var partsByMessage: [String: [Part]] = [:]
    /// Delta 累积：key = "messageID:partID"，用于打字机效果
    var streamingPartTexts: [String: String] = [:]
    var streamingReasoningPart: Part? = nil
    private var streamingDraftMessageIDs: Set<String> = []
    /// Optimistic user rows whose server confirmation has not been observed yet.
    /// Rows are keyed by the deterministic `msg_` id sent with the prompt, so
    /// reconciliation against server data is pure id membership.
    var pendingOptimisticMessageIDs: Set<String> = []
    /// Send failures surfaced inline under the affected user row (no alert).
    /// Keyed by message id; cleared when the row is confirmed or removed.
    var failedSendReasonsByID: [String: String] = [:]

    /// Per-step timing captured from the live SSE stream, keyed by assistant
    /// message id. Only populated while the client observed the stream for that
    /// step (best-effort): a restart or a message loaded purely from REST has no
    /// entry, so the footer falls back to the general (persisted) throughput.
    /// Not cleared by `resetStreaming()` (that fires on every message update,
    /// including the step's own start/finish); pruned on session-scoped clears.
    var stepTimings: [String: StepTiming] = [:]

    struct StepTiming {
        let sessionID: String
        /// Client time the step's assistant message was first seen (step start).
        let stepStart: Date
        /// Client time the first visible text token arrived (nil until it does).
        var firstTextAt: Date?
        /// Client time the step-finish part was observed.
        var finishAt: Date?
        /// Output tokens reported by the step-finish part.
        var outputTokens: Int?

        /// Time to first (visible text) token, in seconds, from step start.
        var ttft: Double? {
            guard let first = firstTextAt else { return nil }
            let value = first.timeIntervalSince(stepStart)
            return value > 0 ? value : nil
        }

        /// Decoding throughput: output tokens over the (first-text -> finish)
        /// window. Excludes prefill and reasoning, which sit before first text.
        var decode: Double? {
            guard let first = firstTextAt, let fin = finishAt, let out = outputTokens, out > 0 else { return nil }
            let window = fin.timeIntervalSince(first)
            guard window > 0 else { return nil }
            return Double(out) / window
        }

        var ttftLabel: String? {
            ttft.map { String(format: "%.1fs", $0) }
        }

        var decodeLabel: String? {
            guard let d = decode else { return nil }
            let text = d >= 10 ? String(Int(d.rounded())) : String(format: "%.1f", d)
            return "\(text) t/s decoding"
        }
    }

    func recordStepStart(_ messageID: String, sessionID: String) {
        guard stepTimings[messageID] == nil else { return }
        stepTimings[messageID] = StepTiming(sessionID: sessionID, stepStart: Date())
    }

    func recordFirstText(_ messageID: String, sessionID: String) {
        if stepTimings[messageID] == nil {
            stepTimings[messageID] = StepTiming(sessionID: sessionID, stepStart: Date())
        }
        if stepTimings[messageID]?.firstTextAt == nil {
            stepTimings[messageID]?.firstTextAt = Date()
        }
    }

    func recordStepFinish(_ messageID: String, sessionID: String, outputTokens: Int?) {
        if stepTimings[messageID] == nil {
            stepTimings[messageID] = StepTiming(sessionID: sessionID, stepStart: Date())
        }
        stepTimings[messageID]?.finishAt = Date()
        if let out = outputTokens {
            stepTimings[messageID]?.outputTokens = out
        }
    }

    func removeTimings(forSession sessionID: String) {
        for (id, timing) in stepTimings where timing.sessionID == sessionID {
            stepTimings[id] = nil
        }
    }

    func isPendingOptimisticMessage(_ messageID: String) -> Bool {
        pendingOptimisticMessageIDs.contains(messageID)
    }

    func trackPendingOptimisticMessage(_ messageID: String) {
        pendingOptimisticMessageIDs.insert(messageID)
    }

    func untrackPendingOptimisticMessages(_ messageIDs: Set<String>) {
        pendingOptimisticMessageIDs.subtract(messageIDs)
    }

    func markSendFailed(messageID: String, reason: String) {
        failedSendReasonsByID[messageID] = reason
    }

    func clearSendFailure(messageID: String) {
        failedSendReasonsByID.removeValue(forKey: messageID)
    }

    func pruneSendFailures(loadedMessageIDs: Set<String>) {
        for id in failedSendReasonsByID.keys where loadedMessageIDs.contains(id) {
            failedSendReasonsByID.removeValue(forKey: id)
        }
    }

    var hasActiveStreaming: Bool {
        streamingReasoningPart != nil || !streamingPartTexts.isEmpty || !streamingDraftMessageIDs.isEmpty
    }

    func resetStreaming() {
        streamingReasoningPart = nil
        streamingPartTexts = [:]
        streamingDraftMessageIDs.removeAll()
    }

    func isStreamingDraftMessage(_ messageID: String) -> Bool {
        streamingDraftMessageIDs.contains(messageID)
    }

    func removeStreamingDraftMessages(_ messageIDs: Set<String>) {
        streamingDraftMessageIDs.subtract(messageIDs)
    }

    func upsertStreamingMessage(
        messageID: String,
        partID: String,
        sessionID: String,
        type: String,
        text: String
    ) {
        let part = Part(
            id: partID,
            messageID: messageID,
            sessionID: sessionID,
            type: type,
            text: text,
            tool: nil,
            callID: nil,
            state: nil,
            metadata: nil,
            files: nil
        )

        if let idx = messages.firstIndex(where: { $0.info.id == messageID }) {
            let current = messages[idx]
            var updatedParts = current.parts
            if let partIdx = updatedParts.firstIndex(where: { $0.id == partID }) {
                updatedParts[partIdx] = part
            } else {
                updatedParts.append(part)
            }

            messages[idx] = MessageWithParts(info: current.info, parts: updatedParts)
            partsByMessage[messageID] = updatedParts
            streamingDraftMessageIDs.insert(messageID)
            return
        }

        let now = Int(Date().timeIntervalSince1970 * 1000)
        let message = Message(
            id: messageID,
            sessionID: sessionID,
            role: "assistant",
            parentID: messages.last?.info.id,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: Message.TimeInfo(created: now, completed: now),
            finish: nil,
            tokens: nil,
            cost: nil
        )

        messages.append(MessageWithParts(info: message, parts: [part]))
        partsByMessage[messageID] = [part]
        streamingDraftMessageIDs.insert(messageID)
    }

    func appendStreamingDelta(
        messageID: String,
        partID: String,
        sessionID: String,
        type: String,
        delta: String
    ) {
        let key = "\(messageID):\(partID)"
        let text = (streamingPartTexts[key] ?? "") + delta
        streamingPartTexts[key] = text

        if type == "reasoning" {
            streamingReasoningPart = Part(
                id: partID,
                messageID: messageID,
                sessionID: sessionID,
                type: "reasoning",
                text: nil,
                tool: nil,
                callID: nil,
                state: nil,
                metadata: nil,
                files: nil
            )
        } else {
            upsertStreamingMessage(
                messageID: messageID,
                partID: partID,
                sessionID: sessionID,
                type: type,
                text: text
            )
        }
    }

    func applyMessagePartUpdate(
        properties: [String: AnyCodable],
        currentSessionID: String?
    ) -> MessagePartUpdateOutcome {
        guard let sessionID = properties["sessionID"]?.value as? String,
              sessionID == currentSessionID,
              let partObject = properties["part"]?.value as? [String: Any],
              let messageID = partObject["messageID"] as? String,
              let partID = partObject["id"] as? String else {
            return .ignored
        }

        let partType = (partObject["type"] as? String) ?? "text"

        if let delta = properties["delta"]?.value as? String,
           !delta.isEmpty {
            appendStreamingDelta(
                messageID: messageID,
                partID: partID,
                sessionID: sessionID,
                type: partType,
                delta: delta
            )
            return .appended(sessionID: sessionID)
        }

        clearStreamingState(messageID: messageID)
        return .finalized(sessionID: sessionID)
    }

    func clearStreamingState(messageID: String) {
        for key in streamingPartTexts.keys where key.hasPrefix("\(messageID):") {
            streamingPartTexts.removeValue(forKey: key)
        }

        if streamingReasoningPart?.messageID == messageID {
            streamingReasoningPart = nil
        }
        streamingDraftMessageIDs.remove(messageID)
    }
}
