//
//  SessionStatsStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

/// Per-session cumulative counters for the status line: rounds (user
/// messages) and tool calls (tool parts). The server has no aggregate for
/// these, and fetching the full message history just to count is too heavy,
/// so the client maintains them locally:
///
/// - Increments arrive with the SSE events the app already consumes
///   (`message.updated` for user rows, `message.part.updated` for tool
///   parts), deduplicated by ID so replays and reconnects never double-count.
/// - After each message-list load the loaded window is reconciled against the
///   seen sets. Reconciliation only ever adds ids; the counts never decrease
///   here.
/// - When the loaded window covers the full history (no older page left),
///   the window is ground truth: counts are recomputed exactly and the
///   baseline is marked complete.
/// - A revert truncates history beyond what any loaded window can observe,
///   so the caller resets the stats from the post-revert window
///   (`resetForRevert`), accepting the documented transient inaccuracy.
///
/// Token totals are NOT maintained here: the server already pushes the
/// session-level cumulative `tokens` on the session object (see
/// `Session.tokens`), and the view falls back to a window sum only when a
/// host omits the field.
@Observable
final class SessionStatsStore {
    struct SessionStats: Codable, Equatable {
        var rounds: Int = 0
        var toolCalls: Int = 0
        var seenUserMessageIDs: Set<String> = []
        var seenToolPartIDs: Set<String> = []
        var baselineComplete: Bool = false
    }

    private(set) var statsBySession: [String: SessionStats] = [:]
    private let defaults: UserDefaults
    private static let storageKey = "sessionStats.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: SessionStats].self, from: data) {
            statsBySession = decoded
        }
    }

    func stats(for sessionID: String) -> SessionStats {
        statsBySession[sessionID] ?? SessionStats()
    }

    /// SSE `message.updated` for a user message: counts once per id.
    /// Returns true when the id was new.
    @discardableResult
    func observeUserMessage(id: String, sessionID: String) -> Bool {
        guard !stats(for: sessionID).seenUserMessageIDs.contains(id) else { return false }
        withStats(sessionID) {
            $0.rounds += 1
            $0.seenUserMessageIDs.insert(id)
        }
        return true
    }

    /// SSE `message.part.updated` for a tool part: counts once per part id.
    /// The unit is the part, not the message: one assistant step can run
    /// several tool parts in parallel.
    @discardableResult
    func observeToolPart(id: String, sessionID: String) -> Bool {
        guard !stats(for: sessionID).seenToolPartIDs.contains(id) else { return false }
        withStats(sessionID) {
            $0.toolCalls += 1
            $0.seenToolPartIDs.insert(id)
        }
        return true
    }

    /// Reconciles against a freshly loaded message window. See the type
    /// documentation for the add-only / exact-recompute rules.
    func reconcile(
        sessionID: String,
        userMessageIDs: Set<String>,
        toolPartIDs: Set<String>,
        isComplete: Bool
    ) {
        withStats(sessionID) { stats in
            if isComplete {
                stats.rounds = userMessageIDs.count
                stats.toolCalls = toolPartIDs.count
                stats.seenUserMessageIDs = userMessageIDs
                stats.seenToolPartIDs = toolPartIDs
                stats.baselineComplete = true
            } else {
                stats.rounds += userMessageIDs.subtracting(stats.seenUserMessageIDs).count
                stats.toolCalls += toolPartIDs.subtracting(stats.seenToolPartIDs).count
                stats.seenUserMessageIDs.formUnion(userMessageIDs)
                stats.seenToolPartIDs.formUnion(toolPartIDs)
            }
        }
    }

    /// Post-revert reset: the reloaded window is all that can be trusted.
    /// `baselineComplete` is demoted because the window may be partial.
    func resetForRevert(
        sessionID: String,
        userMessageIDs: Set<String>,
        toolPartIDs: Set<String>
    ) {
        withStats(sessionID) {
            $0.rounds = userMessageIDs.count
            $0.toolCalls = toolPartIDs.count
            $0.seenUserMessageIDs = userMessageIDs
            $0.seenToolPartIDs = toolPartIDs
            $0.baselineComplete = false
        }
    }

    func remove(sessionID: String) {
        guard statsBySession[sessionID] != nil else { return }
        statsBySession[sessionID] = nil
        save()
    }

    private func withStats(_ sessionID: String, _ mutate: (inout SessionStats) -> Void) {
        var stats = statsBySession[sessionID] ?? SessionStats()
        mutate(&stats)
        statsBySession[sessionID] = stats
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(statsBySession) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
