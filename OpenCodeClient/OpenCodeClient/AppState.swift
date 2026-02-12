//
//  AppState.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var serverURL: String = APIClient.defaultServer
    var username: String = ""
    var password: String = ""
    var isConnected: Bool = false
    var serverVersion: String?
    var connectionError: String?
    var sendError: String?

    var sessions: [Session] = []
    var currentSessionID: String?
    var sessionStatuses: [String: SessionStatus] = [:]

    var messages: [MessageWithParts] = []
    var partsByMessage: [String: [Part]] = [:]

    /// 固定三个模型，不再从 server 导入
    var modelPresets: [ModelPreset] = [
        ModelPreset(displayName: "GPT-5.2", providerID: "openai", modelID: "gpt-5.2"),
        ModelPreset(displayName: "Opus 4.6", providerID: "poe", modelID: "anthropic/claude-opus-4-6"),
        ModelPreset(displayName: "GLM-4.7", providerID: "zai-coding-plan", modelID: "glm-4.7"),
    ]
    var selectedModelIndex: Int = 0

    var pendingPermissions: [PendingPermission] = []

    var themePreference: String = "auto"  // "auto" | "light" | "dark"

    var sessionDiffs: [FileDiff] = []
    var selectedDiffFile: String?
    var selectedTab: Int = 0  // 0=Chat, 1=Files, 2=Settings
    var fileToOpenInFilesTab: String?  // 从 Chat 中 tool 点击跳转时设置，Files tab 或 sheet 展示

    var fileTreeRoot: [FileNode] = []
    var fileStatusMap: [String: String] = [:]  // path -> status
    var expandedPaths: Set<String> = []
    var fileChildrenCache: [String: [FileNode]] = [:]  // path -> children
    var fileSearchQuery: String = ""
    var fileSearchResults: [String] = []

    private let apiClient = APIClient()
    private let sseClient = SSEClient()
    private var sseTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    var selectedModel: ModelPreset? {
        guard modelPresets.indices.contains(selectedModelIndex) else { return nil }
        return modelPresets[selectedModelIndex]
    }

    var currentSession: Session? {
        guard let id = currentSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    var currentSessionStatus: SessionStatus? {
        guard let id = currentSessionID else { return nil }
        return sessionStatuses[id]
    }

    var isBusy: Bool {
        currentSessionStatus?.type == "busy"
    }

    func configure(serverURL: String, username: String? = nil, password: String? = nil) {
        self.serverURL = serverURL.hasPrefix("http") ? serverURL : "http://\(serverURL)"
        self.username = username ?? ""
        self.password = password ?? ""
    }

    func testConnection() async {
        connectionError = nil
        await apiClient.configure(baseURL: serverURL, username: username.isEmpty ? nil : username, password: password.isEmpty ? nil : password)
        do {
            let health = try await apiClient.health()
            isConnected = health.healthy
            serverVersion = health.version
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
        }
    }

    func loadSessions() async {
        guard isConnected else { return }
        do {
            sessions = try await apiClient.sessions()
            if currentSessionID == nil, let first = sessions.first {
                currentSessionID = first.id
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func refreshSessions() async {
        guard isConnected else { return }
        await loadSessions()
        if let statuses = try? await apiClient.sessionStatus() {
            sessionStatuses = statuses
        }
    }

    func selectSession(_ session: Session) {
        currentSessionID = session.id
        Task {
            await loadMessages()
            await loadSessionDiff()
        }
    }

    func createSession() async {
        guard isConnected else { return }
        do {
            let session = try await apiClient.createSession()
            sessions.insert(session, at: 0)
            currentSessionID = session.id
            messages = []
            partsByMessage = [:]
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadMessages() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let loaded = try await apiClient.messages(sessionID: sessionID)
            messages = loaded
            partsByMessage = Dictionary(uniqueKeysWithValues: loaded.map { ($0.info.id, $0.parts) })
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadSessionDiff() async {
        guard let sessionID = currentSessionID else { sessionDiffs = []; return }
        do {
            sessionDiffs = try await apiClient.sessionDiff(sessionID: sessionID)
        } catch {
            sessionDiffs = []
        }
    }

    func loadFileTree() async {
        do {
            fileTreeRoot = try await apiClient.fileList(path: "")
        } catch {
            fileTreeRoot = []
        }
    }

    func loadFileStatus() async {
        do {
            let entries = try await apiClient.fileStatus()
            fileStatusMap = Dictionary(uniqueKeysWithValues: entries.compactMap { e in
                guard let p = e.path else { return nil }
                return (p, e.status ?? "")
            })
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
            fileSearchResults = try await apiClient.findFile(query: query)
        } catch {
            fileSearchResults = []
        }
    }

    func loadFileContent(path: String) async throws -> FileContent {
        try await apiClient.fileContent(path: path)
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

    func sendMessage(_ text: String) async -> Bool {
        sendError = nil
        guard let sessionID = currentSessionID else {
            sendError = "请先选择或创建 Session"
            return false
        }
        let model = selectedModel.map { Message.ModelInfo(providerID: $0.providerID, modelID: $0.modelID) }
        do {
            try await apiClient.promptAsync(sessionID: sessionID, text: text, model: model)
            startPollingAfterSend()
            return true
        } catch {
            sendError = error.localizedDescription
            return false
        }
    }

    private func startPollingAfterSend() {
        pollingTask?.cancel()
        pollingTask = Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await loadMessages()
            }
        }
    }

    func abortSession() async {
        guard let sessionID = currentSessionID else { return }
        do {
            try await apiClient.abort(sessionID: sessionID)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func summarizeSession() async {
        guard let sessionID = currentSessionID else { return }
        do {
            try await apiClient.summarize(sessionID: sessionID)
            await loadMessages()
            await refreshSessions()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func updateSessionTitle(sessionID: String, title: String) async {
        do {
            _ = try await apiClient.updateSession(sessionID: sessionID, title: title)
            await refreshSessions()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func respondPermission(_ perm: PendingPermission, approved: Bool) async {
        guard approved else {
            pendingPermissions.removeAll { $0.id == perm.id }
            return
        }
        do {
            try await apiClient.respondPermission(sessionID: perm.sessionID, permissionID: perm.permissionID)
            pendingPermissions.removeAll { $0.id == perm.id }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func connectSSE() {
        sseTask?.cancel()
        sseTask = Task {
            let stream = await sseClient.connect(
                baseURL: serverURL,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password
            )
            do {
                for try await event in stream {
                    await handleSSEEvent(event)
                }
            } catch {}
        }
    }

    func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }

    private func handleSSEEvent(_ event: SSEEvent) async {
        let type = event.payload.type
        let props = event.payload.properties ?? [:]

        switch type {
        case "session.status":
            if let sessionID = props["sessionID"]?.value as? String,
               let statusObj = props["status"]?.value as? [String: Any] {
                if let status = try? JSONSerialization.data(withJSONObject: statusObj),
                   let decoded = try? JSONDecoder().decode(SessionStatus.self, from: status) {
                    sessionStatuses[sessionID] = decoded
                }
            }
        case "message.updated", "message.part.updated":
            if currentSessionID != nil {
                await loadMessages()
                await loadSessionDiff()
            }
        case "permission.asked":
            if let sessionID = props["sessionID"]?.value as? String,
               let permissionID = props["permissionID"]?.value as? String {
                let desc = (props["description"]?.value as? String) ?? (props["tool"]?.value as? String) ?? "Permission required"
                let perm = PendingPermission(sessionID: sessionID, permissionID: permissionID, description: desc)
                if !pendingPermissions.contains(where: { $0.permissionID == permissionID }) {
                    pendingPermissions.append(perm)
                }
            }
        default:
            break
        }
    }

    func refresh() async {
        await apiClient.configure(baseURL: serverURL, username: username.isEmpty ? nil : username, password: password.isEmpty ? nil : password)
        await testConnection()
        if isConnected {
            await loadSessions()
            await loadMessages()
            await loadSessionDiff()
            await loadFileTree()
            await loadFileStatus()
            let statuses = try? await apiClient.sessionStatus()
            if let statuses { sessionStatuses = statuses }
        }
    }
}

struct PendingPermission: Identifiable {
    var id: String { "\(sessionID)/\(permissionID)" }
    let sessionID: String
    let permissionID: String
    let description: String
}
