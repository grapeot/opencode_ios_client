import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum UITestFixtures {
    static var shouldSkipConnectionRestore: Bool {
        hasUITestSessionTreeFixture
            || hasUITestToolCardsFixture
            || hasUITestF3ComposerFixture
            || hasUITestWebPreviewFixture
            || hasUITestWebPreviewModeFixture
            || hasUITestQuotaFixture
            || hasUITestCarModeFixture
            || hasUITestCarHistoryFixture
            || hasUITestCarDisabledFixture
            || hasUITestClientCapabilityFixture
            || hasUITestDeepLinkFixture
            || hasUITestModelShortlistFixture
    }

    static var hasUITestWebPreviewModeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_WEB_PREVIEW_MODE_FIXTURE")
    }

    static var hasUITestSessionTreeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_SESSION_TREE_FIXTURE")
    }

    static var hasUITestToolCardsFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_TOOL_CARDS_FIXTURE")
    }

    static var hasUITestF3ComposerFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_F3_TRANSCRIBING_FIXTURE")
            || ProcessInfo.processInfo.arguments.contains("UITEST_F3_RETRY_FIXTURE")
    }

    static var hasUITestWebPreviewFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_WEB_PREVIEW_FIXTURE")
    }

    static var hasUITestHostProfilesFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_HOST_PROFILES_FIXTURE")
    }

    static var hasUITestQuotaFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_QUOTA_FIXTURE")
    }

    static var hasUITestCarModeFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CAR_MODE_FIXTURE")
    }

    static var hasUITestCarHistoryFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CAR_HISTORY_FIXTURE")
    }

    static var hasUITestCarDisabledFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CAR_DISABLED_FIXTURE")
    }

    static var hasUITestClientCapabilityFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_CLIENT_CAPABILITY_FIXTURE")
    }

    static var hasUITestDeepLinkFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("UITEST_DEEP_LINK_FIXTURE")
        #else
        false
        #endif
    }

    static var hasUITestModelShortlistFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_MODEL_SHORTLIST_FIXTURE")
            || ProcessInfo.processInfo.arguments.contains("UITEST_MODEL_SHORTLIST_EMPTY_FIXTURE")
    }

    /// Which bundled fixture markdown to render in the web preview. Defaults to
    /// the HTML-cards fixture; override via WEB_PREVIEW_FIXTURE_NAME env var.
    static var webPreviewFixtureName: String {
        let env = ProcessInfo.processInfo.environment["WEB_PREVIEW_FIXTURE_NAME"]
        return (env?.isEmpty == false ? env! : "html_cards")
    }

    static func loadFixtureMarkdown(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "WebPreviewFixtures")
            ?? Bundle.main.url(forResource: name, withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "# Fixture not found: \(name)"
        }
        return text
    }

    static func makeInitialState() -> AppState {
        let state: AppState
        if hasUITestDeepLinkFixture {
            state = AppState(
                deepLinkSessionResolver: { sessionID in
                    guard sessionID == "ses_deep_link_target" else {
                        throw APIError.httpError(statusCode: 404, data: Data())
                    }
                    return deepLinkFixtureSession(
                        id: sessionID,
                        title: "Deep Link Target",
                        directory: "/tmp/deep-link-target"
                    )
                },
                deepLinkHydratesSelection: false
            )
        } else {
            state = AppState()
        }

        if hasUITestDeepLinkFixture {
            applyDeepLinkFixture(to: state)
            return state
        }

        if hasUITestCarHistoryFixture {
            applyCarHistoryFixture(to: state)
            return state
        }

        if hasUITestCarDisabledFixture {
            state.isCarModeEnabled = false
            state.selectedTab = RootTab.chat.rawValue
            return state
        }

        if hasUITestCarModeFixture {
            state.isConnected = true
            state.isCarModeEnabled = true
            state.selectedTab = RootTab.car.rawValue
            state.carLastTranscript = "Navigate to Space Needle and avoid the traffic on I-5."
            state.carLastResponse = CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "I found a faster route. It saves twelve minutes and is ready in Apple Maps.",
                confirmation: nil,
                clientActions: []
            )
            return state
        }

        if hasUITestClientCapabilityFixture {
            state.pendingClientCapabilityRequest = PendingClientCapabilityRequest(
                action: .healthExportAll(id: "health-fixture", reason: "Sync last night's sleep data before analysis"),
                hostProfileID: state.currentHostProfileID,
                sessionID: "ses_health_fixture",
                carContextKey: "fixture|health",
                assistantMessageID: "msg_health_fixture"
            )
            return state
        }

        if hasUITestQuotaFixture {
            applyQuotaFixture(to: state)
            return state
        }

        if hasUITestHostProfilesFixture {
            applyHostProfilesFixture(to: state)
            return state
        }

        if hasUITestModelShortlistFixture {
            applyModelShortlistFixture(to: state)
            return state
        }

        if hasUITestF3ComposerFixture {
            applyF3ComposerFixture(to: state)
            return state
        }

        if hasUITestToolCardsFixture {
            applyToolCardsFixture(to: state)
            return state
        }

        guard hasUITestSessionTreeFixture else { return state }

        state.isConnected = true
        state.sessions = [
            Session(
                id: "root-session",
                slug: "root-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Root Session",
                version: "1",
                time: .init(created: 0, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            ),
            Session(
                id: "child-session",
                slug: "child-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: "root-session",
                title: "Child Session",
                version: "1",
                time: .init(created: 0, updated: 1_500, archived: nil),
                share: nil,
                summary: nil
            ),
            Session(
                id: "archived-session",
                slug: "archived-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Archived Session",
                version: "1",
                time: .init(created: 0, updated: 1_200, archived: 3_000),
                share: nil,
                summary: nil
            ),
            Session(
                id: "archived-child-session",
                slug: "archived-child-session",
                projectID: "p1",
                directory: "/tmp",
                parentID: "archived-session",
                title: "Archived Child",
                version: "1",
                time: .init(created: 0, updated: 1_100, archived: 3_000),
                share: nil,
                summary: nil
            ),
        ]
        state.currentSessionID = "root-session"
        state.expandedSessionIDs = ["root-session", "archived-session"]
        return state
    }

    static func deepLinkFixtureSession(id: String, title: String, directory: String) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "deep-link-project",
            directory: directory,
            parentID: nil,
            title: title,
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
    }

    static func applyDeepLinkFixture(to state: AppState) {
        let source = deepLinkFixtureSession(
            id: "ses_deep_link_source",
            title: "Deep Link Source",
            directory: "/tmp/deep-link-source"
        )
        state.isConnected = true
        state.sessions = [source]
        state.currentSessionID = source.id
        state.selectedTab = RootTab.chat.rawValue

        let assistant = Message(
            id: "msg_deep_link_assistant",
            sessionID: source.id,
            role: "assistant",
            parentID: nil,
            providerID: "fixture",
            modelID: "fixture",
            model: nil,
            error: nil,
            time: .init(created: 1, completed: 2),
            finish: "stop",
            tokens: nil,
            cost: nil
        )
        let text = decodePart([
            "id": "part_deep_link_text",
            "messageID": assistant.id,
            "sessionID": source.id,
            "type": "text",
            "text": "[Open target session](opencode://session/ses_deep_link_target)",
        ])
        state.messages = [MessageWithParts(info: assistant, parts: [text])]
    }

    static func applyCarHistoryFixture(to state: AppState) {
        let sessionID = "car-history-session"
        state.isConnected = true
        state.selectedTab = RootTab.chat.rawValue
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp/car-history",
                parentID: nil,
                title: "Car Mode",
                version: "1",
                time: .init(created: 1, updated: 3, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        let user = Message(
            id: "car-user",
            sessionID: sessionID,
            role: "user",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 1, completed: nil),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        let assistant = Message(
            id: "car-assistant",
            sessionID: sessionID,
            role: "assistant",
            parentID: user.id,
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
        )
        let userPart = decodePart([
            "id": "car-user-text",
            "messageID": user.id,
            "sessionID": sessionID,
            "type": "text",
            "text": "Is the garage door closed?",
        ])
        state.messages = [
            MessageWithParts(info: user, parts: [userPart]),
            MessageWithParts(info: assistant, parts: []),
        ]
    }

    static func applyQuotaFixture(to state: AppState) {
        let sessionID = "quota-fixture-session"
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp/quota-fixture",
                parentID: nil,
                title: "Quota UX Review",
                version: "1",
                time: .init(created: 1_000, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        state.draftInputsBySessionID[sessionID] = ""
        state.selectedModelIndex = 6
        state.aiUsageDashboardURL = "http://usage-dashboard.local:7995"
        state.aiUsageQuotaState = .ready(.init(
            generatedAt: "2026-07-12T09:40:00",
            fetchedAt: Date(),
            quotas: [
                AIUsageQuota(provider: "codex", label: "5h", usedPercentage: 29, remainingPercentage: 71, nextResetTimeMs: 1_783_842_841_000, nextResetISO: nil, usage: nil, remaining: nil),
                AIUsageQuota(provider: "codex", label: "7d", usedPercentage: 62, remainingPercentage: 38, nextResetTimeMs: 1_783_950_000_000, nextResetISO: nil, usage: nil, remaining: nil),
                AIUsageQuota(provider: "claude", label: "5h", usedPercentage: 84, remainingPercentage: 16, nextResetTimeMs: 1_783_850_000_000, nextResetISO: nil, usage: nil, remaining: nil),
                AIUsageQuota(provider: "glm", label: "5h", usedPercentage: 8, remainingPercentage: 92, nextResetTimeMs: 1_783_860_000_000, nextResetISO: nil, usage: nil, remaining: nil),
            ]
        ))
    }

    static func applyModelShortlistFixture(to state: AppState) {
        state.isConnected = true
        state.providerDisplayNames = [
            "zai-coding-plan": "Z.AI Coding Plan",
            "google": "Google"
        ]
        state.catalogModelPresets = [
            ModelPreset(displayName: "GLM-5.3", providerID: "zai-coding-plan", modelID: "glm-5.3"),
            ModelPreset(displayName: "Gemini 3.5 Flash", providerID: "google", modelID: "gemini-3.5-flash"),
            ModelPreset(displayName: "Gemini 3.5 Flash Lite", providerID: "google", modelID: "gemini-3.5-flash-lite")
        ]
        if ProcessInfo.processInfo.arguments.contains("UITEST_MODEL_SHORTLIST_EMPTY_FIXTURE") {
            state.modelShortlist = []
        } else {
            state.modelShortlist = [
                ModelShortlistItem(
                    providerID: "zai-coding-plan",
                    modelID: "glm-5.3",
                    displayName: "GLM-5.3",
                    shortName: "GLM"
                )
            ]
        }
        state.rebuildPickerModelItems(reason: "fixture")
    }

    static func applyHostProfilesFixture(to state: AppState) {
        let local = HostProfile(
            name: "Local OpenCode",
            transport: .direct,
            serverURL: "127.0.0.1:4096",
            basicAuth: nil,
            ssh: nil,
            lastUsedAt: Date(timeIntervalSince1970: 1_000)
        )
        let ssh = HostProfile(
            name: "SSH Lab",
            transport: .sshTunnel,
            serverURL: APIClient.defaultServer,
            basicAuth: nil,
            ssh: SSHTunnelConfig(isEnabled: true, host: "gateway.example.invalid", port: 8006, username: "opencode", remotePort: 19001),
            lastUsedAt: Date(timeIntervalSince1970: 2_000)
        )
        state.hostProfiles = [local, ssh]
        state.currentHostProfileID = local.id
        state.applyCurrentHostProfileToRuntime(persistLegacy: false)
        state.selectedTab = RootTab.settings.rawValue
    }

    /// Injects a deterministic assistant turn so the UI test renders the new tool
    /// cards (file-op grid + merged "N tool calls" row) without a live server.
    /// Only active under the UITEST_TOOL_CARDS_FIXTURE launch argument.
    static func applyToolCardsFixture(to state: AppState) {
        let sessionID = "toolcards-session"
        let userMessageID = "u-toolcards"
        let assistantMessageID = "a-toolcards"

        state.isConnected = true
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp",
                parentID: nil,
                title: "Tool Cards Session",
                version: "1",
                time: .init(created: 0, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        state.expandedSessionIDs = [sessionID]

        // User message: a single text part.
        let userInfo = Message(
            id: userMessageID,
            sessionID: sessionID,
            role: "user",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 1_000, completed: 1_000),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        let userTextPart = decodePart([
            "id": "up-text",
            "messageID": userMessageID,
            "sessionID": sessionID,
            "type": "text",
            "text": "Refactor the API client and run the tests.",
        ])

        // Assistant message: resolvedModel via top-level providerID/modelID so the
        // small "providerID/modelID" footer shows.
        let assistantInfo = Message(
            id: assistantMessageID,
            sessionID: sessionID,
            role: "assistant",
            parentID: userMessageID,
            providerID: "openai",
            modelID: "gpt-5.6-sol",
            model: nil,
            error: nil,
            time: .init(created: 1_100, completed: 1_200),
            finish: "stop",
            tokens: nil,
            cost: nil
        )

        var assistantParts: [Part] = []

        // Leading text so the assistant turn reads naturally.
        assistantParts.append(decodePart([
            "id": "ap-text",
            "messageID": assistantMessageID,
            "sessionID": sessionID,
            "type": "text",
            "text": "Here are the changes I made.",
        ]))

        // File-operation parts -> render as FileCardView in the 2-column grid.
        let fileTools: [(id: String, tool: String, path: String)] = [
            ("ap-read", "read_file", "src/api/client.ts"),
            ("ap-edit", "edit_file", "src/api/types.ts"),
            ("ap-write", "write_file", "README.md"),
        ]
        for f in fileTools {
            assistantParts.append(decodePart([
                "id": f.id,
                "messageID": assistantMessageID,
                "sessionID": sessionID,
                "type": "tool",
                "tool": f.tool,
                "callID": "call-\(f.id)",
                "metadata": ["path": f.path],
                "state": [
                    "status": "completed",
                    "input": ["path": f.path],
                    "output": "ok",
                ],
            ]))
        }

        // A patch part with files -> a fourth file card.
        assistantParts.append(decodePart([
            "id": "ap-patch",
            "messageID": assistantMessageID,
            "sessionID": sessionID,
            "type": "patch",
            "files": [
                ["path": "src/api/index.ts", "additions": 12, "deletions": 3, "status": "modified"],
            ],
        ]))

        // Non-file tools -> collapse into the merged "3 tool calls" row.
        let otherTools: [(id: String, tool: String, command: String, output: String)] = [
            ("ap-bash", "bash", "npm test", "All tests passed"),
            ("ap-grep", "grep", "TODO", "3 matches"),
            ("ap-list", "list", "src/api", "client.ts\ntypes.ts\nindex.ts"),
        ]
        for t in otherTools {
            assistantParts.append(decodePart([
                "id": t.id,
                "messageID": assistantMessageID,
                "sessionID": sessionID,
                "type": "tool",
                "tool": t.tool,
                "callID": "call-\(t.id)",
                "state": [
                    "status": "completed",
                    "title": t.command,
                    "input": ["command": t.command],
                    "output": t.output,
                ],
            ]))
        }

        state.messages = [
            MessageWithParts(info: userInfo, parts: [userTextPart]),
            MessageWithParts(info: assistantInfo, parts: assistantParts),
        ]
    }

    /// Injects a deterministic busy session for F3 composer screenshots.
    /// The voice-side states are controlled by ChatTabView launch arguments.
    static func applyF3ComposerFixture(to state: AppState) {
        let sessionID = "f3-composer-session"
        state.isConnected = true
        state.sessions = [
            Session(
                id: sessionID,
                slug: sessionID,
                projectID: "p1",
                directory: "/tmp/opencode-ios-f3-fixture",
                parentID: nil,
                title: "F3 Voice Steer",
                version: "1",
                time: .init(created: 1_000, updated: 2_000, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = sessionID
        state.sessionStatuses[sessionID] = SessionStatus(type: "busy", attempt: nil, message: "Running implementation", next: nil)
    }

    /// Decode a Part from a JSON-object dictionary, mirroring how the server feeds
    /// parts through Codable (so metadata/state/path classification flows identically).
    static func decodePart(_ obj: [String: Any]) -> Part {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return try! JSONDecoder().decode(Part.self, from: data)
    }
}
