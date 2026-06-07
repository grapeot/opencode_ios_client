//
//  SessionDisplayState.swift
//  OpenCodeClient
//

import Foundation

/// The five mutually exclusive display states a session can be in, used to
/// drive its row indicator color and ordering. Derived purely from session
/// data — see `derive(session:status:isBlocked:lastViewedAt:staleThreshold:now:)`.
enum SessionDisplayState {
    /// Blocked: a pending permission or question is waiting for this session.
    case needsYou
    /// Actively working: `SessionStatus.type` is "busy" or "retry".
    case running
    /// Idle, updated after it was last viewed (or never viewed).
    case doneUnread
    /// Idle, viewed at or after its last update.
    case doneRead
    /// Idle, not updated within the stale threshold.
    case stale

    /// Default stale threshold: 24 hours in milliseconds.
    static let defaultStaleThreshold = 24 * 60 * 60 * 1000

    /// Maps a session to its display state. Pure and testable — inject `now`.
    ///
    /// Priority order:
    /// 1. `isBlocked` → `.needsYou`
    /// 2. status "busy"/"retry" → `.running`
    /// 3. idle, never viewed or updated after last view → `.doneUnread`
    /// 4. idle, stale (older than threshold) → `.stale`
    /// 5. otherwise → `.doneRead`
    ///
    /// - Parameters:
    ///   - session: The session to classify.
    ///   - status: The session's status, if known.
    ///   - isBlocked: Whether a permission/question is pending for this session.
    ///   - lastViewedAt: When the user last viewed this session, in milliseconds
    ///     since epoch; `nil` if never viewed.
    ///   - staleThreshold: Age (in ms) beyond which an idle session is stale.
    ///   - now: Current time in milliseconds since epoch.
    static func derive(
        session: Session,
        status: SessionStatus?,
        isBlocked: Bool,
        lastViewedAt: Int?,
        staleThreshold: Int = defaultStaleThreshold,
        now: Int
    ) -> SessionDisplayState {
        if isBlocked {
            return .needsYou
        }
        if status?.type == "busy" || status?.type == "retry" {
            return .running
        }
        let updated = session.time.updated
        if lastViewedAt == nil || lastViewedAt! < updated {
            return .doneUnread
        }
        if now - updated > staleThreshold {
            return .stale
        }
        return .doneRead
    }
}
