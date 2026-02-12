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
        if s.hasPrefix("a/") || s.hasPrefix("b/") {
            s = String(s.dropFirst(2))
        }
        if let hash = s.firstIndex(of: "#") {
            s = String(s[..<hash])
        }
        if let r = s.range(of: ":[0-9]+(:[0-9]+)?$", options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }
        return s
    }
}
