import Foundation

enum MarkdownImageResolver {
    private static let maxResolvedImageCharacters = 80_000_000
    private static let maxResolvedMarkdownCharacters = 80_000_000
    
    /// Image extensions that should be fetched as binary content
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "ico", "svg"
    ]
    
    private static let imageRegex = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#,
        options: []
    )
    
    /// Resolve image references in markdown text by fetching them via the API.
    /// - Parameters:
    ///   - text: The markdown text
    ///   - markdownFilePath: The path of the markdown file being rendered (for resolving relative paths). Can be nil for chat messages.
    ///   - workspaceDirectory: The workspace root directory
    ///   - fetchContent: Async closure that fetches FileContent for a given path
    /// - Returns: The markdown text with image URLs resolved to data URIs
    static func resolveImages(
        in text: String,
        markdownFilePath: String? = nil,
        workspaceDirectory: String?,
        fetchContent: (String) async throws -> FileContent
    ) async -> String {
        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = imageRegex.matches(in: text, range: fullRange)
        
        guard !matches.isEmpty else { return text }
        
        var result = text
        // Process matches in reverse order to maintain correct string indices
        for match in matches.reversed() {
            if Task.isCancelled { return text }

            guard let altRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else { continue }
            
            let alt = String(text[altRange])
            let rawUrl = String(text[urlRange]).trimmingCharacters(in: .whitespaces)
            
            // Skip if already a data URI or has a scheme
            if rawUrl.hasPrefix("data:") || rawUrl.contains("://") { continue }
            
            // Determine the extension
            let ext = (rawUrl as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, imageExtensions.contains(ext) else { continue }
            
            // Resolve relative path (same rule reused for link routing; see below).
            let resolvedPath = resolveRelativeReference(
                rawUrl,
                markdownFilePath: markdownFilePath,
                workspaceDirectory: workspaceDirectory
            )

            do {
                let content = try await fetchContent(resolvedPath)
                guard let base64Data = content.content, !base64Data.isEmpty else { continue }
                
                // Clean base64 (remove whitespace)
                let cleaned = base64Data
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: " ", with: "")

                guard cleaned.count <= maxResolvedImageCharacters else { continue }

                let mimeType = mimeType(for: ext)
                let dataUri = "data:\(mimeType);base64,\(cleaned)"
                
                let replacement = "![\(alt)](\(dataUri))"
                guard let matchRange = Range(match.range, in: result) else { continue }
                let nextCount = result.count - result[matchRange].count + replacement.count
                guard nextCount <= maxResolvedMarkdownCharacters else { continue }
                result.replaceSubrange(matchRange, with: replacement)
            } catch is CancellationError {
                return text
            } catch {
                continue
            }
        }
        
        return result
    }

    /// Resolve a relative reference (image src or link href) against the markdown
    /// file's own directory, then make it workspace-relative. Mirrors the path
    /// semantics of Native Preview so Web Preview links/images resolve identically.
    /// - A path starting with `/` is treated as absolute (only workspace-normalized).
    /// - Otherwise it is resolved against the markdown file's directory, including
    ///   `../` parent traversal, then workspace-normalized and `./`-stripped.
    static func resolveRelativeReference(
        _ rawReference: String,
        markdownFilePath: String?,
        workspaceDirectory: String?
    ) -> String {
        var resolvedPath = rawReference
        if let mdPath = markdownFilePath, !rawReference.hasPrefix("/") {
            let mdDir = (mdPath as NSString).deletingLastPathComponent
            resolvedPath = (mdDir as NSString).appendingPathComponent(rawReference)
        }

        // PathNormalizer.normalize (called inside) collapses `.` / `..` segments
        // purely by string, so `../images/x.png` resolves without touching disk.
        resolvedPath = PathNormalizer.resolveWorkspaceRelativePath(resolvedPath, workspaceDirectory: workspaceDirectory)

        if resolvedPath.hasPrefix("./") { resolvedPath = String(resolvedPath.dropFirst(2)) }
        return resolvedPath
    }

    private static func mimeType(for fileExtension: String) -> String {
        switch fileExtension {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "svg":
            return "image/svg+xml"
        default:
            return "image/\(fileExtension)"
        }
    }
}
