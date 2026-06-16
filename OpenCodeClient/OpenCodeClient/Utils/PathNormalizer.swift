//
//  PathNormalizer.swift
//  OpenCodeClient
//

import Foundation

/// 统一路径规范化：用于 API 请求、文件跳转等
nonisolated enum PathNormalizer {

    /// 规范化文件路径：去除 a/b 前缀、# 及后缀、:line:col 后缀
    static func normalize(_ path: String) -> String {
        var s = trimPathWhitespace(path)

        // Some tool payloads contain percent-encoded paths (sometimes double-encoded).
        // Decode a few times until stable so `src%2Fapp.swift` -> `src/app.swift`.
        for _ in 0..<3 {
            guard let decoded = s.removingPercentEncoding, decoded != s else { break }
            s = decoded
        }

        // Normalize file:// URLs (if present)
        if s.hasPrefix("file://"), let url = URL(string: s) {
            s = url.path
        }

        // Drop leading slash to keep API paths workspace-relative when possible
        if s.hasPrefix("/") {
            s = String(s.dropFirst())
        }
        if s.hasPrefix("a/") || s.hasPrefix("b/") {
            s = String(s.dropFirst(2))
        }
        if let hash = s.firstIndex(of: "#") {
            s = String(s[..<hash])
        }
        s = stripLineColumnSuffix(s)

        var normalizedSegments: [Substring] = []
        for segment in s.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                if !normalizedSegments.isEmpty {
                    normalizedSegments.removeLast()
                }
            default:
                normalizedSegments.append(segment)
            }
        }
        s = normalizedSegments.joined(separator: "/")
        return s
    }

    private static func trimPathWhitespace(_ path: String) -> String {
        let scalars = path.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex

        while start < end, isPathWhitespace(scalars[start]) {
            start = scalars.index(after: start)
        }
        while start < end {
            let beforeEnd = scalars.index(before: end)
            guard isPathWhitespace(scalars[beforeEnd]) else { break }
            end = beforeEnd
        }

        return String(scalars[start..<end])
    }

    private static func isPathWhitespace(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20:
            return true
        default:
            return false
        }
    }

    private static func stripLineColumnSuffix(_ path: String) -> String {
        guard let lastColon = path.lastIndex(of: ":") else { return path }
        let lastValue = path[path.index(after: lastColon)...]
        guard !lastValue.isEmpty, lastValue.allSatisfy(\.isNumber) else { return path }

        let beforeLastColon = path[..<lastColon]
        let lastSlash = path.lastIndex(of: "/")
        if let previousColon = beforeLastColon.lastIndex(of: ":"), previousColon > (lastSlash ?? path.startIndex) {
            let lineValue = path[path.index(after: previousColon)..<lastColon]
            if !lineValue.isEmpty, lineValue.allSatisfy(\.isNumber) {
                return String(path[..<previousColon])
            }
        }

        return String(path[..<lastColon])
    }

    /// Resolve an absolute/host path to workspace-relative when possible.
    ///
    /// Tool payloads sometimes carry absolute paths (e.g. "/Users/.../repo/file.swift").
    /// OpenCode server APIs generally expect workspace-relative paths.
    static func resolveWorkspaceRelativePath(_ path: String, workspaceDirectory: String?) -> String {
        let absoluteInput = absoluteHostPath(path)
        let p = normalize(path)
        guard let workspaceDirectory, !workspaceDirectory.isEmpty else {
            return absoluteInput ?? p
        }
        let dir = normalize(workspaceDirectory)
        if p == dir {
            return ""
        }
        if p.hasPrefix(dir + "/") {
            let resolved = String(p.dropFirst(dir.count + 1))
            return resolved
        }
        if let absoluteInput {
            return absoluteInput
        }
        return p
    }

    private static func absoluteHostPath(_ path: String) -> String? {
        let trimmed = trimPathWhitespace(path)
        if trimmed.hasPrefix("/") { return trimmed }
        if trimmed.hasPrefix("Users/") { return "/" + trimmed }
        return nil
    }
}
