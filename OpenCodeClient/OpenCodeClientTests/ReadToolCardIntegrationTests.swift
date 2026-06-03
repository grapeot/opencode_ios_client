//
//  ReadToolCardIntegrationTests.swift
//  OpenCodeClientTests
//
//  Tier 3 live integration test: real OpenCode server -> APIClient decode ->
//  ToolCardClassifier read-card contract. Opt-in only; default test runs return
//  immediately so CI/local unit tests do not require a server or credentials.
//

import Foundation
import Testing
@testable import OpenCodeClient

struct ReadToolCardIntegrationTests {
    @Test func readToolCallFromRealServerClassifiesAsReadCard() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["OPENCODE_INTEGRATION_TESTS"] == "1" else { return }
        guard let serverURL = env.nonEmpty("OPENCODE_SERVER_URL") else { return }
        guard let agent = env.nonEmpty("OPENCODE_AGENT") else { return }

        let model = makeModelInfo(environment: env)
        let client = APIClient(
            baseURL: serverURL,
            username: env.nonEmpty("OPENCODE_USERNAME"),
            password: env.nonEmpty("OPENCODE_PASSWORD")
        )

        let health = try await client.health()
        #expect(health.healthy)

        var createdSessionID: String?
        do {
            let session = try await client.createSession(title: "ios-tier3-read-card")
            createdSessionID = session.id

            try await client.promptAsync(
                sessionID: session.id,
                text: "Read the file AGENTS.md and reply with only its first line. Do not create, edit, or write any file.",
                agent: agent,
                model: model
            )

            let messages = try await pollForReadToolPart(client: client, sessionID: session.id)
            let readParts = messages.flatMap(\.parts).filter(isReadToolPart)

            #expect(readParts.isEmpty == false)
            #expect(readParts.contains { part in
                !part.filePathsForNavigation.isEmpty || (part.toolOutput?.contains("<type>file</type>") == true)
            })

            try? await client.deleteSession(sessionID: session.id)
            createdSessionID = nil
        } catch {
            if let createdSessionID {
                try? await client.deleteSession(sessionID: createdSessionID)
            }
            throw error
        }
    }

    private func pollForReadToolPart(
        client: APIClient,
        sessionID: String,
        timeoutSeconds: TimeInterval = 90,
        intervalSeconds: UInt64 = 2
    ) async throws -> [MessageWithParts] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var latest: [MessageWithParts] = []

        while Date() < deadline {
            latest = try await client.messages(sessionID: sessionID)
            if latest.flatMap(\.parts).contains(where: isReadToolPart) {
                return latest
            }
            try await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
        }

        return latest
    }

    private func isReadToolPart(_ part: Part) -> Bool {
        guard part.isTool, let tool = part.tool?.lowercased() else { return false }
        return ToolCardClassifier.readToolPrefixes.contains { tool.hasPrefix($0) }
    }

    private func makeModelInfo(environment env: [String: String]) -> Message.ModelInfo? {
        guard let providerID = env.nonEmpty("OPENCODE_MODEL_PROVIDER"),
              let modelID = env.nonEmpty("OPENCODE_MODEL_ID") else {
            return nil
        }
        return Message.ModelInfo(providerID: providerID, modelID: modelID)
    }
}

private extension Dictionary where Key == String, Value == String {
    func nonEmpty(_ key: String) -> String? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
