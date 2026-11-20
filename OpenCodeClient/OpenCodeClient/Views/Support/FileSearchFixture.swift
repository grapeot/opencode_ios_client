import Foundation
import SwiftUI

@MainActor
@Observable
final class FileSearchProbe {
    var findDirectories: [String] = []
    var contentDirectories: [String] = []
    var sentFromFilePreview = false

    var summary: String {
        "find:\(findDirectories.joined(separator: "|")) content:\(contentDirectories.joined(separator: "|")) sent:\(sentFromFilePreview)"
    }
}

enum FileSearchFixture {
    static let argument = "UITEST_FILE_SEARCH_FIXTURE"
    static let modeKey = "FILE_SEARCH_FIXTURE_MODE"
    static let resultPath = "notes.txt"
    static let sentinel = "W06_FILE_SENTINEL"
    static let directory = "/tmp/w06-files"
    static let workspaceA = "/tmp/w06-ws-a"
    static let workspaceB = "/tmp/w06-ws-b"
    static let contentA = "CONTENT_A"
    static let contentB = "CONTENT_B"
    @MainActor static let probe = FileSearchProbe()

    enum Mode: String {
        case results
        case empty
        case loading
        case live
        case split
    }

    static var routesSplitHost: Bool {
        isActive && mode == .split
    }

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var mode: Mode {
        let raw = ProcessInfo.processInfo.environment[modeKey] ?? Mode.results.rawValue
        return Mode(rawValue: raw) ?? .results
    }

    @MainActor
    static func makeAppState() -> AppState {
        probe.findDirectories = []
        probe.contentDirectories = []
        probe.sentFromFilePreview = false
        let defaults = UITestFixtures.isolatedDefaults(label: "file-search")
        return AppState(
            apiClient: StubClient(),
            sseClient: SSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: HostCredentialAccess(
                save: { _, _ in },
                load: { _ in nil },
                delete: { _ in }
            )
        )
    }

    @MainActor
    static func apply(to state: AppState) {
        state.isConnected = true
        state.selectedTab = RootTab.files.rawValue
        if ProcessInfo.processInfo.environment["UITEST_LAYOUT_PREFERENCE"] == "focus" {
            state.layoutPreference = .focus
        }
        let filesDirectory = mode == .live || mode == .split ? workspaceB : directory
        let sessionDirectory = mode == .live || mode == .split ? workspaceA : directory
        let checksNarrowControls = ProcessInfo.processInfo.environment["UITEST_NARROW_WORKSPACE_CONTROLS"] == "1"
        state.selectedProjectWorktree = checksNarrowControls ? nil : filesDirectory
        state.sessions = [
            Session(
                id: "w06-files",
                slug: "w06-files",
                projectID: "p1",
                directory: sessionDirectory,
                parentID: nil,
                title: checksNarrowControls ? "Review notes and implementation details for the sidebar layout" : "Files",
                version: "1",
                time: .init(created: 1, updated: 2, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = "w06-files"
        if checksNarrowControls {
            state.modelShortlist = [.init(providerID: "fixture", modelID: "workspace",
                                          displayName: "Workspace Reasoning Model", shortName: "Workspace Reasoning Model")]
            state.selectedModelIndex = 0
        }
        state.fileTreeRoot = [
            FileNode(name: "src", path: "src", absolute: nil, type: "directory", ignored: false)
        ]
        state.fileStore.fileSearchOwner = state.captureHostRequestSnapshot()
        state.fileStore.fileSearchDirectory = state.effectiveProjectDirectory
        state.fileStore.fileChildrenScope = FileChildrenScope(
            host: state.captureHostRequestSnapshot(),
            directory: state.effectiveProjectDirectory
        )
        switch mode {
        case .results:
            state.fileSearchQuery = "notes"
            state.fileSearchResults = [resultPath]
            state.fileStore.fileSearchInFlight = false
        case .empty:
            state.fileSearchQuery = "missing"
            state.fileSearchResults = []
            state.fileStore.fileSearchInFlight = false
        case .loading:
            state.fileSearchQuery = "notes"
            state.fileSearchResults = []
            state.fileStore.fileSearchInFlight = true
        case .live, .split:
            state.fileTreeRoot = [
                FileNode(name: "notes.txt", path: resultPath, absolute: nil, type: "file", ignored: false)
            ]
            state.fileSearchQuery = ""
            state.fileSearchResults = []
            state.fileStore.fileSearchInFlight = false
        }
        #if DEBUG
        if let stale = ProcessInfo.processInfo.environment["UITEST_STALE_INLINE"], !stale.isEmpty {
            state.inlinePreviewPath = stale
            state.inlinePreviewWorkspaceDirectory = filesDirectory
            state.inlineEventSequence = 1
        }
        if ProcessInfo.processInfo.environment["UITEST_FILE_SEARCH_OPEN_PREVIEW"] == "1" {
            state.previewFilePath = resultPath
            state.previewFileWorkspaceDirectory = filesDirectory
            state.columnEventSequence = 2
        }
        #endif
    }

    actor StubClient: APIClientProtocol, FileDirectorySearching {
        func configure(baseURL: String, username: String?, password: String?) {}
        func health() async throws -> HealthResponse { HealthResponse(healthy: true, version: "fixture") }
        func projects() async throws -> [Project] { [] }
        func projectCurrent() async throws -> Project? { nil }
        func sessions(directory: String?, limit: Int) async throws -> [Session] { [] }
        func session(sessionID: String) async throws -> Session {
            throw APIError.httpError(statusCode: 404, data: Data())
        }
        func createSession(title: String?, directory: String?) async throws -> Session {
            guard ProcessInfo.processInfo.environment["UITEST_NARROW_WORKSPACE_CONTROLS"] == "1" else {
                throw APIError.httpError(statusCode: 501, data: Data())
            }
            let now = Int(Date().timeIntervalSince1970 * 1000)
            return Session(id: "w06-created", slug: "w06-created", projectID: "p1",
                           directory: directory ?? FileSearchFixture.directory, parentID: nil,
                           title: "Created from sidebar", version: "1", time: .init(created: now, updated: now, archived: nil),
                           share: nil, summary: nil)
        }
        func updateSession(sessionID: String, title: String) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func deleteSession(sessionID: String) async throws {}
        func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] { [] }
        func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {
            if sessionID == "w06-files", text == "Read this file with me" {
                await MainActor.run { FileSearchFixture.probe.sentFromFilePreview = true }
            }
        }
        func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func abort(sessionID: String) async throws {}
        func sessionStatus() async throws -> [String: SessionStatus] { [:] }
        func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
        func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
        func pendingQuestions() async throws -> [QuestionRequest] { [] }
        func replyQuestion(requestID: String, answers: [[String]]) async throws {}
        func rejectQuestion(requestID: String) async throws {}
        func providers() async throws -> ProvidersResponse {
            try JSONDecoder().decode(ProvidersResponse.self, from: Data("{\"providers\":[]}".utf8))
        }
        func providerRegistry() async throws -> ProviderRegistryResponse {
            ProviderRegistryResponse(providers: [], connectedProviderIDs: [])
        }
        func agents() async throws -> [AgentInfo] { [] }
        func sessionDiff(sessionID: String) async throws -> [FileDiff] { [] }
        func sessionTodos(sessionID: String) async throws -> [TodoItem] { [] }
        func fileList(path: String, directory: String?) async throws -> [FileNode] { [] }
        func fileContent(path: String, directory: String?) async throws -> FileContent {
            let recorded = directory ?? ""
            await MainActor.run {
                FileSearchFixture.probe.contentDirectories.append(recorded)
            }
            if FileSearchFixture.mode == .live || FileSearchFixture.mode == .split {
                let text = directory == FileSearchFixture.workspaceB ? FileSearchFixture.contentB : FileSearchFixture.contentA
                return FileContent(type: "text", content: text)
            }
            return FileContent(type: "text", content: FileSearchFixture.sentinel)
        }
        func findFile(query: String, limit: Int) async throws -> [String] {
            try await findFile(query: query, limit: limit, directory: nil)
        }
        func findFile(query: String, limit: Int, directory: String?) async throws -> [String] {
            let recorded = directory ?? ""
            await MainActor.run {
                FileSearchFixture.probe.findDirectories.append(recorded)
            }
            if FileSearchFixture.mode == .live || FileSearchFixture.mode == .split {
                return query.isEmpty ? [] : [FileSearchFixture.resultPath]
            }
            return [FileSearchFixture.resultPath]
        }
        func fileStatus() async throws -> [FileStatusEntry] { [] }
        func forkSession(sessionID: String, messageID: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
    }
}

struct FileSearchSplitHost: View {
    @Bindable var state: AppState

    private var showsPreview: Bool {
        guard let path = state.previewFilePath else { return false }
        return !path.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                FileTreeView(state: state, forceSplitPreview: true)
                    .fileSearchQueryHandlers(state: state)
                    .navigationTitle(L10n.t(.navFiles))
            }
            .frame(minHeight: 140, maxHeight: showsPreview ? 180 : 360)
            if showsPreview, let path = state.previewFilePath {
                FileContentView(
                    state: state,
                    filePath: path,
                    workspaceDirectory: state.previewFileWorkspaceDirectory ?? "",
                    boundSessionID: state.previewSessionID
                )
                .frame(minHeight: 240, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("split")
                .font(.system(size: 1))
                .accessibilityIdentifier("file-search-split-host")
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            Text(FileSearchFixture.probe.summary)
                .font(.system(size: 1))
                .accessibilityIdentifier("file-search-probe")
                .allowsHitTesting(false)
        }
    }
}
