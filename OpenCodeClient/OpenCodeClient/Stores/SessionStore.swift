//
//  SessionStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
final class SessionStore {
    var sessions: [Session] = []
    var currentSessionID: String?
    var sessionStatuses: [String: SessionStatus] = [:]
}
