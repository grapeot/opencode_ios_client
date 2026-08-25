import Foundation
import Testing
@testable import OpenCodeClient

struct SessionScopedStateTests {
    @Test func removeClearsEverySessionKeyedFieldIncludingQuestions() {
        var scope = SessionScopedState()
        scope.activities["s1"] = SessionActivity(sessionID: "s1", state: .running, text: "x", startedAt: Date())
        scope.statusUpdatedAt["s1"] = Date()
        scope.activityTextLastChangeAt["s1"] = Date()
        scope.loadedMessageLimit["s1"] = 40
        scope.hasMoreHistory["s1"] = true
        scope.loadingOlderMessages.insert("s1")
        scope.draftInputs["s1"] = "draft"
        scope.selectedModelIDs["s1"] = "google/gemini-3.5-flash"
        scope.pendingPermissions = [
            PendingPermission(
                sessionID: "s1",
                permissionID: "p1",
                permission: nil,
                patterns: [],
                allowAlways: false,
                tool: nil,
                description: "x"
            )
        ]
        scope.pendingQuestions = [
            QuestionRequest(id: "q1", sessionID: "s1", questions: [], tool: nil),
            QuestionRequest(id: "q2", sessionID: "s2", questions: [], tool: nil)
        ]
        scope.activities["s2"] = SessionActivity(sessionID: "s2", state: .completed, text: "y", startedAt: Date())

        scope.remove(sessionID: "s1")

        #expect(scope.activities["s1"] == nil)
        #expect(scope.activities["s2"] != nil)
        #expect(scope.loadedMessageLimit["s1"] == nil)
        #expect(scope.hasMoreHistory["s1"] == nil)
        #expect(!scope.loadingOlderMessages.contains("s1"))
        #expect(scope.draftInputs["s1"] == nil)
        #expect(scope.selectedModelIDs["s1"] == nil)
        #expect(scope.pendingPermissions.isEmpty)
        #expect(scope.pendingQuestions.map(\.id) == ["q2"])
    }

    @Test func resetAllClearsHostSwitchLeftovers() {
        var scope = SessionScopedState()
        scope.activities["s1"] = SessionActivity(sessionID: "s1", state: .running, text: "x", startedAt: Date())
        scope.loadedMessageLimit["s1"] = 40
        scope.pendingQuestions = [QuestionRequest(id: "q1", sessionID: "s1", questions: [], tool: nil)]
        scope.draftInputs["s1"] = "draft"
        scope.resetAll()
        #expect(scope.activities.isEmpty)
        #expect(scope.loadedMessageLimit.isEmpty)
        #expect(scope.pendingQuestions.isEmpty)
        #expect(scope.draftInputs.isEmpty)
    }

    @Test @MainActor func hostSwitchResetsPreviouslyLeakedSessionCaches() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.sessionActivities["s1"] = SessionActivity(sessionID: "s1", state: .running, text: "x", startedAt: Date())
        state.loadedMessageLimitBySessionID["s1"] = 40
        state.hasMoreHistoryBySessionID["s1"] = true
        state.pendingQuestions = [QuestionRequest(id: "q1", sessionID: "s1", questions: [], tool: nil)]
        state.draftInputsBySessionID["s1"] = "draft"
        state.selectedModelIDBySessionID["s1"] = "google/gemini-3.5-flash"

        state.resetConnectionRuntimeForHostSwitch()

        #expect(state.sessionActivities.isEmpty)
        #expect(state.loadedMessageLimitBySessionID.isEmpty)
        #expect(state.hasMoreHistoryBySessionID.isEmpty)
        #expect(state.pendingQuestions.isEmpty)
        #expect(state.pendingPermissions.isEmpty)
        #expect(state.draftInputsBySessionID.isEmpty)
        #expect(state.selectedModelIDBySessionID.isEmpty)
    }

    @Test @MainActor func clearSessionScopedCachesDropsQuestionsForThatSessionOnly() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        state.pendingQuestions = [
            QuestionRequest(id: "q1", sessionID: "s1", questions: [], tool: nil),
            QuestionRequest(id: "q2", sessionID: "s2", questions: [], tool: nil)
        ]
        state.sessionActivities["s1"] = SessionActivity(sessionID: "s1", state: .running, text: "x", startedAt: Date())
        state.clearSessionScopedCaches(sessionID: "s1")
        #expect(state.pendingQuestions.map(\.id) == ["q2"])
        #expect(state.sessionActivities["s1"] == nil)
    }
}
