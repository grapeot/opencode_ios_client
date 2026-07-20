import Foundation
import Testing
@testable import OpenCodeClient

struct ClientCapabilityActionTests {
    @Test func decodesHealthAndUnknownActionsWithoutDroppingEnvelope() throws {
        let health = try JSONDecoder().decode(
            CarClientAction.self,
            from: Data(#"{"id":"health-1","type":"health_quantification.export_all","reason":"Refresh sleep data"}"#.utf8)
        )
        #expect(health == .healthExportAll(id: "health-1", reason: "Refresh sleep data"))

        let envelope = try JSONDecoder().decode(
            CarResponseEnvelope.self,
            from: Data(#"{"version":1,"status":"completed","speech":"Unsupported action ignored.","confirmation":null,"clientActions":[{"id":"future-1","type":"future.capability","payload":"ignored"}]}"#.utf8)
        )
        #expect(envelope.speech == "Unsupported action ignored.")
        #expect(envelope.clientActions == [.unknown(id: "future-1", type: "future.capability")])
    }

    @Test func buildsCanonicalHealthHandoffURL() throws {
        let callbackID = String(repeating: "a", count: 43)
        let url = try #require(AppState.healthExportURL(callbackID: callbackID))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "healthquantification")
        #expect(components.host == "export-all")
        #expect(components.queryItems == [
            URLQueryItem(name: "callback", value: "opencode://client-action-return/\(callbackID)")
        ])
    }
}

struct ClientCapabilityCallbackParserTests {
    private let callbackID = String(repeating: "A", count: 43)

    @Test func parsesBoundedCallbackResult() throws {
        let url = try #require(URL(string: "opencode://client-action-return/\(callbackID)?status=partial&sent=12&upserted=10&failed=sleep,workouts&error_code=category_failure"))
        let expected = ClientActionCallback(
            callbackID: callbackID,
            status: .partial,
            sent: 12,
            upserted: 10,
            failedCategories: [.sleep, .workouts],
            errorCode: .categoryFailure
        )
        #expect(OpenCodeDeepLinkParser.parse(url) == .success(.clientActionReturn(expected)))
    }

    @Test func rejectsMalformedCallbackResultsWithoutRelaxingSessionLinks() throws {
        let values = [
            "opencode://client-action-return/short?status=success&sent=1&upserted=1",
            "opencode://client-action-return/\(callbackID)/extra?status=success&sent=1&upserted=1",
            "opencode://client-action-return/\(callbackID)?status=unknown&sent=1&upserted=1",
            "opencode://client-action-return/\(callbackID)?status=success&sent=-1&upserted=1",
            "opencode://client-action-return/\(callbackID)?status=success&sent=1&upserted=1&extra=x",
            "opencode://client-action-return/\(callbackID)?status=success&status=failed&sent=1&upserted=1",
            "opencode://client-action-return/\(callbackID)?status=partial&sent=1&upserted=1&failed=unknown&error_code=category_failure",
            "opencode://client-action-return/\(callbackID)?status=failed&sent=0&upserted=0&error_code=free_text",
            "opencode://user@client-action-return/\(callbackID)?status=success&sent=1&upserted=1",
            "opencode://client-action-return:4096/\(callbackID)?status=success&sent=1&upserted=1",
            "opencode://client-action-return/\(callbackID)?status=success&sent=1&upserted=1#fragment",
        ]
        for value in values {
            let url = try #require(URL(string: value))
            guard case .failure = OpenCodeDeepLinkParser.parse(url) else {
                Issue.record("Expected callback to fail: \(value)")
                continue
            }
        }

        let session = try #require(URL(string: "opencode://session/ses_callback-regression"))
        #expect(OpenCodeDeepLinkParser.parse(session) == .success(.session(id: "ses_callback-regression")))
    }
}

struct ClientCapabilityCallbackStoreTests {
    @Test func pendingConsumesOnceAndPersistsNormalizedOutbox() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000)
        let store = ClientCapabilityCallbackStore(rootDirectory: root, now: { now })
        let record = try store.createPending(
            capability: .healthExportAll,
            hostProfileID: UUID(),
            carContextKey: "host|workspace",
            sessionID: "ses_original",
            assistantMessageID: "msg_assistant",
            actionID: "health-1"
        )
        #expect(record.callbackID.count == 43)
        #expect(record.continuationMessageID == "msg_client_\(record.callbackID)")
        #expect(try store.hasActiveRecord(for: .healthExportAll))

        let callback = ClientActionCallback(
            callbackID: record.callbackID,
            status: .success,
            sent: 42,
            upserted: 42,
            failedCategories: [],
            errorCode: nil
        )
        let accepted = try store.consume(callback)
        let consumed = try #require(accepted)
        #expect(consumed.result?.sent == 42)
        #expect(try store.consume(callback) == nil)
        #expect(try store.outboxRecords().map(\.callbackID) == [record.callbackID])
    }

    @Test func cleanupExpiresPendingAndRetainsRecentOutbox() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = ClientCapabilityCallbackStore(rootDirectory: root, now: { clock })
        let record = try store.createPending(
            capability: .healthExportAll,
            hostProfileID: UUID(),
            carContextKey: "host|workspace",
            sessionID: "ses_original",
            assistantMessageID: "msg_assistant",
            actionID: "health-1"
        )
        clock = clock.addingTimeInterval(ClientCapabilityCallbackStore.pendingLifetime + 1)
        try store.cleanup()
        #expect(try !store.hasActiveRecord(for: .healthExportAll))

        let next = try store.createPending(
            capability: .healthExportAll,
            hostProfileID: UUID(),
            carContextKey: "host|workspace",
            sessionID: "ses_original",
            assistantMessageID: "msg_assistant",
            actionID: "health-2"
        )
        _ = try store.consume(ClientActionCallback(
            callbackID: next.callbackID,
            status: .busy,
            sent: 0,
            upserted: 0,
            failedCategories: [],
            errorCode: .exportInProgress
        ))
        clock = clock.addingTimeInterval(ClientCapabilityCallbackStore.pendingLifetime)
        try store.cleanup()
        #expect(try store.outboxRecords().count == 1)
        #expect(record.callbackID != next.callbackID)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("client-capability-tests-\(UUID().uuidString)")
    }
}

struct ClientCapabilityPermissionTests {
    @Test @MainActor func allowOnceLaunchesWithoutPersistingPermission() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("client-capability-state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = UserDefaults.standard.object(forKey: AppState.healthExportPermissionKey)
        UserDefaults.standard.removeObject(forKey: AppState.healthExportPermissionKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.healthExportPermissionKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.healthExportPermissionKey) }
        }

        var openedURL: URL?
        let store = ClientCapabilityCallbackStore(rootDirectory: root)
        let state = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(),
            clientCapabilityStore: store,
            clientCapabilityURLOpener: { url in openedURL = url; return true }
        )
        let action = CarClientAction.healthExportAll(id: "health-1", reason: "Refresh sleep")
        await state.requestClientCapability(
            action,
            sessionID: "ses_original",
            carContextKey: "host|workspace",
            assistantMessageID: "msg_assistant"
        )
        #expect(state.pendingClientCapabilityRequest?.action == action)

        await state.resolveClientCapabilityPermission(allow: true)

        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(state.healthExportPermission == .ask)
        #expect(openedURL?.scheme == "healthquantification")
        #expect(try store.hasActiveRecord(for: .healthExportAll))
    }
}

struct ClientCapabilityContinuationTests {
    @Test @MainActor func callbackContinuesRecordedSessionWithoutChangingCurrentSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("client-capability-continuation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClientCapabilityCallbackStore(rootDirectory: root)
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = AppState(
            apiClient: api,
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(),
            carSpeechOutput: speech,
            clientCapabilityStore: store,
            clientCapabilityURLOpener: { _ in true }
        )
        state.isConnected = true
        state.currentSessionID = "ses_visible"
        let contextKey = "original-host|/health-workspace"
        let hostSignature = try #require(state.clientCapabilityHostSignature(for: state.currentHostProfileID))
        let record = try store.createPending(
            capability: .healthExportAll,
            hostProfileID: state.currentHostProfileID,
            hostConfigurationSignature: hostSignature,
            carContextKey: contextKey,
            sessionID: "ses_original",
            assistantMessageID: "msg_request",
            actionID: "health-1"
        )
        await api.setMessagesResult([])
        await api.setPromptStructuredResult(Self.assistantResponse(
            id: "msg_analysis",
            sessionID: record.sessionID,
            parentID: record.continuationMessageID
        ))
        let callback = ClientActionCallback(
            callbackID: record.callbackID,
            status: .success,
            sent: 12,
            upserted: 12,
            failedCategories: [],
            errorCode: nil
        )

        await state.receiveClientActionCallback(callback)

        let calls = await api.promptStructuredCalls
        #expect(calls.map(\.sessionID) == ["ses_original"])
        #expect(calls.first?.messageID == record.continuationMessageID)
        #expect(calls.first?.text.contains("\"kind\":\"client_action_result\"") == true)
        #expect(state.currentSessionID == "ses_visible")
        #expect(state.carSessionsByContext[contextKey]?.lastHandledAssistantMessageID == "msg_analysis")
        #expect(try store.outboxRecords().isEmpty)
        #expect(speech.spokenTexts.isEmpty)
    }

    private static func assistantResponse(id: String, sessionID: String, parentID: String) -> MessageWithParts {
        MessageWithParts(
            info: Message(
                id: id,
                sessionID: sessionID,
                role: "assistant",
                parentID: parentID,
                providerID: "openai",
                modelID: "gpt-5.6-sol-fast",
                model: nil,
                error: nil,
                time: .init(created: 2, completed: 3),
                finish: "stop",
                tokens: nil,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .completed,
                    speech: "The Health data is ready.",
                    confirmation: nil,
                    clientActions: []
                )
            ),
            parts: []
        )
    }
}
