import Foundation

/// Permission + question responses. Both are async server requests; the
/// SSE channel doesn't replay them, so `refresh*` is called when the user
/// enters a session that was already mid-flight.
extension AppState {
    func respondPermission(_ perm: PendingPermission, response: APIClient.PermissionResponse) async {
        do {
            try await apiClient.respondPermission(sessionID: perm.sessionID, permissionID: perm.permissionID, response: response)
            pendingPermissions.removeAll { $0.id == perm.id }
            await refreshPendingPermissions()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    /// SSE permission events are not replayed; poll pending permissions so users can enter
    /// an in-progress session and still see the warning.
    func refreshPendingPermissions() async {
        guard isConnected else { return }
        do {
            let requests = try await apiClient.pendingPermissions()
            pendingPermissions = PermissionController.fromPendingRequests(requests)
        } catch {
            // Keep the current list on errors.
        }
    }

    func respondQuestion(_ request: QuestionRequest, answers: [[String]]) async {
        do {
            try await apiClient.replyQuestion(requestID: request.id, answers: answers)
            pendingQuestions.removeAll { $0.id == request.id }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func rejectQuestion(_ request: QuestionRequest) async {
        do {
            try await apiClient.rejectQuestion(requestID: request.id)
            pendingQuestions.removeAll { $0.id == request.id }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func refreshPendingQuestions() async {
        guard isConnected else { return }
        do {
            pendingQuestions = try await apiClient.pendingQuestions()
        } catch {
            connectionError = error.localizedDescription
        }
    }
}
