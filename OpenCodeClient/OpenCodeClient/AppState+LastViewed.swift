import Foundation

/// Per-session last-viewed timestamp persistence. Records when the user last
/// opened a session so the row can render read/unread state (see
/// `SessionDisplayState.derive`). State lives on `AppState` (declared next to
/// the other per-session maps) so SwiftUI observation works; only behavior
/// lives here. Mirrors the persistence shape of `AppState+Drafts.swift`.
extension AppState {
    /// Last-viewed timestamp (ms since epoch) for a session, or nil if never viewed.
    func lastViewedAt(for sessionID: String?) -> Int? {
        guard let sessionID else { return nil }
        return lastViewedAtBySessionID[sessionID]
    }

    /// Stamps the current time (ms since epoch) as the session's last-viewed time
    /// and persists the map to UserDefaults.
    func markSessionViewed(_ sessionID: String) {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        lastViewedAtBySessionID[sessionID] = now

        if lastViewedAtBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.lastViewedAtBySessionKey)
            return
        }
        if let data = try? JSONEncoder().encode(lastViewedAtBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.lastViewedAtBySessionKey)
        }
    }
}
