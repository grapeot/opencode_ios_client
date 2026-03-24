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
            variant: nil,
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
