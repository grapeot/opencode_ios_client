//
//  Message.swift
//  OpenCodeClient
//

import Foundation

struct Message: Codable, Identifiable {
    let id: String
    let sessionID: String
    let role: String
    let parentID: String?
    let model: ModelInfo?
    let time: TimeInfo
    let finish: String?

    struct ModelInfo: Codable {
        let providerID: String
        let modelID: String
    }

    struct TimeInfo: Codable {
        let created: Int
        let completed: Int?
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
}

struct MessageWithParts: Codable {
    let info: Message
    let parts: [Part]
}

/// Part.state can be String (simple) or object (ToolState with status/title/input/output)
struct PartStateBridge: Codable {
    let displayString: String
    /// 调用的理由/描述，来自 state.title 或 state.metadata.description
    let title: String?
    /// 命令/输入，来自 state.input 或 state.metadata
    let inputSummary: String?
    /// 输出结果，来自 state.output 或 state.metadata.output
    let output: String?
    /// 文件路径，来自 state.input.path/file_path/filePath 或 patchText 中的 *** Add File: / *** Update File:
    let pathFromInput: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            displayString = str
            title = nil
            inputSummary = nil
            output = nil
            pathFromInput = nil
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            if let status = dict["status"]?.value as? String {
                displayString = status
            } else if let t = dict["title"]?.value as? String {
                displayString = t
            } else {
                displayString = "…"
            }
            var tit: String? = dict["title"]?.value as? String
            var out: String? = dict["output"]?.value as? String
            if let meta = dict["metadata"]?.value as? [String: AnyCodable] {
                if out == nil, let o = meta["output"]?.value as? String { out = o }
                if tit == nil, let d = meta["description"]?.value as? String { tit = d }
            }
            var inp: String?
            var pathInp: String?
            if let inputVal = dict["input"]?.value {
                if let inputStr = inputVal as? String {
                    inp = inputStr
                    pathInp = nil
                } else {
                    func getStr(_ d: [String: Any], _ k: String) -> String? {
                        if let v = d[k] as? String { return v }
                        if let arr = d[k] as? [String], let first = arr.first { return first }
                        return nil
                    }
                    let inputDict: [String: Any]?
                    if let id = inputVal as? [String: Any] {
                        inputDict = id
                    } else if let id2 = inputVal as? [String: AnyCodable] {
                        inputDict = id2.mapValues { $0.value }
                    } else {
                        inputDict = nil
                    }
                    if let d = inputDict {
                        inp = getStr(d, "command") ?? getStr(d, "path")
                        // Extract file path for write/edit/apply_patch
                        var pathVal = getStr(d, "path") ?? getStr(d, "file_path") ?? getStr(d, "filePath")
                        if pathVal == nil, let patchText = getStr(d, "patchText") {
                            // Parse "*** Add File: path" or "*** Update File: path" (may appear after *** Begin Patch\n)
                            for prefix in ["*** Add File: ", "*** Update File: "] {
                                if let range = patchText.range(of: prefix) {
                                    let rest = String(patchText[range.upperBound...])
                                    pathVal = rest.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
                                    break
                                }
                            }
                        }
                        pathInp = pathVal
                    } else {
                        pathInp = nil
                    }
                }
            } else {
                pathInp = nil
            }
            pathFromInput = pathInp
            title = tit
            inputSummary = inp
            output = out
        } else {
            pathFromInput = nil
            throw DecodingError.typeMismatch(PartStateBridge.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Part.state must be String or object"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayString)
    }
}

struct Part: Codable, Identifiable {
    let id: String
    let messageID: String
    let sessionID: String
    let type: String
    let text: String?
    let tool: String?
    let callID: String?
    let state: PartStateBridge?
    let metadata: PartMetadata?
    let files: [FileChange]?

    /// For UI display; handles both string and object state
    var stateDisplay: String? { state?.displayString }
    /// 调用的理由/描述（用于 tool label）
    var toolReason: String? { state?.title }
    /// 命令/输入摘要
    var toolInputSummary: String? { state?.inputSummary }
    /// 输出结果
    var toolOutput: String? { state?.output }

    struct FileChange: Codable {
        let path: String
        let additions: Int
        let deletions: Int
        let status: String?
    }

    struct PartMetadata: Codable {
        let path: String?
        let title: String?
        let input: String?
    }

    var isText: Bool { type == "text" }
    var isReasoning: Bool { type == "reasoning" }
    var isTool: Bool { type == "tool" }
    var isPatch: Bool { type == "patch" }

    /// 可跳转的文件路径列表：来自 files 数组、metadata.path、或 state.input 中的 path/patchText 解析
    var filePathsForNavigation: [String] {
        var out: [String] = []
        if let files = files {
            out.append(contentsOf: files.map(\.path))
        }
        if let p = metadata?.path, !p.isEmpty {
            out.append(p)
        }
        if let p = state?.pathFromInput, !p.isEmpty, !out.contains(p) {
            out.append(p)
        }
        return out
    }
    var isStepStart: Bool { type == "step-start" }
    var isStepFinish: Bool { type == "step-finish" }
}
