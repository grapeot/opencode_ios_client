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

    var modelPresets: [ModelPreset] = []
    var selectedModelIndex: Int = 0

    private let apiClient = APIClient()
    private let sseClient = SSEClient()
    private var sseTask: Task<Void, Never>?

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
        Task { await loadMessages() }
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

    func sendMessage(_ text: String) async -> Bool {
        sendError = nil
        guard let sessionID = currentSessionID else {
            sendError = "请先选择或创建 Session"
            return false
        }
        let model = selectedModel.map { Message.ModelInfo(providerID: $0.providerID, modelID: $0.modelID) }
        do {
            try await apiClient.promptAsync(sessionID: sessionID, text: text, model: model)
            return true
        } catch {
            sendError = error.localizedDescription
            return false
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
            if let sessionID = currentSessionID {
                await loadMessages()
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
            let statuses = try? await apiClient.sessionStatus()
            if let statuses { sessionStatuses = statuses }
        }
    }
}
