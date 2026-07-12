import Foundation
import Testing
@testable import OpenCodeClient

private actor MockAIUsageQuotaClient: AIUsageQuotaClientProtocol {
    let result: Result<AIUsageQuotasResponse, Error>
    private(set) var endpoints: [URL] = []
    private(set) var events: [String] = []

    init(result: Result<AIUsageQuotasResponse, Error>) {
        self.result = result
    }

    func fetchQuotas(from endpoint: URL) async throws -> AIUsageQuotasResponse {
        endpoints.append(endpoint)
        events.append("fetch")
        return try result.get()
    }

    func refreshDashboard(from quotasEndpoint: URL) async throws {
        events.append("refresh")
    }

    func requestCount() -> Int { endpoints.count }
    func recordedEvents() -> [String] { events }
}

@Suite(.serialized)
struct AIUsageQuotaTests {
    @Test func decodesQuotaContract() throws {
        let data = Data(#"{"generated_at":"2026-07-12T09:00:00","quotas":[{"provider":"codex","label":"5h","used_percentage":29,"remaining_percentage":71,"next_reset_time_ms":1783842841000,"next_reset_iso":"2026-07-12T10:54:01","usage":null,"remaining":null}]}"#.utf8)

        let response = try JSONDecoder().decode(AIUsageQuotasResponse.self, from: data)

        #expect(response.generatedAt == "2026-07-12T09:00:00")
        #expect(response.quotas.first?.provider == "codex")
        #expect(response.quotas.first?.clampedRemainingPercentage == 71)
        #expect(response.quotas.first?.resetDate != nil)
    }

    @Test func normalizesBaseAndFullEndpointURLs() {
        #expect(AppState.aiUsageQuotaEndpointURL("192.168.1.20:7995")?.absoluteString == "http://192.168.1.20:7995/api/v1/quotas")
        #expect(AppState.aiUsageQuotaEndpointURL("https://usage.example.com/api/v1/quotas")?.absoluteString == "https://usage.example.com/api/v1/quotas")
        #expect(AppState.aiUsageQuotaEndpointURL("https://usage.example.com/")?.absoluteString == "https://usage.example.com/api/v1/quotas")
        #expect(AppState.aiUsageQuotaEndpointURL("http://usage.example.com") == nil)
        #expect(AppState.aiUsageQuotaEndpointURL("  ") == nil)
    }

    @Test func mapsSupportedModelsToQuotaProviders() {
        let gpt = ModelPreset(displayName: "GPT-5.6 Sol", providerID: "openai", modelID: "gpt-5.6-sol")
        let glm = ModelPreset(displayName: "GLM-5.2", providerID: "zai-coding-plan", modelID: "glm-5.2")
        let gemini = ModelPreset(displayName: "Gemini 3.5 Flash", providerID: "google", modelID: "gemini-3.5-flash")

        #expect(gpt.primaryQuotaKey == AIUsageQuotaKey(provider: "codex", label: "5h"))
        #expect(glm.primaryQuotaKey == AIUsageQuotaKey(provider: "glm", label: "5h"))
        #expect(gemini.primaryQuotaKey == nil)
    }

    @Test @MainActor func blankEndpointMakesNoRequest() async {
        let previous = UserDefaults.standard.string(forKey: AppState.aiUsageDashboardURLKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.aiUsageDashboardURLKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.aiUsageDashboardURLKey) }
        }
        let mock = MockAIUsageQuotaClient(result: .success(.init(generatedAt: nil, quotas: [])))
        let state = AppState(aiUsageQuotaClient: mock)
        state.aiUsageDashboardURL = ""

        await state.refreshAIUsageQuotas(force: true)

        #expect(await mock.requestCount() == 0)
        #expect(state.aiUsageQuotaState == .idle)
    }

    @Test @MainActor func refreshLoadsSelectedGPTQuota() async {
        let previous = UserDefaults.standard.string(forKey: AppState.aiUsageDashboardURLKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.aiUsageDashboardURLKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.aiUsageDashboardURLKey) }
        }
        let quota = AIUsageQuota(
            provider: "codex",
            label: "5h",
            usedPercentage: 29,
            remainingPercentage: 71,
            nextResetTimeMs: nil,
            nextResetISO: nil,
            usage: nil,
            remaining: nil
        )
        let mock = MockAIUsageQuotaClient(result: .success(.init(generatedAt: "2026-07-12T09:00:00", quotas: [quota])))
        let state = AppState(aiUsageQuotaClient: mock)
        state.aiUsageDashboardURL = "https://usage.example.com"
        state.selectedModelIndex = 1

        await state.refreshAIUsageQuotas(force: true)

        #expect(state.selectedModelQuota == quota)
        #expect(state.aiUsageQuotaTestOK)
        #expect(await mock.requestCount() == 1)
    }

    @Test @MainActor func manualRefreshUpdatesDashboardBeforeFetchingQuotas() async {
        let previous = UserDefaults.standard.string(forKey: AppState.aiUsageDashboardURLKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.aiUsageDashboardURLKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.aiUsageDashboardURLKey) }
        }
        let mock = MockAIUsageQuotaClient(result: .success(.init(generatedAt: nil, quotas: [])))
        let state = AppState(aiUsageQuotaClient: mock)
        state.aiUsageDashboardURL = "https://usage.example.com"

        await state.refreshAIUsageDashboard()

        #expect(await mock.recordedEvents() == ["refresh", "fetch"])
        #expect(!state.isRefreshingAIUsageProviders)
    }
}
