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
    /// Some servers return providerID/modelID as top-level fields (instead of `model`).
    let providerID: String?
    let modelID: String?
    let model: ModelInfo?
    let error: MessageError?
    let time: TimeInfo
    let finish: String?
    let tokens: TokenInfo?
    let cost: Double?

    struct ModelInfo: Codable {
        let providerID: String
        let modelID: String
    }

    struct TokenInfo: Codable {
        let total: Int
        let input: Int
        let output: Int
        let reasoning: Int
        let cache: CacheInfo?

        struct CacheInfo: Codable {
            let read: Int
            let write: Int
        }

        private enum CodingKeys: String, CodingKey {
            case total
            case input
            case output
            case reasoning
            case cache
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
            reasoning = try c.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
            cache = try c.decodeIfPresent(CacheInfo.self, forKey: .cache)
            // Newer OpenCode server payloads may omit `total`.
            total = try c.decodeIfPresent(Int.self, forKey: .total) ?? (input + output + reasoning)
        }
    }

    struct TimeInfo: Codable {
        let created: Int
        let completed: Int?
    }

    struct MessageError: Codable {
        let name: String
        let data: [String: AnyCodable]

        var message: String? {
            if let msg = data["message"]?.value as? String { return msg }
            if let msg = data["error"]?.value as? String { return msg }
            return nil
        }
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }

    var resolvedModel: ModelInfo? {
        if let model { return model }
        if let providerID, let modelID { return ModelInfo(providerID: providerID, modelID: modelID) }
        return nil
    }

    var errorMessageForDisplay: String? {
        let trimmed = error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
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

    /// For todowrite: updated todo list (if present)
    let todos: [TodoItem]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        func decodeTodos(from obj: Any) -> [TodoItem]? {
            guard JSONSerialization.isValidJSONObject(obj) else { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return try? JSONDecoder().decode([TodoItem].self, from: data)
        }

        func decodeTodosFromJSONText(_ text: String?) -> [TodoItem]? {
            guard let text else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let data = trimmed.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([TodoItem].self, from: data)
        }

        if let str = try? container.decode(String.self) {
            displayString = str
            title = nil
            inputSummary = nil
            output = nil
            pathFromInput = nil
            todos = nil
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
            if let meta = dict["metadata"]?.value as? [String: Any] {
                if out == nil, let o = meta["output"] as? String { out = o }
                if tit == nil, let d = meta["description"] as? String { tit = d }
            }
            var inp: String?
            var pathInp: String?
            var todoList: [TodoItem]?

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

                        if let todosObj = d["todos"], let decoded = decodeTodos(from: todosObj) {
                            todoList = decoded
                        }

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

            if todoList == nil,
               let meta = dict["metadata"]?.value as? [String: Any],
               let todosObj = meta["todos"] {
                todoList = decodeTodos(from: todosObj)
            }

            if todoList == nil {
                todoList = decodeTodosFromJSONText(out)
            }

            pathFromInput = pathInp
            title = tit
            inputSummary = inp
            output = out
            todos = todoList
        } else {
            pathFromInput = nil
            todos = nil
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

    var toolTodos: [TodoItem] {
        if let t = metadata?.todos, !t.isEmpty { return t }
        if let t = state?.todos, !t.isEmpty { return t }
        return []
    }

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
        let todos: [TodoItem]?

        private enum CodingKeys: String, CodingKey {
            case path
            case title
            case input
            case todos
        }

        init(path: String?, title: String?, input: String?, todos: [TodoItem]?) {
            self.path = path
            self.title = title
            self.input = input
            self.todos = todos
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            path = try? c.decode(String.self, forKey: .path)
            title = try? c.decode(String.self, forKey: .title)

            if let inputString = try? c.decode(String.self, forKey: .input) {
                input = inputString
            } else if let inputObject = try? c.decode([String: AnyCodable].self, forKey: .input),
                      JSONSerialization.isValidJSONObject(inputObject.mapValues({ $0.value })),
                      let data = try? JSONSerialization.data(withJSONObject: inputObject.mapValues({ $0.value })),
                      let text = String(data: data, encoding: .utf8) {
                input = text
            } else {
                input = nil
            }

            if let decoded = try? c.decode([TodoItem].self, forKey: .todos) {
                todos = decoded
            } else if let raw = try? c.decode([AnyCodable].self, forKey: .todos),
                      JSONSerialization.isValidJSONObject(raw.map({ $0.value })),
                      let data = try? JSONSerialization.data(withJSONObject: raw.map({ $0.value })),
                      let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
                todos = decoded
            } else {
                todos = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(path, forKey: .path)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(input, forKey: .input)
            try c.encodeIfPresent(todos, forKey: .todos)
        }
    }

    var isText: Bool { type == "text" }
    var isReasoning: Bool { type == "reasoning" }
    var isTool: Bool { type == "tool" }
    var isPatch: Bool { type == "patch" }

    /// 可跳转的文件路径列表：来自 files 数组、metadata.path、或 state.input 中的 path/patchText 解析
    var filePathsForNavigation: [String] {
        var out: [String] = []
        if let files = files {
            out.append(contentsOf: files.map { PathNormalizer.normalize($0.path) })
        }
        if let p = metadata?.path.map({ PathNormalizer.normalize($0) }), !p.isEmpty {
            out.append(p)
        }
        if let p = state?.pathFromInput.map({ PathNormalizer.normalize($0) }), !p.isEmpty, !out.contains(p) {
            out.append(p)
        }
        return out
    }
    var isStepStart: Bool { type == "step-start" }
    var isStepFinish: Bool { type == "step-finish" }
}
