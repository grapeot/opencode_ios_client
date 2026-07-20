import Foundation

enum CarModeError: LocalizedError {
    case notConnected
    case selectedProjectUnsupported
    case invalidResponse
    case unsupportedAction
    case mapsUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected: return L10n.t(.carNotConnected)
        case .selectedProjectUnsupported: return L10n.t(.carServerDefaultRequired)
        case .invalidResponse: return L10n.t(.carInvalidResponse)
        case .unsupportedAction: return L10n.t(.carUnsupportedAction)
        case .mapsUnavailable: return L10n.t(.carMapsUnavailable)
        }
    }
}

extension AppState {
    var carContextKey: String {
        let directory = effectiveProjectDirectory ?? serverCurrentProjectWorktree ?? "__server_default__"
        return "\(currentHostProfileID.uuidString)|\(directory)"
    }

    var currentCarSessionRecord: CarSessionRecord? {
        carSessionsByContext[carContextKey]
    }

    var currentCarSessionID: String? {
        currentCarSessionRecord?.sessionID
    }

    func submitCarTurn(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let turnID = UUID()
        carActiveTurnID = turnID
        carLastTranscript = text
        carError = nil
        carPhase = .waitingReply

        do {
            let session = try await ensureCarSession()
            let response = try await apiClient.promptStructured(
                sessionID: session.id,
                text: text,
                system: CarModeProtocol.systemPrompt,
                format: CarModeProtocol.outputFormat,
                agent: "build",
                model: CarModeProtocol.model
            )
            guard carActiveTurnID == turnID else { return }
            try await handleCarResponse(response, sessionID: session.id, turnID: turnID)
        } catch {
            guard carActiveTurnID == turnID else { return }
            carError = error.localizedDescription
            carPhase = .failed
            carActiveTurnID = nil
        }
    }

    func cancelCarInteraction() async {
        let sessionID = currentCarSessionID
        let shouldAbort = carActiveTurnID != nil
        carActiveTurnID = nil
        carSpeechOutput.stop()
        carPhase = .idle
        if shouldAbort, let sessionID {
            try? await apiClient.abort(sessionID: sessionID)
        }
    }

    func startNewCarSession() async {
        await cancelCarInteraction()
        carSessionsByContext.removeValue(forKey: carContextKey)
        persistCarSessions()
        carLastTranscript = ""
        carLastResponse = nil
        carError = nil
    }

    private func ensureCarSession() async throws -> Session {
        guard isConnected else { throw CarModeError.notConnected }

        if let record = currentCarSessionRecord {
            do {
                let session = try await apiClient.session(sessionID: record.sessionID)
                guard session.isArchived else { return session }
                let restored = try await apiClient.updateSessionArchived(sessionID: session.id, archived: -1)
                upsertSession(restored)
                return restored
            } catch APIError.httpError(let statusCode, _) where statusCode == 404 {
                carSessionsByContext.removeValue(forKey: carContextKey)
                persistCarSessions()
            }
        }

        guard canCreateSession else { throw CarModeError.selectedProjectUnsupported }
        let session = try await apiClient.createSession(title: "Car Mode")
        carSessionsByContext[carContextKey] = CarSessionRecord(
            sessionID: session.id,
            lastHandledAssistantMessageID: nil,
            pendingConfirmationID: nil,
            lastUsedAt: Date()
        )
        persistCarSessions()
        upsertSession(session)
        return session
    }

    private func handleCarResponse(_ response: MessageWithParts, sessionID: String, turnID: UUID) async throws {
        guard response.info.isAssistant,
              response.info.sessionID == sessionID,
              response.info.time.completed != nil,
              let envelope = response.info.structured,
              envelope.version == 1,
              !envelope.speech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CarModeError.invalidResponse
        }
        guard currentCarSessionRecord?.lastHandledAssistantMessageID != response.info.id else {
            carPhase = .idle
            carActiveTurnID = nil
            return
        }
        var record = currentCarSessionRecord ?? CarSessionRecord(
            sessionID: sessionID,
            lastHandledAssistantMessageID: nil,
            pendingConfirmationID: nil,
            lastUsedAt: Date()
        )
        record.lastHandledAssistantMessageID = response.info.id
        record.pendingConfirmationID = envelope.status == .needsConfirmation ? envelope.confirmation?.id : nil
        record.lastUsedAt = Date()
        carSessionsByContext[carContextKey] = record
        persistCarSessions()

        carLastResponse = envelope
        carPhase = .speaking
        await carSpeechOutput.speak(envelope.speech)
        guard carActiveTurnID == turnID else { return }

        if envelope.status == .completed, let action = envelope.clientActions.first {
            switch action {
            case .openNavigation:
                guard await CarClientActionDispatcher.dispatch(action) else {
                    throw CarModeError.mapsUnavailable
                }
            case .healthExportAll:
                await requestClientCapability(
                    action,
                    sessionID: sessionID,
                    carContextKey: carContextKey,
                    assistantMessageID: response.info.id
                )
            case .unknown:
                break
            }
        }

        switch envelope.status {
        case .completed:
            carPhase = .idle
        case .needsConfirmation:
            carPhase = .awaitingConfirmation
        case .failed:
            carPhase = .failed
        }
        carActiveTurnID = nil
    }

    func persistCarSessions() {
        if carSessionsByContext.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.carSessionsByContextKey)
        } else if let data = try? JSONEncoder().encode(carSessionsByContext) {
            UserDefaults.standard.set(data, forKey: Self.carSessionsByContextKey)
        }
    }
}
