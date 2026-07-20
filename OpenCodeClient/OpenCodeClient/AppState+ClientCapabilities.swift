import Foundation
import CryptoKit

enum ClientCapabilityError: LocalizedError {
    case alreadyRunning
    case launchFailed
    case invalidCallback
    case continuationFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: L10n.t(.capabilityAlreadyRunning)
        case .launchFailed: L10n.t(.capabilityLaunchFailed)
        case .invalidCallback: L10n.t(.capabilityInvalidCallback)
        case .continuationFailed: L10n.t(.capabilityContinuationFailed)
        }
    }
}

extension AppState {
    func requestClientCapability(
        _ action: CarClientAction,
        sessionID: String,
        carContextKey: String,
        assistantMessageID: String
    ) async {
        guard case .healthExportAll = action else { return }
        if healthExportPermission == .allowAlways {
            await dispatchClientCapability(
                action,
                hostProfileID: currentHostProfileID,
                sessionID: sessionID,
                carContextKey: carContextKey,
                assistantMessageID: assistantMessageID
            )
        } else {
            pendingClientCapabilityRequest = PendingClientCapabilityRequest(
                action: action,
                hostProfileID: currentHostProfileID,
                sessionID: sessionID,
                carContextKey: carContextKey,
                assistantMessageID: assistantMessageID
            )
        }
    }

    func resolveClientCapabilityPermission(allow: Bool, always: Bool = false) async {
        guard let request = pendingClientCapabilityRequest else { return }
        pendingClientCapabilityRequest = nil
        guard allow else { return }
        if always { healthExportPermission = .allowAlways }
        await dispatchClientCapability(
            request.action,
            hostProfileID: request.hostProfileID,
            sessionID: request.sessionID,
            carContextKey: request.carContextKey,
            assistantMessageID: request.assistantMessageID
        )
    }

    func revokeHealthExportPermission() {
        healthExportPermission = .ask
    }

    func receiveClientActionCallback(_ callback: ClientActionCallback) async {
        do {
            try clientCapabilityStore.cleanup()
            guard try clientCapabilityStore.consume(callback) != nil else { return }
            await retryClientCapabilityOutbox()
        } catch {
            clientCapabilityError = ClientCapabilityError.invalidCallback.localizedDescription
        }
    }

    func retryClientCapabilityOutbox() async {
        do {
            try clientCapabilityStore.cleanup()
            let records = try clientCapabilityStore.outboxRecords()
            for record in records {
                guard hostProfiles.contains(where: { $0.id == record.hostProfileID }) else {
                    try? clientCapabilityStore.removeOutbox(callbackID: record.callbackID)
                    continue
                }
                guard record.hostProfileID == currentHostProfileID else { continue }
                guard record.hostConfigurationSignature == clientCapabilityHostSignature(for: record.hostProfileID) else {
                    try? clientCapabilityStore.removeOutbox(callbackID: record.callbackID)
                    clientCapabilityError = ClientCapabilityError.continuationFailed.localizedDescription
                    continue
                }
                guard
                      isConnected,
                      !clientCapabilityInFlightCallbackIDs.contains(record.callbackID) else { continue }
                clientCapabilityInFlightCallbackIDs.insert(record.callbackID)
                await submitClientCapabilityContinuation(record)
                clientCapabilityInFlightCallbackIDs.remove(record.callbackID)
            }
        } catch {
            clientCapabilityError = ClientCapabilityError.continuationFailed.localizedDescription
        }
    }

    func cleanupClientCapabilityCallbacks() {
        try? clientCapabilityStore.cleanup()
    }

    private func dispatchClientCapability(
        _ action: CarClientAction,
        hostProfileID: UUID,
        sessionID: String,
        carContextKey: String,
        assistantMessageID: String
    ) async {
        guard case .healthExportAll(let actionID, _) = action else { return }
        guard hostProfileID == currentHostProfileID,
              hostProfiles.contains(where: { $0.id == hostProfileID }) else {
            clientCapabilityError = ClientCapabilityError.continuationFailed.localizedDescription
            return
        }
        do {
            let record = try clientCapabilityStore.createPending(
                capability: .healthExportAll,
                hostProfileID: hostProfileID,
                hostConfigurationSignature: clientCapabilityHostSignature(for: hostProfileID) ?? "",
                carContextKey: carContextKey,
                sessionID: sessionID,
                assistantMessageID: assistantMessageID,
                actionID: actionID
            )
            guard let url = Self.healthExportURL(callbackID: record.callbackID),
                  await clientCapabilityURLOpener(url) else {
                try? clientCapabilityStore.removePending(callbackID: record.callbackID)
                throw ClientCapabilityError.launchFailed
            }
        } catch ClientCapabilityCallbackStore.StoreError.duplicateCapability {
            clientCapabilityError = ClientCapabilityError.alreadyRunning.localizedDescription
        } catch {
            clientCapabilityError = error.localizedDescription
        }
    }

    private func submitClientCapabilityContinuation(_ record: ClientCapabilityCallbackRecord) async {
        guard let result = record.result else {
            try? clientCapabilityStore.removeOutbox(callbackID: record.callbackID)
            return
        }
        let continuationTurnID = beginClientCapabilityContinuationIfVisible(record)
        do {
            let routeGeneration = deepLinkRouteID
            for pollAttempt in 0..<15 {
                guard clientCapabilityContinuationIsActive(record, turnID: continuationTurnID) else { return }
                let history = try await apiClient.messages(sessionID: record.sessionID, limit: nil)
                guard clientCapabilityRouteIsCurrent(record, generation: routeGeneration),
                      clientCapabilityContinuationIsActive(record, turnID: continuationTurnID) else { return }
                if history.contains(where: { $0.info.id == record.continuationMessageID }) {
                    if let response = history.first(where: {
                        $0.info.isAssistant && $0.info.parentID == record.continuationMessageID
                    }), response.info.time.completed != nil {
                        try await handleClientCapabilityContinuationResponse(
                            response,
                            record: record,
                            continuationTurnID: continuationTurnID
                        )
                        try clientCapabilityStore.removeOutbox(callbackID: record.callbackID)
                        return
                    }
                    guard pollAttempt < 14 else {
                        finishClientCapabilityContinuationFailure(record, turnID: continuationTurnID)
                        return
                    }
                    try await Task.sleep(for: .seconds(2))
                    guard clientCapabilityRouteIsCurrent(record, generation: routeGeneration),
                          clientCapabilityContinuationIsActive(record, turnID: continuationTurnID) else { return }
                    continue
                }

                let response = try await apiClient.promptStructured(
                    sessionID: record.sessionID,
                    messageID: record.continuationMessageID,
                    text: try Self.clientResultText(record: record, result: result),
                    system: CarModeProtocol.clientResultSystemPrompt,
                    format: CarModeProtocol.outputFormat,
                    agent: "build",
                    model: CarModeProtocol.model
                )
                guard clientCapabilityRouteIsCurrent(record, generation: routeGeneration) else { return }
                try await handleClientCapabilityContinuationResponse(
                    response,
                    record: record,
                    continuationTurnID: continuationTurnID
                )
                try clientCapabilityStore.removeOutbox(callbackID: record.callbackID)
                return
            }
        } catch APIError.httpError(let statusCode, _) where [401, 403, 404].contains(statusCode) {
            try? clientCapabilityStore.removeOutbox(callbackID: record.callbackID)
            clientCapabilityError = ClientCapabilityError.continuationFailed.localizedDescription
            finishClientCapabilityContinuationFailure(record, turnID: continuationTurnID)
        } catch {
            // Retryable transport and server errors remain in Outbox until reconnect or expiration.
            finishClientCapabilityContinuationFailure(record, turnID: continuationTurnID)
        }
    }

    private func handleClientCapabilityContinuationResponse(
        _ response: MessageWithParts,
        record callbackRecord: ClientCapabilityCallbackRecord,
        continuationTurnID: UUID?
    ) async throws {
        guard response.info.isAssistant,
              response.info.sessionID == callbackRecord.sessionID,
              response.info.time.completed != nil,
              let envelope = response.info.structured,
              envelope.version == 1,
              !envelope.speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.clientActions.isEmpty else {
            throw CarModeError.invalidResponse
        }

        var carRecord = carSessionsByContext[callbackRecord.carContextKey] ?? CarSessionRecord(
            sessionID: callbackRecord.sessionID,
            lastHandledAssistantMessageID: nil,
            pendingConfirmationID: nil,
            lastUsedAt: Date()
        )
        carRecord.lastHandledAssistantMessageID = response.info.id
        carRecord.pendingConfirmationID = envelope.status == .needsConfirmation ? envelope.confirmation?.id : nil
        carRecord.lastUsedAt = Date()
        carSessionsByContext[callbackRecord.carContextKey] = carRecord
        persistCarSessions()

        guard let continuationTurnID,
              carContextKey == callbackRecord.carContextKey,
              carActiveTurnID == continuationTurnID,
              carActiveCapabilityCallbackID == callbackRecord.callbackID else { return }
        carLastResponse = envelope
        carPhase = .speaking
        await carSpeechOutput.speak(envelope.speech)
        guard carActiveTurnID == continuationTurnID,
              carActiveCapabilityCallbackID == callbackRecord.callbackID,
              carContextKey == callbackRecord.carContextKey,
              currentHostProfileID == callbackRecord.hostProfileID,
              clientCapabilityHostSignature(for: callbackRecord.hostProfileID) == callbackRecord.hostConfigurationSignature else { return }
        switch envelope.status {
        case .completed: carPhase = .idle
        case .needsConfirmation: carPhase = .awaitingConfirmation
        case .failed: carPhase = .failed
        }
        carActiveTurnID = nil
        carActiveCapabilityCallbackID = nil
    }

    private func beginClientCapabilityContinuationIfVisible(
        _ record: ClientCapabilityCallbackRecord
    ) -> UUID? {
        guard carContextKey == record.carContextKey, carActiveTurnID == nil else { return nil }
        let turnID = UUID()
        carActiveTurnID = turnID
        carActiveCapabilityCallbackID = record.callbackID
        carError = nil
        carPhase = .waitingReply
        return turnID
    }

    private func finishClientCapabilityContinuationFailure(
        _ record: ClientCapabilityCallbackRecord,
        turnID: UUID?
    ) {
        guard let turnID,
              carActiveTurnID == turnID,
              carActiveCapabilityCallbackID == record.callbackID else { return }
        carActiveTurnID = nil
        carActiveCapabilityCallbackID = nil
        carError = ClientCapabilityError.continuationFailed.localizedDescription
        carPhase = .failed
    }

    func clientCapabilityHostSignature(for hostProfileID: UUID) -> String? {
        guard let profile = hostProfiles.first(where: { $0.id == hostProfileID }) else { return nil }
        let ssh = profile.ssh.map {
            "\($0.isEnabled)|\($0.host)|\($0.port)|\($0.username)|\($0.remotePort)"
        } ?? ""
        let value = [
            profile.transport.rawValue,
            profile.serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
            profile.basicAuth?.username ?? "",
            ssh,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func clientCapabilityRouteIsCurrent(
        _ record: ClientCapabilityCallbackRecord,
        generation: UUID
    ) -> Bool {
        isConnected
            && deepLinkRouteID == generation
            && currentHostProfileID == record.hostProfileID
            && clientCapabilityHostSignature(for: record.hostProfileID) == record.hostConfigurationSignature
    }

    private func clientCapabilityContinuationIsActive(
        _ record: ClientCapabilityCallbackRecord,
        turnID: UUID?
    ) -> Bool {
        guard let turnID else { return true }
        return carActiveTurnID == turnID && carActiveCapabilityCallbackID == record.callbackID
    }

    nonisolated static func healthExportURL(callbackID: String) -> URL? {
        guard ClientCapabilityCallbackStore.isValidCallbackID(callbackID) else { return nil }
        var callback = URLComponents()
        callback.scheme = OpenCodeDeepLinkParser.scheme
        callback.host = "client-action-return"
        callback.path = "/\(callbackID)"
        guard let callbackURL = callback.url?.absoluteString else { return nil }

        var launch = URLComponents()
        launch.scheme = "healthquantification"
        launch.host = "export-all"
        launch.queryItems = [URLQueryItem(name: "callback", value: callbackURL)]
        return launch.url
    }

    nonisolated private static func clientResultText(
        record: ClientCapabilityCallbackRecord,
        result: ClientActionCallbackPayload
    ) throws -> String {
        struct Result: Encodable {
            let kind = "client_action_result"
            let capability: String
            let invocationID: String
            let status: HealthExportStatus
            let sent: Int
            let upserted: Int
            let failedCategories: [HealthExportCategory]
            let errorCode: HealthExportErrorCode?

            enum CodingKeys: String, CodingKey {
                case kind, capability, status, sent, upserted
                case invocationID = "invocation_id"
                case failedCategories = "failed_categories"
                case errorCode = "error_code"
            }
        }
        let value = Result(
            capability: record.capability.rawValue,
            invocationID: record.callbackID,
            status: result.status,
            sent: result.sent,
            upserted: result.upserted,
            failedCategories: result.failedCategories,
            errorCode: result.errorCode
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
