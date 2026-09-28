import Foundation
import Testing
@testable import OpenCodeClient

struct AgentCatalogAndDeleteTests {
    @Test @MainActor func loadAgentsCorrectsUnknownSelection() async {
        let api = MockAPIClient()
        await api.setAgentsResult([
            AgentInfo(name: "build", description: nil, mode: "primary", hidden: false, native: true),
        ])
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.hasServerAgentCatalog = true
        state.selectedAgentName = "grok"

        await state.loadAgents()

        #expect(state.selectedAgentName == "build")
        #expect(state.selectedAgent?.name == "build")
        #expect(state.hasServerAgentCatalog)
    }

    @Test @MainActor func loadAgentsKeepsKnownSelection() async {
        let api = MockAPIClient()
        await api.setAgentsResult([
            AgentInfo(name: "build", description: nil, mode: "primary", hidden: false, native: true),
            AgentInfo(name: "plan", description: nil, mode: "primary", hidden: false, native: true),
        ])
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.hasServerAgentCatalog = true
        state.selectedAgentName = "plan"

        await state.loadAgents()

        #expect(state.selectedAgentName == "plan")
        #expect(state.selectedAgent?.name == "plan")
    }

    @Test @MainActor func loadAgentsEmptyCatalogLeavesSelection() async {
        let api = MockAPIClient()
        await api.setAgentsResult([])
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.selectedAgentName = "grok"

        await state.loadAgents()

        #expect(state.hasServerAgentCatalog)
        #expect(state.selectedAgentName == "grok")
    }

    @Test @MainActor func sendUsesCatalogNotPlaceholderName() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        state.sessions = [Self.session(id: "s1")]
        state.selectedAgentIndex = 0

        let sent = await state.sendMessage("hello")

        #expect(sent)
        #expect(await api.promptAsyncAgents == ["build"])
        #expect(state.agents.first?.name == "OpenCode-Builder")
    }

    @Test @MainActor func sendCorrectsUnknownAgentAgainstCatalog() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        state.sessions = [Self.session(id: "s1")]
        state.agents = [
            AgentInfo(name: "build", description: nil, mode: "primary", hidden: false, native: true),
        ]
        state.hasServerAgentCatalog = true
        state.selectedAgentName = "grok"

        let sent = await state.sendMessage("hello")

        #expect(sent)
        #expect(await api.promptAsyncAgents == ["build"])
        #expect(state.selectedAgentName == "build")
    }

    @Test @MainActor func sendKeepsKnownAgent() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        state.sessions = [Self.session(id: "s1")]
        state.agents = [
            AgentInfo(name: "build", description: nil, mode: "primary", hidden: false, native: true),
            AgentInfo(name: "plan", description: nil, mode: "primary", hidden: false, native: true),
        ]
        state.hasServerAgentCatalog = true
        state.selectedAgentName = "plan"
        state.selectedAgentIndex = 1

        let sent = await state.sendMessage("hello")

        #expect(sent)
        #expect(await api.promptAsyncAgents == ["plan"])
    }

    @Test @MainActor func loadMessagesRevalidatesAgainstCatalog() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        state.agents = [
            AgentInfo(name: "build", description: nil, mode: "primary", hidden: false, native: true),
        ]
        state.hasServerAgentCatalog = true
        state.selectedAgentName = "grok"

        await state.loadMessages()

        #expect(state.selectedAgentName == "build")
    }

    @Test @MainActor func loadMessagesDoesNotRewriteSelectionWhenCatalogEmpty() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        state.hasServerAgentCatalog = true
        state.agents = []
        state.selectedAgentName = "plan"

        await state.loadMessages()

        #expect(state.selectedAgentName == "plan")
    }

    @Test @MainActor func hostSwitchDropsPreviousServerAgent() {
        let state = makeIsolatedAppState()
        state.agents = [
            AgentInfo(name: "grok", description: nil, mode: "primary", hidden: false, native: true),
        ]
        state.hasServerAgentCatalog = true
        state.selectedAgentName = "grok"
        state.selectedAgentIndex = 0

        state.resetConnectionRuntimeForHostSwitch()

        #expect(state.agents.isEmpty)
        #expect(state.hasServerAgentCatalog == false)
        #expect(state.selectedAgentName == "build")
    }

    @Test func httpErrorDescriptionIncludesStatusAndBody() {
        let error = APIError.httpError(statusCode: 501, data: Data("not executable".utf8))
        #expect(error.localizedDescription.contains("501"))
        #expect(error.localizedDescription.contains("not executable"))
    }

    @Test @MainActor func deleteSessionHTTPFailureKeepsLocalRow() async {
        let api = MockAPIClient()
        await api.setDeleteSessionError(
            APIError.httpError(statusCode: 501, data: Data("session.delete unsupported".utf8))
        )
        let state = makeIsolatedAppState(apiClient: api)
        state.sessions = [Self.session(id: "s1"), Self.session(id: "s2")]
        state.currentSessionID = "s1"

        do {
            try await state.deleteSession(sessionID: "s1")
            Issue.record("expected delete to fail")
        } catch {
            #expect(error.localizedDescription.contains("501"))
            #expect(error.localizedDescription.contains("session.delete unsupported"))
        }

        #expect(state.sessions.map(\.id) == ["s1", "s2"])
        #expect(state.currentSessionID == "s1")
        #expect(await api.deletedSessionIDs.isEmpty)
    }

    private static func session(id: String) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: id,
            version: "1",
            time: .init(created: 0, updated: 1, archived: nil),
            share: nil,
            summary: nil
        )
    }
}
