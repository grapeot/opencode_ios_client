import Foundation

/// File tree browsing + status + search + content loading. State
/// (`fileTreeRoot`, `fileStatusMap`, `fileChildrenCache`, `expandedPaths`,
/// `fileSearchResults`) lives on the `FileStore` and is exposed through
/// computed accessors on `AppState`. This extension hosts the user-facing
/// load actions.
extension AppState {
    func loadFileTree() async {
        let previousChildrenCache = fileChildrenCache
        let previouslyExpandedPaths = expandedPaths
        do {
            fileTreeRoot = try await apiClient.fileList(path: "")
            fileChildrenCache = previousChildrenCache.filter { previouslyExpandedPaths.contains($0.key) }
        } catch {
            fileTreeRoot = []
        }
    }

    func loadFileStatus() async {
        do {
            let entries = try await apiClient.fileStatus()
            var nextStatusMap: [String: String] = [:]
            for entry in entries {
                guard let path = entry.path else { continue }
                nextStatusMap[path] = entry.status ?? ""
            }
            fileStatusMap = nextStatusMap
        } catch {
            fileStatusMap = [:]
        }
    }

    func loadFileChildren(path: String) async -> [FileNode] {
        do {
            let children = try await apiClient.fileList(path: path)
            fileChildrenCache[path] = children
            return children
        } catch {
            fileChildrenCache[path] = []
            return []
        }
    }

    func cachedChildren(for path: String) -> [FileNode]? {
        fileChildrenCache[path]
    }

    func searchFiles(query: String) async {
        guard !query.isEmpty else { fileSearchResults = []; return }
        do {
            fileSearchResults = try await apiClient.findFile(query: query, limit: 50)
        } catch {
            fileSearchResults = []
        }
    }

    func loadFileContent(path: String) async throws -> FileContent {
        let resolved = PathNormalizer.resolveWorkspaceRelativePath(path, workspaceDirectory: currentSession?.directory)
        return try await apiClient.fileContent(path: resolved)
    }

    func loadFileContent(pathBytes: [UInt8]) async throws -> FileContent {
        let path = String(decoding: pathBytes, as: UTF8.self)
        return try await loadFileContent(path: path)
    }

    func toggleFileExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func isFileExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }
}
