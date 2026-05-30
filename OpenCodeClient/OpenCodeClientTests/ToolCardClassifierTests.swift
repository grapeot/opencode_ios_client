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

    // MARK: - Directory read detection + entries parsing

    /// Build a `read` Part whose object `state` carries `output`, mirroring the
    /// real server shape where Part.toolOutput resolves to state.output.
    private func makeReadPart(tool: String = "read", output: String) throws -> Part {
        let obj: [String: Any] = [
            "id": "d1",
            "messageID": "m1",
            "sessionID": "s1",
            "type": "tool",
            "tool": tool,
            "state": [
                "status": "completed",
                "output": output,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(Part.self, from: data)
    }

    private let directoryOutput = """
    <path>/abs/path/proj</path>
    <type>directory</type>
    <entries>
    sub/
    nested_dir/
    file.txt
    README.md
    (4 entries)
    </entries>
    """

    @Test func directoryReadIsDetected() throws {
        let part = try makeReadPart(output: directoryOutput)
        #expect(ToolCardClassifier.isDirectoryRead(part))
    }

    @Test func fileReadIsNotDirectoryRead() throws {
        let fileOutput = """
        <path>/abs/path/file.txt</path>
        <type>file</type>
        <content>hello</content>
        """
        let part = try makeReadPart(output: fileOutput)
        #expect(!ToolCardClassifier.isDirectoryRead(part))
    }

    @Test func readFileAliasDetectsDirectory() throws {
        let part = try makeReadPart(tool: "read_file", output: directoryOutput)
        #expect(ToolCardClassifier.isDirectoryRead(part))
    }

    @Test func nonReadToolIsNeverDirectoryRead() throws {
        // Even if some tool's output mentioned directory, only `read` counts.
        let part = try makeReadPart(tool: "bash", output: directoryOutput)
        #expect(!ToolCardClassifier.isDirectoryRead(part))
    }

    @Test func readWithoutOutputIsNotDirectoryRead() throws {
        let part = try makePart(type: "tool", tool: "read")
        #expect(!ToolCardClassifier.isDirectoryRead(part))
    }

    @Test func parsesEntriesWithDirAndFileFlags() throws {
        let entries = ToolCardClassifier.parseDirectoryEntries(directoryOutput)
        #expect(entries.count == 4)
        #expect(entries.map(\.name) == ["sub", "nested_dir", "file.txt", "README.md"])
        #expect(entries.map(\.isDirectory) == [true, true, false, false])
    }

    @Test func parseSkipsSummaryAndBlankLines() throws {
        let output = """
        <type>directory</type>
        <entries>

        a/

        b.swift
        (2 entries)
        </entries>
        """
        let entries = ToolCardClassifier.parseDirectoryEntries(output)
        #expect(entries.map(\.name) == ["a", "b.swift"])
        #expect(entries.map(\.isDirectory) == [true, false])
    }

    @Test func parseReturnsEmptyWhenNoEntriesBlock() throws {
        #expect(ToolCardClassifier.parseDirectoryEntries("<type>file</type>").isEmpty)
        #expect(ToolCardClassifier.parseDirectoryEntries(nil).isEmpty)
    }

    @Test func parseHandlesMissingCloseTag() throws {
        // Tolerate a truncated/streaming output with no </entries>.
        let output = "<entries>\nonly/\nfile.txt\n"
        let entries = ToolCardClassifier.parseDirectoryEntries(output)
        #expect(entries.map(\.name) == ["only", "file.txt"])
        #expect(entries.map(\.isDirectory) == [true, false])
    }
}
