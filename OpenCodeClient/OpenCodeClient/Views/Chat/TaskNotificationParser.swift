//
//  TaskNotificationParser.swift
//  OpenCodeClient
//

import Foundation

enum TaskState: String, Equatable {
    case completed
    case error
    case running
}

struct TaskNotification: Equatable {
    let sessionID: String
    let state: TaskState
    let summary: String?
    let resultText: String

    var isFailed: Bool { state == .error }

    var displayTitle: String {
        TaskNotificationParser.displayTitle(summary: summary, sessionID: sessionID)
    }
}

enum TaskNotificationParser {
    static let cardAccessibilityIdentifier = "task-notification-card"
    static let openSessionAccessibilityIdentifier = "task-notification-open-session"
    static let completedSummaryPrefix = "Background task completed: "
    static let failedSummaryPrefix = "Background task failed: "
    static let defaultExpandedCharacterLimit = 500

    static func parse(_ text: String) -> TaskNotification? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isTaskOpen(trimmed), trimmed.hasSuffix("</task>") else { return nil }
        guard let openEnd = tagEnd(in: trimmed, from: trimmed.startIndex) else { return nil }
        let closeStart = trimmed.index(trimmed.endIndex, offsetBy: -"</task>".count)
        guard closeStart >= openEnd else { return nil }

        let attributeSource = trimmed[trimmed.index(trimmed.startIndex, offsetBy: "<task".count)..<trimmed.index(before: openEnd)]
        guard let attributes = attributes(in: attributeSource),
              let sessionID = attributes["id"], !sessionID.isEmpty,
              let stateRaw = attributes["state"],
              let state = TaskState(rawValue: stateRaw) else { return nil }

        let inner = trimmed[openEnd..<closeStart]
        let summary = elementBody("summary", in: inner)
        guard let resultText = resultBody(state: state, in: inner) else { return nil }
        return TaskNotification(
            sessionID: sessionID,
            state: state,
            summary: summary,
            resultText: resultText
        )
    }

    static func displayTitle(summary: String?, sessionID: String) -> String {
        let raw = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stripped = stripSummaryPrefix(raw)
        if !stripped.isEmpty { return stripped }
        return shortSessionID(sessionID)
    }

    static func shortSessionID(_ sessionID: String) -> String {
        if sessionID.count <= 12 { return sessionID }
        return "…" + String(sessionID.suffix(8))
    }

    private static func stripSummaryPrefix(_ summary: String) -> String {
        for prefix in [completedSummaryPrefix, failedSummaryPrefix] where summary.hasPrefix(prefix) {
            return String(summary.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return summary
    }

    private static func isTaskOpen(_ text: String) -> Bool {
        guard text.hasPrefix("<task") else { return false }
        let after = text.index(text.startIndex, offsetBy: "<task".count)
        guard after < text.endIndex else { return false }
        let boundary = text[after]
        return boundary.isWhitespace || boundary == ">"
    }

    private static func tagEnd(in text: String, from open: String.Index) -> String.Index? {
        var index = open
        var quote: Character?
        while index < text.endIndex {
            let char = text[index]
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                }
                index = text.index(after: index)
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                index = text.index(after: index)
                continue
            }
            if char == ">" {
                return text.index(after: index)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func attributes(in source: Substring) -> [String: String]? {
        var index = source.startIndex
        var parsed: [String: String] = [:]
        while index < source.endIndex {
            while index < source.endIndex, source[index].isWhitespace || source[index] == "/" {
                index = source.index(after: index)
            }
            guard index < source.endIndex else { break }
            let nameStart = index
            while index < source.endIndex, isAttributeName(source[index]) {
                index = source.index(after: index)
            }
            guard nameStart < index else { return nil }
            let name = String(source[nameStart..<index])
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            guard index < source.endIndex, source[index] == "=" else { return nil }
            index = source.index(after: index)
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            guard index < source.endIndex else { return nil }
            let quote = source[index]
            guard quote == "\"" || quote == "'" else { return nil }
            index = source.index(after: index)
            let valueStart = index
            while index < source.endIndex, source[index] != quote {
                index = source.index(after: index)
            }
            guard index < source.endIndex else { return nil }
            parsed[name] = String(source[valueStart..<index])
            index = source.index(after: index)
        }
        return parsed
    }

    private static func isAttributeName(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "-" || char == ":"
    }

    private static func resultBody(state: TaskState, in inner: Substring) -> String? {
        let preferred = state == .error ? "task_error" : "task_result"
        let fallback = state == .error ? "task_result" : "task_error"
        return elementBody(preferred, in: inner) ?? elementBody(fallback, in: inner)
    }

    private static func elementBody(_ name: String, in text: Substring) -> String? {
        let open = "<\(name)>"
        let close = "</\(name)>"
        guard let openRange = text.range(of: open) else { return nil }
        let afterOpen = text[openRange.upperBound...]
        guard let closeRange = afterOpen.range(of: close, options: .backwards) else { return nil }
        return unwrapEnvelopeNewline(String(afterOpen[..<closeRange.lowerBound]))
    }

    private static func unwrapEnvelopeNewline(_ text: String) -> String {
        var result = text
        if result.hasPrefix("\n") { result.removeFirst() }
        if result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}
