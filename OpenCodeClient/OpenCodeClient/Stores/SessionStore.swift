//
//  SessionStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
final class SessionStore {
    var sessions: [Session] = []
    var sessionStatuses: [String: SessionStatus] = [:]

    private static let currentSessionIDKey = "currentSessionID"

    var currentSessionID: String? {
        didSet {
            // Persist to UserDefaults whenever it changes
            if let id = currentSessionID {
                UserDefaults.standard.set(id, forKey: Self.currentSessionIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentSessionIDKey)
            }
        }
    }

    init() {
        // Restore persisted session ID on init
        currentSessionID = UserDefaults.standard.string(forKey: Self.currentSessionIDKey)
    }
}
