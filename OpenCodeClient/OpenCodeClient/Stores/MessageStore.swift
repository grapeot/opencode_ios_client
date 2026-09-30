//
//  MessageStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
final class MessageStore {
    /// Result of applying an SSE part payload in place.
    /// - applied: local state updated, no REST needed.
    /// - needsReconcile: payload is incomplete for its part type (e.g. a thin
    ///   shim-shape part); the caller falls back to the REST reconciliation
    ///   path so behavior matches the pre-SSE-data-path host.
    /// - ignored: payload is complete but intentionally a no-op (e.g. a text
    ///   part for a row not loaded yet); nothing to apply and no REST needed.
    enum PartUpsertOutcome {
        case applied
        case needsReconcile
        case ignored
    }

    /// Part types that only ever belong to assistant messages. These may
    /// create a placeholder (shell) row when they arrive before the
    /// `message.updated` that would have created the row (reconnect miss or
    /// reordering). Text/file parts must not create shell rows: their role is
    /// ambiguous (user or assistant), so a premature row would misrender.
    private static let assistantShellPartTypes: Set<String> = ["tool", "reasoning", "step-finish", "patch"]

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
    /// step (best-effort): a message loaded purely from REST has no entry, so
    /// the footer falls back to the general (persisted) throughput. Completed
    /// steps (one with an observed step-finish token count) survive app
    /// restarts via `defaults`; incomplete ones do not, since a truncated
    /// window would fabricate a number. Pruned on session-scoped clears.
    var stepTimings: [String: StepTiming] = [:]

    private let defaults: UserDefaults
    private static let timingsKey = "stepTimings.v1"
    private static let maxPersistedTimings = 200

    private struct PersistedTiming: Codable {
        let sessionID: String
        let firstVisibleAt: Double?
        let lastVisibleAt: Double?
        let outputTokens: Int?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadTimings()
    }

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
    /// `recordVisibleToken`). A token count finalizes the decoding window, so
    /// this is the only moment the entry is persisted: first/last timestamps
    /// and the output count are all settled by then.
    func recordStepFinish(_ messageID: String, sessionID: String, outputTokens: Int?) {
        guard let out = outputTokens, stepTimings[messageID]?.outputTokens == nil else { return }
        stepTimings[messageID]?.outputTokens = out
        persistTimings()
    }

    func removeTimings(forSession sessionID: String) {
        for (id, timing) in stepTimings where timing.sessionID == sessionID {
            stepTimings[id] = nil
        }
        persistTimings()
    }

    private func loadTimings() {
        guard let data = defaults.data(forKey: Self.timingsKey),
              let saved = try? JSONDecoder().decode([String: PersistedTiming].self, from: data)
        else { return }
        for (id, saved) in saved
        where saved.outputTokens != nil && saved.firstVisibleAt != nil {
            stepTimings[id] = StepTiming(
                sessionID: saved.sessionID,
                firstVisibleAt: Date(timeIntervalSince1970: saved.firstVisibleAt! / 1000),
                lastVisibleAt: saved.lastVisibleAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                outputTokens: saved.outputTokens
            )
        }
    }

    private func persistTimings() {
        var snapshot: [String: PersistedTiming] = [:]
        for (id, timing) in stepTimings where timing.outputTokens != nil {
            snapshot[id] = PersistedTiming(
                sessionID: timing.sessionID,
                firstVisibleAt: timing.firstVisibleAt.map { $0.timeIntervalSince1970 * 1000 },
                lastVisibleAt: timing.lastVisibleAt.map { $0.timeIntervalSince1970 * 1000 },
                outputTokens: timing.outputTokens
            )
        }
        if snapshot.count > Self.maxPersistedTimings {
            let newestFirst = snapshot.sorted { ($0.value.lastVisibleAt ?? 0) > ($1.value.lastVisibleAt ?? 0) }
            snapshot = Dictionary(uniqueKeysWithValues: Array(newestFirst.prefix(Self.maxPersistedTimings)).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.timingsKey)
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

    /// Completeness gate for the SSE data path, per part type:
    /// - tool: the payload must carry a decodable `state` (the tool's
    ///   status/input/output/time). A tool part without state is the thin
    ///   shim shape and cannot render tool status locally.
    /// - text/reasoning: the `text` field must be present. An empty string is
    ///   valid (the start frame) — only an absent field fails.
    /// - other types (step-start, step-finish, patch, file, ...): accept as-is;
    ///   none of them have a critical local-render field that a thin payload
    ///   would omit.
    private func isPayloadComplete(_ part: Part) -> Bool {
        switch part.type {
        case "tool":
            return part.state != nil
        case "text", "reasoning":
            return part.text != nil
        default:
            return true
        }
    }

    /// Applies a full part payload in place (SSE data path): replace-or-insert
    /// the part inside its message row, creating a shell row for
    /// assistant-only part types when the row is not loaded yet.
    func upsertPart(_ part: Part) -> PartUpsertOutcome {
        guard isPayloadComplete(part) else { return .needsReconcile }

        if let rowIndex = messages.firstIndex(where: { $0.info.id == part.messageID }) {
            var row = messages[rowIndex]
            if let partIndex = row.parts.firstIndex(where: { $0.id == part.id }) {
                row.parts[partIndex] = part
            } else {
                // Server parts never reuse temp ids. Drop the row's optimistic
                // temp parts of the same type so a server part never renders
                // side-by-side with its placeholder. This cannot rely on the
                // pending flag alone: for user messages the `message.updated`
                // (which untracks the row) arrives before the text part
                // event, and without this the placeholder text would linger
                // next to the server text (duplicated bubble content).
                row.parts.removeAll { $0.id.hasPrefix("temp-") && $0.type == part.type }
                if isPendingOptimisticMessage(part.messageID) {
                    row.parts.removeAll { $0.id.hasPrefix("temp-") }
                }
                row.parts.append(part)
            }
            messages[rowIndex] = row
            partsByMessage[part.messageID] = row.parts
            return .applied
        }

        guard Self.assistantShellPartTypes.contains(part.type) else {
            // A text/file part for a row we do not have: wait for the
            // `message.updated` (or the next reconciliation) instead of
            // creating a row whose role we cannot know.
            return .ignored
        }

        let shell = Message(
            id: part.messageID,
            sessionID: part.sessionID,
            role: "assistant",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: Int(Date().timeIntervalSince1970 * 1000), completed: nil),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        messages.append(MessageWithParts(info: shell, parts: [part]))
        partsByMessage[part.messageID] = [part]
        return .applied
    }

    /// Applies a full message-info payload in place. Replaces the row's info
    /// but keeps its parts (`message.updated` never carries parts; they come
    /// from part events and reconciliations). Creates a shell row (empty
    /// parts) when the row is not loaded yet. A confirmed user message is
    /// untracked from the pending-optimistic set — the same id-membership
    /// semantics as `loadMessages`' optimistic merge — and its inline send
    /// failure (if any) is cleared.
    func upsertMessageInfo(_ info: Message) {
        if let rowIndex = messages.firstIndex(where: { $0.info.id == info.id }) {
            var row = messages[rowIndex]
            row.info = info
            messages[rowIndex] = row
            partsByMessage[info.id] = row.parts
        } else {
            messages.append(MessageWithParts(info: info, parts: []))
            partsByMessage[info.id] = []
        }
        if info.isUser {
            untrackPendingOptimisticMessages([info.id])
            clearSendFailure(messageID: info.id)
        }
    }

    /// Appends a streaming text delta to a locally-known part. No-op when the
    /// part is not loaded (a reconnect that missed the start frame converges
    /// on the part's end frame). Reserved coalescing switch: when
    /// `deltaAppendThrottle` is set, appends inside the window are dropped;
    /// the lost intermediate state converges on the end frame, which carries
    /// the full text.
    var deltaAppendThrottle: TimeInterval? = nil
    private var lastDeltaAppendAt: Date?

    func appendDelta(messageID: String, partID: String, delta: String) {
        if let throttle = deltaAppendThrottle,
           let last = lastDeltaAppendAt,
           Date().timeIntervalSince(last) < throttle {
            return
        }
        lastDeltaAppendAt = Date()
        guard let rowIndex = messages.firstIndex(where: { $0.info.id == messageID }),
              let partIndex = messages[rowIndex].parts.firstIndex(where: { $0.id == partID }) else {
            return
        }
        messages[rowIndex].parts[partIndex].text =
            (messages[rowIndex].parts[partIndex].text ?? "") + delta
    }

    /// Removes one part (SSE `message.part.removed`; the payload carries only
    /// ids). No-op when the row or part is not loaded.
    func removePart(messageID: String, partID: String) {
        guard let rowIndex = messages.firstIndex(where: { $0.info.id == messageID }) else { return }
        guard let partIndex = messages[rowIndex].parts.firstIndex(where: { $0.id == partID }) else { return }
        messages[rowIndex].parts.remove(at: partIndex)
        partsByMessage[messageID] = messages[rowIndex].parts
    }

    /// Removes a whole row (SSE `message.removed`). Mirrors `removeMessage`
    /// housekeeping: drops the parts index entry, untracks the id, and clears
    /// any inline send failure.
    func removeMessageRow(messageID: String) {
        guard messages.contains(where: { $0.info.id == messageID }) else { return }
        messages.removeAll { $0.info.id == messageID }
        partsByMessage[messageID] = nil
        untrackPendingOptimisticMessages([messageID])
        clearSendFailure(messageID: messageID)
    }
}
