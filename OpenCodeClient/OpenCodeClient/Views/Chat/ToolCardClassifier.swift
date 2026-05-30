//
//  ToolCardClassifier.swift
//  OpenCodeClient
//
//  Classification logic for the "tool card render redo": which parts render as
//  file cards (2-column grid) vs. collapse into a single "N tool calls" row.
//  Extracted from MessageRowView so the behavior is unit-testable without a View.
//

import Foundation

enum ToolCardClassifier {
    /// A "file operation" is a patch part, or a tool whose name matches one of the
    /// file-op verbs. Loose prefix match so aliases like "edit"/"write"/"read"/"patch"
    /// and full forms like "edit_file"/"apply_patch" all count.
    static let fileOpToolPrefixes = [
        "apply_patch", "edit_file", "write_file", "read_file",
        "patch", "edit", "write", "read",
    ]

    static func isFileOperation(_ part: Part) -> Bool {
        if part.isPatch { return true }
        guard part.isTool, let tool = part.tool?.lowercased() else { return false }
        return fileOpToolPrefixes.contains { tool.hasPrefix($0) }
    }

    /// Split a buffered run of tool/patch parts into the file-card group (grid) and
    /// the "other tools" group (merged into one "N tool calls" disclosure row).
    static func split(_ parts: [Part]) -> (fileParts: [Part], otherParts: [Part]) {
        var fileParts: [Part] = []
        var otherParts: [Part] = []
        for part in parts {
            if isFileOperation(part) {
                fileParts.append(part)
            } else {
                otherParts.append(part)
            }
        }
        return (fileParts, otherParts)
    }

    /// Number shown in the merged "N tool calls" row (count of non-file tools).
    static func toolCallsCount(_ parts: [Part]) -> Int {
        parts.lazy.filter { !isFileOperation($0) }.count
    }
}
