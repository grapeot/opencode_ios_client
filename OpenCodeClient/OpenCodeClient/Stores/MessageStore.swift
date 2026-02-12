//
//  MessageStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
final class MessageStore {
    var messages: [MessageWithParts] = []
    var partsByMessage: [String: [Part]] = [:]
    /// Delta 累积：key = "messageID:partID"，用于打字机效果
    var streamingPartTexts: [String: String] = [:]
}
