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
        case finalized(sessionID: String)
    }

    var messages: [MessageWithParts] = []
    var partsByMessage: [String: [Part]] = [:]
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
    /// Pruned on session-scoped clears.
    var stepTimings: [String: StepTiming] = [:]

    /// partID -> part type, keyed by "\(sessionID):\(partID)". Populated from
    /// `message.part.updated` (which carries the part's `type`) before any of
    /// that part's `message.part.delta` events arrive. The delta event carries
    /// only `field`, which the server sets to "text" for BOTH reasoning and
    /// text parts, so this map is what lets us stamp first-text only for
    /// genuine text parts. First write wins: a part's type never changes.
    private var partTypes: [String: String] = [:]

    struct StepTiming {
        let sessionID: String
        /// Client time the first visible output token arrived (text or a tool
        /// call's JSON input; reasoning is excluded because `outputTokens`
        /// excludes it too). Nil until one does.
        var firstVisibleAt: Date?
        /// Client time the most recent visible output token arrived. Together
        /// with `firstVisibleAt` this forms the decoding window.
        var lastVisibleAt: Date?
        /// Output tokens reported by the step-finish part.
        var outputTokens: Int?

        /// Decoding throughput: output tokens over the visible streaming window
        /// (first token -> last token). Excludes prefill, which sits before the
        /// first token, and tool execution, which sits after the last one (the
        /// step-finish part only arrives once the step's tools have run, so it
        /// is never used as a window end). Nil unless both ends were observed
        /// and the step reported its output tokens.
        var decode: Double? {
            guard let first = firstVisibleAt, let last = lastVisibleAt,
                  let out = outputTokens, out > 0 else { return nil }
            let window = last.timeIntervalSince(first)
            guard window > 0 else { return nil }
            return Double(out) / window
        }

        var decodeLabel: String? {
            guard let d = decode else { return nil }
            let text = d >= 10 ? String(Int(d.rounded())) : String(format: "%.1f", d)
            return "\(text) t/s decoding"
        }
    }

    /// Marks that the step's assistant message was observed before any of its
    /// tokens arrived. Only steps with an entry get a decoding window: if the
    /// client joined mid-step, a truncated window would fabricate a number.
    func recordStepStart(_ messageID: String, sessionID: String) {
        guard stepTimings[messageID] == nil else { return }
        stepTimings[messageID] = StepTiming(sessionID: sessionID)
    }

    /// Stamps one visible output token (text or tool-call input): the first
    /// sighting opens the decoding window, every sighting moves its end. No-op
    /// unless the step start was already observed; see `recordStepStart`.
    func recordVisibleToken(_ messageID: String, sessionID: String) {
        let now = Date()
        if stepTimings[messageID]?.firstVisibleAt == nil {
            stepTimings[messageID]?.firstVisibleAt = now
        }
        stepTimings[messageID]?.lastVisibleAt = now
    }

    /// No-op unless the step start was already observed (see
    /// `recordVisibleToken`).
    func recordStepFinish(_ messageID: String, sessionID: String, outputTokens: Int?) {
        if let out = outputTokens {
            stepTimings[messageID]?.outputTokens = out
        }
    }

    func removeTimings(forSession sessionID: String) {
        for (id, timing) in stepTimings where timing.sessionID == sessionID {
            stepTimings[id] = nil
        }
    }

    func recordPartType(sessionID: String, partID: String, type: String) {
        let key = "\(sessionID):\(partID)"
        if partTypes[key] == nil {
            partTypes[key] = type
        }
    }

    func partType(for partID: String, inSession sessionID: String) -> String? {
        partTypes["\(sessionID):\(partID)"]
    }

    func removePartTypes(forSession sessionID: String) {
        for key in partTypes.keys where key.hasPrefix("\(sessionID):") {
            partTypes[key] = nil
        }
    }

    func clearPartTypes() {
        partTypes = [:]
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

    func applyMessagePartUpdate(
        properties: [String: AnyCodable],
        currentSessionID: String?
    ) -> MessagePartUpdateOutcome {
        guard let sessionID = properties["sessionID"]?.value as? String,
              sessionID == currentSessionID,
              let partObject = properties["part"]?.value as? [String: Any],
              partObject["messageID"] as? String != nil,
              let partID = partObject["id"] as? String else {
            return .ignored
        }

        let partType = (partObject["type"] as? String) ?? "text"
        recordPartType(sessionID: sessionID, partID: partID, type: partType)
        return .finalized(sessionID: sessionID)
    }
}
