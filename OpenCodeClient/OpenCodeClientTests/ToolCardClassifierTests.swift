//
//  ToolCardClassifierTests.swift
//  OpenCodeClientTests
//
//  Behavior guard for the "tool card render redo": which parts become file cards
//  (2-column grid) vs. which collapse into the merged "N tool calls" row, and the
//  count shown in that row. Layer 1 deterministic logic test (see docs/tests.md).
//

import Foundation
import Testing
@testable import OpenCodeClient

struct ToolCardClassifierTests {

    /// Build a Part by decoding JSON, so the test exercises the real model exactly
    /// as the server would feed it (type/tool/metadata path all flow through Codable).
    private func makePart(
        id: String = "p1",
        type: String,
        tool: String? = nil,
        path: String? = nil
    ) throws -> Part {
        var obj: [String: Any] = [
            "id": id,
            "messageID": "m1",
            "sessionID": "s1",
            "type": type,
        ]
        if let tool { obj["tool"] = tool }
        if let path { obj["metadata"] = ["path": path] }
        let data = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(Part.self, from: data)
    }

    // MARK: - isFileOperation

    @Test func patchPartIsFileOperation() throws {
        let part = try makePart(type: "patch")
        #expect(ToolCardClassifier.isFileOperation(part))
    }

    @Test func canonicalFileTools() throws {
        for tool in ["apply_patch", "edit_file", "write_file", "read_file"] {
            let part = try makePart(type: "tool", tool: tool)
            #expect(ToolCardClassifier.isFileOperation(part), "\(tool) should be a file operation")
        }
    }

    @Test func aliasFileToolsViaPrefix() throws {
        for tool in ["edit", "write", "read", "patch"] {
            let part = try makePart(type: "tool", tool: tool)
            #expect(ToolCardClassifier.isFileOperation(part), "alias \(tool) should be a file operation")
        }
    }

    @Test func toolNameMatchIsCaseInsensitive() throws {
        let part = try makePart(type: "tool", tool: "Edit_File")
        #expect(ToolCardClassifier.isFileOperation(part))
    }

    @Test func nonFileToolsAreNotFileOperations() throws {
        for tool in ["bash", "grep", "glob", "list", "webfetch", "task", "todowrite"] {
            let part = try makePart(type: "tool", tool: tool)
            #expect(!ToolCardClassifier.isFileOperation(part), "\(tool) should NOT be a file operation")
        }
    }

    @Test func textPartIsNotFileOperation() throws {
        let part = try makePart(type: "text")
        #expect(!ToolCardClassifier.isFileOperation(part))
    }

    @Test func toolWithoutNameIsNotFileOperation() throws {
        let part = try makePart(type: "tool", tool: nil)
        #expect(!ToolCardClassifier.isFileOperation(part))
    }

    // MARK: - split + count

    @Test func splitPartitionsFileAndOtherTools() throws {
        let parts = [
            try makePart(id: "1", type: "tool", tool: "read_file", path: "src/a.ts"),
            try makePart(id: "2", type: "tool", tool: "bash"),
            try makePart(id: "3", type: "patch"),
            try makePart(id: "4", type: "tool", tool: "grep"),
            try makePart(id: "5", type: "tool", tool: "edit"),
        ]
        let (fileParts, otherParts) = ToolCardClassifier.split(parts)

        #expect(fileParts.map(\.id) == ["1", "3", "5"])
        #expect(otherParts.map(\.id) == ["2", "4"])
    }

    @Test func toolCallsCountIsOtherToolsOnly() throws {
        let parts = [
            try makePart(id: "1", type: "tool", tool: "write_file"),
            try makePart(id: "2", type: "tool", tool: "bash"),
            try makePart(id: "3", type: "tool", tool: "glob"),
            try makePart(id: "4", type: "patch"),
        ]
        // 2 file ops (write_file + patch), 2 other tools (bash + glob)
        #expect(ToolCardClassifier.toolCallsCount(parts) == 2)
    }

    @Test func allFileOpsMeansZeroToolCalls() throws {
        let parts = [
            try makePart(id: "1", type: "tool", tool: "read_file"),
            try makePart(id: "2", type: "patch"),
        ]
        let (fileParts, otherParts) = ToolCardClassifier.split(parts)
        #expect(fileParts.count == 2)
        #expect(otherParts.isEmpty)
        #expect(ToolCardClassifier.toolCallsCount(parts) == 0)
    }

    @Test func allOtherToolsMeansNoFileCards() throws {
        let parts = [
            try makePart(id: "1", type: "tool", tool: "bash"),
            try makePart(id: "2", type: "tool", tool: "webfetch"),
            try makePart(id: "3", type: "tool", tool: "task"),
        ]
        let (fileParts, otherParts) = ToolCardClassifier.split(parts)
        #expect(fileParts.isEmpty)
        #expect(otherParts.count == 3)
        #expect(ToolCardClassifier.toolCallsCount(parts) == 3)
    }
}
