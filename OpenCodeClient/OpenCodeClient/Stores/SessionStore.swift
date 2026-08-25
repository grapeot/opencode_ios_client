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
    let defaults: UserDefaults

    var currentSessionID: String? {
        didSet {
            if let id = currentSessionID {
                defaults.set(id, forKey: Self.currentSessionIDKey)
            } else {
                defaults.removeObject(forKey: Self.currentSessionIDKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentSessionID = defaults.string(forKey: Self.currentSessionIDKey)
    }
}
