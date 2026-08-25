import Foundation

struct SessionScopedState {
    var activities: [String: SessionActivity] = [:]
    var statusUpdatedAt: [String: Date] = [:]
    var activityTextLastChangeAt: [String: Date] = [:]
    var activityTextPendingTask: [String: Task<Void, Never>] = [:]
    var loadedMessageLimit: [String: Int] = [:]
    var hasMoreHistory: [String: Bool] = [:]
    var loadingOlderMessages: Set<String> = []
    var draftInputs: [String: String] = [:]
    var selectedModelIDs: [String: String] = [:]
    var pendingPermissions: [PendingPermission] = []
    var pendingQuestions: [QuestionRequest] = []

    mutating func remove(sessionID: String) {
        activities[sessionID] = nil
        statusUpdatedAt[sessionID] = nil
        activityTextLastChangeAt[sessionID] = nil
        activityTextPendingTask[sessionID]?.cancel()
        activityTextPendingTask[sessionID] = nil
        loadedMessageLimit[sessionID] = nil
        hasMoreHistory[sessionID] = nil
        loadingOlderMessages.remove(sessionID)
        draftInputs[sessionID] = nil
        selectedModelIDs[sessionID] = nil
        pendingPermissions.removeAll { $0.sessionID == sessionID }
        pendingQuestions.removeAll { $0.sessionID == sessionID }
    }

    mutating func resetAll() {
        activityTextPendingTask.values.forEach { $0.cancel() }
        self = SessionScopedState()
    }
}
