//
//  PathNormalizer.swift
//  OpenCodeClient
//

import Foundation

/// 统一路径规范化：用于 API 请求、文件跳转等
enum PathNormalizer {

    /// 规范化文件路径：去除 a/b 前缀、# 及后缀、:line:col 后缀
    static func normalize(_ path: String) -> String {
        var s = path.trimmingCharacters(in: .whitespacesAndNewlines)

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
        if let r = s.range(of: ":[0-9]+(:[0-9]+)?$", options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }

        // Prevent obvious path traversal segments from flowing into API calls.
        // (Server should enforce this too; this is a defense-in-depth client-side guard.)
        let safeSegments = s.split(separator: "/").filter { seg in
            seg != "." && seg != ".." && !seg.isEmpty
        }
        s = safeSegments.joined(separator: "/")
        return s
    }

    /// Resolve an absolute/host path to workspace-relative when possible.
    ///
    /// Tool payloads sometimes carry absolute paths (e.g. "/Users/.../repo/file.swift").
    /// OpenCode server APIs generally expect workspace-relative paths.
    static func resolveWorkspaceRelativePath(_ path: String, workspaceDirectory: String?) -> String {
        let p = normalize(path)
        guard let workspaceDirectory, !workspaceDirectory.isEmpty else { return p }
        let dir = normalize(workspaceDirectory)
        if p == dir { return "" }
        if p.hasPrefix(dir + "/") {
            return String(p.dropFirst(dir.count + 1))
        }
        return p
    }
}
