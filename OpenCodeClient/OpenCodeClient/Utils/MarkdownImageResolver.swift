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
            
            // Resolve relative path
            var resolvedPath = rawUrl
            if let mdPath = markdownFilePath, !rawUrl.hasPrefix("/") {
                let mdDir = (mdPath as NSString).deletingLastPathComponent
                resolvedPath = (mdDir as NSString).appendingPathComponent(rawUrl)
            }
            
            // Make workspace-relative
            resolvedPath = PathNormalizer.resolveWorkspaceRelativePath(resolvedPath, workspaceDirectory: workspaceDirectory)
            
            // Strip leading ./ from the resolved path
            if resolvedPath.hasPrefix("./") { resolvedPath = String(resolvedPath.dropFirst(2)) }
            
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
