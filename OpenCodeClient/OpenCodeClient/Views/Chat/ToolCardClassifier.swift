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

    /// `read` tool names (and aliases) — a directory read can only come from one of
    /// these, never from edit/write/patch.
    static let readToolPrefixes = ["read_file", "read"]

    /// True when this part is a `read` whose tool output reports a directory.
    /// The server embeds `<type>directory</type>` in the read output for a folder
    /// (vs. `<type>file</type>` for a file); see Models/Message.swift toolOutput.
    static func isDirectoryRead(_ part: Part) -> Bool {
        guard part.isTool, let tool = part.tool?.lowercased() else { return false }
        guard readToolPrefixes.contains(where: { tool.hasPrefix($0) }) else { return false }
        guard let output = part.toolOutput else { return false }
        return output.contains("<type>directory</type>")
    }

    /// One entry in a directory read: a child file or subdirectory.
    struct DirectoryEntry: Identifiable, Equatable {
        let name: String
        let isDirectory: Bool
        var id: String { name }
    }

    /// Parse the `<entries>…</entries>` block out of a directory read's output.
    /// Each line is a child name; names ending in "/" are subdirectories. Blank
    /// lines and trailing summary lines like "(12 entries)" are dropped. The
    /// display name keeps the trailing "/" stripped so the UI can render it
    /// uniformly with its own icon.
    static func parseDirectoryEntries(_ output: String?) -> [DirectoryEntry] {
        guard let output else { return [] }
        guard let openRange = output.range(of: "<entries>") else { return [] }
        let afterOpen = output[openRange.upperBound...]
        let body: Substring
        if let closeRange = afterOpen.range(of: "</entries>") {
            body = afterOpen[..<closeRange.lowerBound]
        } else {
            body = afterOpen
        }

        var entries: [DirectoryEntry] = []
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Drop summary lines such as "(12 entries)" or "(0 entries)".
            if line.hasPrefix("(") && line.hasSuffix("entries)") { continue }
            let isDir = line.hasSuffix("/")
            let name = isDir ? String(line.dropLast()) : line
            if name.isEmpty { continue }
            entries.append(DirectoryEntry(name: name, isDirectory: isDir))
        }
        return entries
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
