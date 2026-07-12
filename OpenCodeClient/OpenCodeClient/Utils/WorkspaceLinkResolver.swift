import Foundation

nonisolated enum WorkspaceLinkResolution: Equatable {
    case external(URL)
    case file(path: String)
    case fragmentOnly
    case rejected(String)
}

nonisolated enum WorkspaceLinkResolver {
    static func resolve(
        _ rawHref: String,
        workspaceDirectory: String?,
        baseFilePath: String? = nil
    ) -> WorkspaceLinkResolution {
        let href = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return .rejected("Empty link") }
        guard !href.hasPrefix("#") else { return .fragmentOnly }

        if href.hasPrefix("//") {
            return .rejected("Scheme-relative links are not allowed")
        }

        if let components = URLComponents(string: href), let scheme = components.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                guard let url = URL(string: href) else { return .rejected("Invalid URL") }
                return .external(url)
            case "file":
                guard let workspace = normalizedAbsolutePath(workspaceDirectory), !workspace.isEmpty else {
                    return .rejected("Cannot open workspace file link without a workspace directory")
                }
                return resolveFileURL(components, workspace: workspace)
            case "javascript", "data":
                return .rejected("Blocked unsafe link scheme: \(scheme)")
            default:
                return .rejected("Unsupported link scheme: \(scheme)")
            }
        }

        guard let workspace = normalizedAbsolutePath(workspaceDirectory), !workspace.isEmpty else {
            return .rejected("Cannot open workspace file link without a workspace directory")
        }

        let encodedPath = pathPart(from: href)
        let (decodedPath, changedByDecoding) = decodedPercentEncoding(encodedPath)
        if changedByDecoding, containsParentSegment(decodedPath) {
            return .rejected("Encoded parent traversal is not allowed")
        }

        if decodedPath.hasPrefix("/") {
            return resolveAbsolutePath(decodedPath, workspace: workspace)
        }

        guard let absolute = resolveRelativePath(decodedPath, workspace: workspace, baseFilePath: baseFilePath) else {
            return .rejected("Relative link escapes the workspace")
        }
        return workspaceRelativeFile(absolutePath: absolute, workspace: workspace)
    }

    private static func resolveFileURL(_ components: URLComponents, workspace: String) -> WorkspaceLinkResolution {
        if let host = components.host, !host.isEmpty, host.lowercased() != "localhost" {
            return .rejected("Only local file:// links are allowed")
        }
        let encodedPath = components.percentEncodedPath
        guard !encodedPath.isEmpty else { return .rejected("Empty file URL path") }
        let (decodedPath, changedByDecoding) = decodedPercentEncoding(encodedPath)
        if changedByDecoding, containsParentSegment(decodedPath) {
            return .rejected("Encoded parent traversal is not allowed")
        }
        return resolveAbsolutePath(decodedPath, workspace: workspace)
    }

    private static func resolveAbsolutePath(_ path: String, workspace: String) -> WorkspaceLinkResolution {
        guard let absolute = normalizedAbsolutePath(path) else {
            return .rejected("Invalid absolute path")
        }
        return workspaceRelativeFile(absolutePath: absolute, workspace: workspace)
    }

    private static func workspaceRelativeFile(absolutePath: String, workspace: String) -> WorkspaceLinkResolution {
        guard absolutePath != workspace else { return .rejected("Workspace root is not a file") }
        guard absolutePath.hasPrefix(workspace + "/") else {
            return .rejected("File link is outside the workspace")
        }
        let relative = String(absolutePath.dropFirst(workspace.count + 1))
        guard !relative.isEmpty else { return .rejected("Empty file path") }
        return .file(path: relative)
    }

    private static func resolveRelativePath(
        _ path: String,
        workspace: String,
        baseFilePath: String?
    ) -> String? {
        var baseSegments = pathSegments(workspace)
        if let baseFilePath, !baseFilePath.isEmpty {
            let baseAbsolute: String
            if baseFilePath.hasPrefix("/") {
                guard let normalized = normalizedAbsolutePath(baseFilePath), normalized == workspace || normalized.hasPrefix(workspace + "/") else {
                    return nil
                }
                baseAbsolute = normalized
            } else {
                guard let normalized = normalizedAbsolutePath(workspace + "/" + baseFilePath) else { return nil }
                baseAbsolute = normalized
            }
            baseSegments = pathSegments(baseAbsolute)
            if !baseSegments.isEmpty { baseSegments.removeLast() }
        }

        let workspaceDepth = pathSegments(workspace).count
        var output = baseSegments
        for segment in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch segment {
            case ".":
                continue
            case "..":
                guard output.count > workspaceDepth else { return nil }
                output.removeLast()
            default:
                output.append(segment)
            }
        }
        return "/" + output.joined(separator: "/")
    }

    private static func normalizedAbsolutePath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        var segments: [String] = []
        for segment in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch segment {
            case ".":
                continue
            case "..":
                if !segments.isEmpty { segments.removeLast() }
            default:
                segments.append(segment)
            }
        }
        return "/" + segments.joined(separator: "/")
    }

    private static func pathSegments(_ absolutePath: String) -> [String] {
        absolutePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func pathPart(from href: String) -> String {
        if let components = URLComponents(string: href), !components.percentEncodedPath.isEmpty {
            return components.percentEncodedPath
        }
        return href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
    }

    private static func decodedPercentEncoding(_ value: String) -> (String, Bool) {
        var current = value
        var changed = false
        for _ in 0..<3 {
            guard let decoded = current.removingPercentEncoding, decoded != current else { break }
            current = decoded
            changed = true
        }
        return (current, changed)
    }

    private static func containsParentSegment(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }
}
