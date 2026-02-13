import Foundation

enum ActivityTracker {
    static let debounceWindowSeconds: TimeInterval = 2.5

    static func updateSessionActivity(
        sessionID: String,
        previous: SessionStatus?,
        current: SessionStatus,
        existing: SessionActivity?,
        messages: [MessageWithParts],
        currentSessionID: String?,
        hasActiveStreaming: Bool = false,
        now: Date = Date()
    ) -> SessionActivity? {
        let wasBusy = isBusyStatus(previous)
        let nowBusy = isBusyStatus(current)

        let message = current.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let opText = (message?.isEmpty == false)
            ? message!
            : (current.type == "retry" ? "Retrying" : "Thinking")

        if nowBusy {
            if !wasBusy || existing?.state != .running {
                let derivedStart = lastUserMessageCreatedAt(sessionID: sessionID, messages: messages) ?? now
                return SessionActivity(
                    sessionID: sessionID,
                    state: .running,
                    text: opText,
                    startedAt: derivedStart,
                    endedAt: nil,
                    anchorMessageID: nil
                )
            }

            if var running = existing {
                running.text = opText
                running.anchorMessageID = nil
                return running
            }
        }

        if wasBusy, var completed = existing {
            if hasActiveStreaming || hasRunningAssistantWork(sessionID: sessionID, messages: messages) {
                completed.state = .running
                completed.endedAt = nil
                completed.anchorMessageID = nil
                return completed
            }

            let completion = lastAssistantMessageCompletedAtOrAfter(
                sessionID: sessionID,
                messages: messages,
                threshold: completed.startedAt
            )
            if completion == nil {
                completed.state = .running
                completed.endedAt = nil
                completed.anchorMessageID = nil
                return completed
            }

            completed.state = .completed
            completed.endedAt = completion ?? now
            if sessionID == currentSessionID {
                completed.anchorMessageID = messages.last?.info.id
            }
            return completed
        }

        return existing
    }

    static func bestSessionActivityText(
        sessionID: String,
        currentSessionID: String?,
        sessionStatuses: [String: SessionStatus],
        messages: [MessageWithParts],
        streamingReasoningPart: Part?,
        streamingPartTexts: [String: String]
    ) -> String {
        if let status = sessionStatuses[sessionID],
           let msg = status.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !msg.isEmpty {
            return msg
        }

        if let part = lastAssistantToolPart(sessionID: sessionID, state: "running", messages: messages),
           let mapped = formatStatusFromPart(part) {
            return mapped
        }

        if sessionID == currentSessionID,
           let part = streamingReasoningPart,
           part.sessionID == sessionID {
            let key = "\(part.messageID):\(part.id)"
            let text = streamingPartTexts[key] ?? ""
            return formatThinkingFromReasoningText(text)
        }

        if let part = lastAssistantPart(sessionID: sessionID, messages: messages),
           let mapped = formatStatusFromPart(part) {
            return mapped
        }

        return "Thinking"
    }

    static func debounceDelay(lastChangeAt: Date?, now: Date, window: TimeInterval = debounceWindowSeconds) -> TimeInterval {
        let last = lastChangeAt ?? .distantPast
        let delta = now.timeIntervalSince(last)
        if delta >= window { return 0 }
        return max(0, window - delta)
    }

    static func formatThinkingFromReasoningText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let topic = extractLeadingBoldTopic(from: trimmed) {
            return "Thinking - \(topic)"
        }
        return "Thinking"
    }

    static func formatStatusFromPart(_ part: Part) -> String? {
        if part.isTool {
            let base: String? = {
                switch part.tool {
                case "task":
                    return "Delegating"
                case "todowrite", "todoread":
                    return "Planning"
                case "read":
                    return "Gathering context"
                case "list", "grep", "glob":
                    return "Searching codebase"
                case "webfetch":
                    return "Searching web"
                case "edit", "write":
                    return "Making edits"
                case "bash":
                    return "Running commands"
                default:
                    return nil
                }
            }()

            let topic = (part.toolReason ?? part.toolInputSummary)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let base, let topic, !topic.isEmpty {
                return "\(base) - \(topic)"
            }
            return base
        }

        if part.isReasoning {
            return formatThinkingFromReasoningText(part.text ?? "")
        }

        if part.isText {
            return "Gathering thoughts"
        }

        return nil
    }

    private static func isBusyStatus(_ status: SessionStatus?) -> Bool {
        guard let type = status?.type else { return false }
        return type == "busy" || type == "retry"
    }

    private static func lastUserMessageCreatedAt(sessionID: String, messages: [MessageWithParts]) -> Date? {
        for msg in messages.reversed() {
            if msg.info.sessionID != sessionID { continue }
            if msg.info.isUser {
                return Date(timeIntervalSince1970: Double(msg.info.time.created) / 1000.0)
            }
        }
        return nil
    }

    private static func lastAssistantMessageCompletedAtOrAfter(sessionID: String, messages: [MessageWithParts], threshold: Date) -> Date? {
        for msg in messages.reversed() {
            if msg.info.sessionID != sessionID { continue }
            if msg.info.isAssistant, let completed = msg.info.time.completed {
                let date = Date(timeIntervalSince1970: Double(completed) / 1000.0)
                if date >= threshold {
                    return date
                }
            }
        }
        return nil
    }

    private static func hasRunningAssistantWork(sessionID: String, messages: [MessageWithParts]) -> Bool {
        for msg in messages.reversed() where msg.info.sessionID == sessionID {
            guard msg.info.isAssistant else { continue }
            for part in msg.parts.reversed() {
                if !part.isTool { continue }
                let state = part.stateDisplay?.lowercased() ?? ""
                if state == "running" || state == "pending" {
                    return true
                }
            }
        }
        return false
    }

    private static func lastAssistantPart(sessionID: String, messages: [MessageWithParts]) -> Part? {
        for msg in messages.reversed() where msg.info.sessionID == sessionID {
            guard msg.info.isAssistant else { continue }
            for part in msg.parts.reversed() {
                if part.isStepStart || part.isStepFinish { continue }
                return part
            }
        }
        return nil
    }

    private static func lastAssistantToolPart(sessionID: String, state: String, messages: [MessageWithParts]) -> Part? {
        for msg in messages.reversed() where msg.info.sessionID == sessionID {
            guard msg.info.isAssistant else { continue }
            for part in msg.parts.reversed() {
                guard part.isTool else { continue }
                if part.stateDisplay?.lowercased() == state { return part }
            }
        }
        return nil
    }

    private static func extractLeadingBoldTopic(from text: String) -> String? {
        let pattern = "^\\s*\\*\\*(.+?)\\*\\*"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2 else { return nil }
        let topic = (text as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty ? nil : topic
    }
}
