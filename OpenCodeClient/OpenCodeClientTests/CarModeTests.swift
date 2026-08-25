//
//  CarModeTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
import VoiceFlowKit
@testable import OpenCodeClient

@Suite(.serialized)
struct CarModeFlowTests {
    @Test func pendingCarFileKeepsOriginatingStrategy() {
        let url = URL(fileURLWithPath: "/tmp/gpt-live.wav")
        let pending = PendingCarAudio.file(url, strategy: .gptLiveTranscribe)
        #expect(pending.strategy == .gptLiveTranscribe)
    }

    @Test @MainActor func submitCarTurnReusesScopedSessionAndSpeaksOnce() async throws {
        let defaultsKey = AppState.carSessionsByContextKey
        let oldValue = UserDefaults.standard.data(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        defer {
            if let oldValue { UserDefaults.standard.set(oldValue, forKey: defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
        }

        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = AppState(
            apiClient: api,
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(),
            carSpeechOutput: speech
        )
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        let session = Session(
            id: "car-session",
            slug: "car-session",
            projectID: "p1",
            directory: "/tmp/car-workspace",
            parentID: nil,
            title: "Car Mode",
            version: "1",
            time: .init(created: 1, updated: 1, archived: nil),
            share: nil,
            summary: nil
        )
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(MessageWithParts(
            info: Message(
                id: "assistant-1",
                sessionID: session.id,
                role: "assistant",
                parentID: "user-1",
                providerID: "openai",
                modelID: "gpt-5.6-sol-fast",
                model: nil,
                error: nil,
                time: .init(created: 2, completed: 3),
                finish: "tool-calls",
                tokens: nil,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .completed,
                    speech: "The garage door is closed.",
                    confirmation: nil,
                    clientActions: []
                )
            ),
            parts: []
        ))

        await state.submitCarTurn("Is the garage closed?")
        await api.setSessionResult(Session(
            id: session.id,
            slug: session.slug,
            projectID: session.projectID,
            directory: session.directory,
            parentID: nil,
            title: session.title,
            version: session.version,
            time: .init(created: 1, updated: 2, archived: 2),
            share: nil,
            summary: nil
        ))
        await state.submitCarTurn("Is the garage still closed?")

        #expect(state.currentCarSessionID == session.id)
        #expect(state.carPhase == .idle)
        #expect(speech.spokenTexts == ["The garage door is closed."])
        #expect(await api.promptStructuredCalls.count == 2)
        #expect(await api.promptStructuredCalls.first?.modelID == "gpt-5.6-sol-fast")
        #expect(await api.promptStructuredCalls.allSatisfy { $0.sessionID == session.id })
        #expect(await api.updateSessionArchivedCalls.map(\.1) == [-1])
    }

    @Test @MainActor func selectedProjectCanRestoreExistingCarSession() async throws {
        let oldSelection = UserDefaults.standard.string(forKey: AppState.selectedProjectWorktreeKey)
        let oldCarSessions = UserDefaults.standard.data(forKey: AppState.carSessionsByContextKey)
        UserDefaults.standard.removeObject(forKey: AppState.selectedProjectWorktreeKey)
        UserDefaults.standard.removeObject(forKey: AppState.carSessionsByContextKey)
        defer {
            if let oldSelection { UserDefaults.standard.set(oldSelection, forKey: AppState.selectedProjectWorktreeKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.selectedProjectWorktreeKey) }
            if let oldCarSessions { UserDefaults.standard.set(oldCarSessions, forKey: AppState.carSessionsByContextKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.carSessionsByContextKey) }
        }

        let api = MockAPIClient()
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/server-default"
        state.selectedProjectWorktree = "/workspace/selected"
        let session = Session(
            id: "selected-car-session",
            slug: "selected-car-session",
            projectID: "p1",
            directory: "/workspace/selected",
            parentID: nil,
            title: "Car Mode",
            version: "1",
            time: .init(created: 1, updated: 2, archived: 3),
            share: nil,
            summary: nil
        )
        state.carSessionsByContext[state.carContextKey] = CarSessionRecord(
            sessionID: session.id,
            lastHandledAssistantMessageID: nil,
            pendingConfirmationID: nil,
            lastUsedAt: Date()
        )
        await api.setSessionResult(session)
        await api.setPromptStructuredResult(MessageWithParts(
            info: Message(
                id: "selected-assistant",
                sessionID: session.id,
                role: "assistant",
                parentID: "selected-user",
                providerID: "openai",
                modelID: "gpt-5.6-sol-fast",
                model: nil,
                error: nil,
                time: .init(created: 4, completed: 5),
                finish: "tool-calls",
                tokens: nil,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .completed,
                    speech: "Restored.",
                    confirmation: nil,
                    clientActions: []
                )
            ),
            parts: []
        ))

        await state.submitCarTurn("Continue")

        #expect(state.carPhase == .idle)
        #expect(await api.updateSessionArchivedCalls.map(\.0) == [session.id])
        #expect(await api.promptStructuredCalls.map(\.sessionID) == [session.id])
    }

    @Test @MainActor func carSessionContextSeparatesHostsAndWorkspaces() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.serverCurrentProjectWorktree = "/workspace/a"
        let first = state.carContextKey
        state.serverCurrentProjectWorktree = "/workspace/b"
        let second = state.carContextKey
        state.currentHostProfileID = UUID()
        let third = state.carContextKey

        #expect(first != second)
        #expect(second != third)
    }

    @Test @MainActor func selectedProjectCannotReuseServerDefaultCarSession() async {
        let oldSelection = UserDefaults.standard.string(forKey: AppState.selectedProjectWorktreeKey)
        defer {
            if let oldSelection { UserDefaults.standard.set(oldSelection, forKey: AppState.selectedProjectWorktreeKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.selectedProjectWorktreeKey) }
        }
        let api = MockAPIClient()
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/server-default"
        state.selectedProjectWorktree = "/workspace/selected"

        await state.submitCarTurn("Hello")

        #expect(state.carPhase == .failed)
        #expect(state.carError == CarModeError.selectedProjectUnsupported.localizedDescription)
        #expect(await api.promptStructuredCalls.isEmpty)
    }

    @Test @MainActor func failedStructuredResponseKeepsCarModeFailed() async throws {
        let oldSelection = UserDefaults.standard.string(forKey: AppState.selectedProjectWorktreeKey)
        let oldCarSessions = UserDefaults.standard.data(forKey: AppState.carSessionsByContextKey)
        UserDefaults.standard.removeObject(forKey: AppState.carSessionsByContextKey)
        defer {
            if let oldSelection { UserDefaults.standard.set(oldSelection, forKey: AppState.selectedProjectWorktreeKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.selectedProjectWorktreeKey) }
            if let oldCarSessions { UserDefaults.standard.set(oldCarSessions, forKey: AppState.carSessionsByContextKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.carSessionsByContextKey) }
        }
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = AppState(
            apiClient: api,
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(),
            carSpeechOutput: speech
        )
        state.isConnected = true
        state.selectedProjectWorktree = nil
        let session = Session(
            id: "car-failed",
            slug: "car-failed",
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: "Car Mode",
            version: "1",
            time: .init(created: 1, updated: 1, archived: nil),
            share: nil,
            summary: nil
        )
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(MessageWithParts(
            info: Message(
                id: "assistant-failed",
                sessionID: session.id,
                role: "assistant",
                parentID: "user-1",
                providerID: "openai",
                modelID: "gpt-5.6-sol-fast",
                model: nil,
                error: nil,
                time: .init(created: 2, completed: 3),
                finish: "tool-calls",
                tokens: nil,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .failed,
                    speech: "I could not complete that request.",
                    confirmation: nil,
                    clientActions: []
                )
            ),
            parts: []
        ))

        await state.submitCarTurn("Try it")

        #expect(state.carPhase == .failed)
        #expect(speech.spokenTexts == ["I could not complete that request."])
    }

    @Test @MainActor func cancellingWithoutActiveTurnDoesNotAbortSession() async {
        let api = MockAPIClient()
        let state = AppState(apiClient: api, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())

        await state.cancelCarInteraction()

        #expect(await api.abortSessionIDs.isEmpty)
    }
}
