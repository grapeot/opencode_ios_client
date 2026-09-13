//
//  Message.swift
//  OpenCodeClient
//

import Foundation

enum DisplayTextDecoder {
    static func decodeJSONUnicodeEscapes(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        func hexDigit(_ character: Character) -> UInt32? {
            guard let value = character.unicodeScalars.first?.value else { return nil }
            if (48...57).contains(value) { return value - 48 }
            if (97...102).contains(value) { return value - 97 + 10 }
            if (65...70).contains(value) { return value - 65 + 10 }
            return nil
        }

        func hexValue(at start: String.Index) -> (value: UInt32, end: String.Index)? {
            var value: UInt32 = 0
            var cursor = start
            for _ in 0..<4 {
                guard cursor < text.endIndex, let digit = hexDigit(text[cursor]) else { return nil }
                value = value * 16 + digit
                cursor = text.index(after: cursor)
            }
            return (value, cursor)
        }

        while index < text.endIndex {
            guard text[index] == "\\" else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let uIndex = text.index(after: index)
            guard uIndex < text.endIndex, text[uIndex] == "u" else {
                result.append(text[index])
                index = uIndex
                continue
            }

            let hexStart = text.index(after: uIndex)
            guard let first = hexValue(at: hexStart) else {
                result.append(text[index])
                index = uIndex
                continue
            }

            if (0xD800...0xDBFF).contains(first.value) {
                let slash = first.end
                if slash < text.endIndex,
                   text[slash] == "\\" {
                    let secondU = text.index(after: slash)
                    if secondU < text.endIndex,
                       text[secondU] == "u",
                       let second = hexValue(at: text.index(after: secondU)),
                       (0xDC00...0xDFFF).contains(second.value) {
                        let scalar = 0x10000 + ((first.value - 0xD800) << 10) + (second.value - 0xDC00)
                        if let unicodeScalar = UnicodeScalar(scalar) {
                            result.append(Character(unicodeScalar))
                            index = second.end
                            continue
                        }
                    }
                }
            }

            if let unicodeScalar = UnicodeScalar(first.value) {
                result.append(Character(unicodeScalar))
                index = first.end
            } else {
                result.append(text[index])
                index = uIndex
            }
        }

        return result
    }
}

nonisolated struct Message: Codable, Identifiable {
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
    let structured: CarResponseEnvelope?

    init(
        id: String,
        sessionID: String,
        role: String,
        parentID: String?,
        providerID: String?,
        modelID: String?,
        model: ModelInfo?,
        error: MessageError?,
        time: TimeInfo,
        finish: String?,
        tokens: TokenInfo?,
        cost: Double?,
        structured: CarResponseEnvelope? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.parentID = parentID
        self.providerID = providerID
        self.modelID = modelID
        self.model = model
        self.error = error
        self.time = time
        self.finish = finish
        self.tokens = tokens
        self.cost = cost
        self.structured = structured
    }

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

    /// Tokens the model actually emitted during this step: visible `output`
    /// plus `reasoning` (thinking). Prefill (`input`) and cache read/write are
    /// excluded because they are not generated tokens.
    var generatedTokens: Int {
        (tokens?.output ?? 0) + (tokens?.reasoning ?? 0)
    }

    /// Raw step wall-clock in seconds (`time.created` -> `time.completed`).
    /// This window spans the whole step, which on live servers includes the
    /// step's tool execution: `Step.Ended` / `step-finish` is published only
    /// after the tools have run (`awaitToolFibers` in the V2 runner, and the
    /// same ordering in the legacy processor). Prefer
    /// `throughputExcludingToolSeconds` for display.
    var stepSeconds: Double? {
        guard let completed = time.completed else { return nil }
        let ms = completed - time.created
        guard ms > 0 else { return nil }
        return Double(ms) / 1000.0
    }

    /// Throughput with the step's tool execution removed from the denominator.
    ///
    /// The numerator is unchanged, so tool-call argument tokens stay counted;
    /// only the wait for the tool is dropped. A write tool that ran 48s inside
    /// a 56s step reads as 68 t/s instead of 9 t/s. Falls back to the raw
    /// window when the server recorded no tool timing, or when subtracting the
    /// tool time would leave nothing positive. This is the only rate the UI
    /// shows, so the footer and the Context sheet cannot drift.
    func throughputExcludingToolSeconds(_ toolSeconds: Double) -> Double? {
        guard let window = stepSeconds else { return nil }
        let adjusted = window - max(0, toolSeconds)
        return throughput(overSeconds: adjusted > 0 ? adjusted : window)
    }

    private func throughput(overSeconds seconds: Double?) -> Double? {
        guard let seconds, seconds > 0 else { return nil }
        let tokens = generatedTokens
        guard tokens > 0 else { return nil }
        return Double(tokens) / seconds
    }

    /// Short display form of `throughputExcludingToolSeconds`, e.g. "146 t/s" or
    /// "8.3 t/s". Integer when >= 10, one decimal below that; nil when
    /// unavailable.
    func throughputLabelExcludingToolSeconds(_ toolSeconds: Double) -> String? {
        throughputExcludingToolSeconds(toolSeconds).map(Self.throughputText)
    }

    /// Shared tokens/second formatter: integer when >= 10, one decimal below
    /// that. Used by both the per-message footer and the Context sheet so the
    /// two can never drift.
    static func throughputText(_ value: Double) -> String {
        let text = value >= 10 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return "\(text) t/s"
    }
}

nonisolated struct MessageWithParts: Codable {
    let info: Message
    let parts: [Part]

    /// Wall-clock this step spent inside its tools (sum of `state.time`). Zero
    /// when the server recorded no tool timing, e.g. a step that called no
    /// tools or an older payload without `state.time`.
    var toolRunSeconds: Double {
        parts.compactMap(\.toolRunSeconds).reduce(0, +)
    }
}

struct ComposerImageAttachment: Identifiable, Equatable {
    let id: UUID
    let filename: String
    let mime: String
    let dataURL: String
    let thumbnailData: Data
    let byteSize: Int
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

    /// Tool execution bounds from state.time, in epoch milliseconds. Present
    /// for running and completed tools; nil when the server did not record it.
    let runStartMillis: Double?
    let runEndMillis: Double?

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

        /// state.time values arrive as JSON numbers; Int and Double both occur
        /// depending on the server's encoder.
        func millis(_ value: Any?) -> Double? {
            if let double = value as? Double { return double }
            if let int = value as? Int { return Double(int) }
            if let number = value as? NSNumber { return number.doubleValue }
            return nil
        }

        if let str = try? container.decode(String.self) {
            displayString = str
            title = nil
            inputSummary = nil
            output = nil
            pathFromInput = nil
            runStartMillis = nil
            runEndMillis = nil
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

            let timeObj: [String: Any]? =
                (dict["time"]?.value as? [String: Any])
                ?? (dict["time"]?.value as? [String: AnyCodable]).map { $0.mapValues { $0.value } }

            pathFromInput = pathInp
            title = tit
            inputSummary = inp
            output = out
            runStartMillis = millis(timeObj?["start"])
            runEndMillis = millis(timeObj?["end"])
            todos = todoList
        } else {
            pathFromInput = nil
            runStartMillis = nil
            runEndMillis = nil
            todos = nil
            throw DecodingError.typeMismatch(PartStateBridge.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Part.state must be String or object"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayString)
    }
}

nonisolated struct Part: Codable, Identifiable {
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
    var mime: String? = nil
    var filename: String? = nil
    var url: String? = nil
    var source: String? = nil

    /// For UI display; handles both string and object state
    var stateDisplay: String? { state?.displayString }
    /// 调用的理由/描述（用于 tool label）
    var toolReason: String? { state?.title }
    /// 命令/输入摘要
    var toolInputSummary: String? { state?.inputSummary }
    var toolInputSummaryForDisplay: String? {
        toolInputSummary.map(DisplayTextDecoder.decodeJSONUnicodeEscapes)
    }
    /// 输出结果
    var toolOutput: String? { state?.output }
    var toolOutputForDisplay: String? {
        toolOutput.map(DisplayTextDecoder.decodeJSONUnicodeEscapes)
    }

    /// Wall-clock this tool itself ran, from `state.time`. Nil while running or
    /// when the server recorded no timing. Kept separate from the step window
    /// so tool execution can be removed from throughput denominators.
    var toolRunSeconds: Double? {
        guard let start = state?.runStartMillis,
              let end = state?.runEndMillis,
              end > start else { return nil }
        return (end - start) / 1000.0
    }

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

        private enum CodingKeys: String, CodingKey {
            case path, additions, deletions, status
        }

        init(path: String, additions: Int = 0, deletions: Int = 0, status: String? = nil) {
            self.path = path
            self.additions = additions
            self.deletions = deletions
            self.status = status
        }

        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let path = try? single.decode(String.self) {
                self.path = path
                additions = 0
                deletions = 0
                status = nil
                return
            }

            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(String.self, forKey: .path)
            additions = (try? c.decode(Int.self, forKey: .additions)) ?? 0
            deletions = (try? c.decode(Int.self, forKey: .deletions)) ?? 0
            status = try? c.decode(String.self, forKey: .status)
        }
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
    var isFile: Bool { type == "file" }
    var isImageAttachment: Bool { isFile && (mime?.hasPrefix("image/") ?? false) }

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
