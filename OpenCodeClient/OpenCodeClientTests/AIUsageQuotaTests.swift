import Foundation
import Testing
@testable import OpenCodeClient

@MainActor
private final class MockAIUsageQuotaClient: AIUsageQuotaClientProtocol {
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

    func requestCount() async -> Int { endpoints.count }
    func recordedEvents() async -> [String] { events }
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

    @Test func decodesFractionalPercentages() throws {
        let data = Data(#"{"generated_at":"2026-10-08T06:23:43","quotas":[{"provider":"ollama","label":"5h","used_percentage":1.6,"remaining_percentage":98.4,"next_reset_time_ms":1791468000000,"next_reset_iso":"2026-10-08T07:00","usage":null,"remaining":null},{"provider":"cursor","label":"Models","used_percentage":9.606333333333334,"remaining_percentage":90.39366666666666,"next_reset_time_ms":null,"next_reset_iso":null,"usage":null,"remaining":null}]}"#.utf8)

        let response = try JSONDecoder().decode(AIUsageQuotasResponse.self, from: data)

        #expect(response.quotas.count == 2)
        #expect(response.quotas.first?.usedPercentage == 2)
        #expect(response.quotas.first?.remainingPercentage == 98)
        #expect(response.quotas.last?.usedPercentage == 10)
        #expect(response.quotas.last?.remainingPercentage == 90)
    }

    @Test func decodesWholeNumberPercentagesSentAsFloats() throws {
        let data = Data(#"{"generated_at":null,"quotas":[{"provider":"codex","label":"7d","used_percentage":79.0,"remaining_percentage":21.0,"next_reset_time_ms":null,"next_reset_iso":null,"usage":null,"remaining":null}]}"#.utf8)

        let response = try JSONDecoder().decode(AIUsageQuotasResponse.self, from: data)

        #expect(response.quotas.first?.usedPercentage == 79)
        #expect(response.quotas.first?.remainingPercentage == 21)
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
        let glm = ModelPreset(displayName: "GLM-5.3", providerID: "zai-coding-plan", modelID: "glm-5.3")
        let gemini = ModelPreset(displayName: "Gemini 3.7 Flash", providerID: "google", modelID: "gemini-3.7-flash")
        let grok = ModelPreset(displayName: "Grok 4.7", providerID: "xai", modelID: "grok-4.7")

        #expect(gpt.primaryQuotaKey == AIUsageQuotaKey(provider: "codex", label: "5h"))
        #expect(glm.primaryQuotaKey == AIUsageQuotaKey(provider: "glm", label: "5h"))
        #expect(gemini.primaryQuotaKey == nil)
        #expect(grok.primaryQuotaKey == AIUsageQuotaKey(provider: "grok", label: "Weekly"))
    }

    @Test func fallsBackToProviderWindowWhenPreferredLabelIsMissing() {
        let weekly = AIUsageQuota(
            provider: "grok",
            label: "Weekly",
            usedPercentage: 23,
            remainingPercentage: 77,
            nextResetTimeMs: nil,
            nextResetISO: nil,
            usage: nil,
            remaining: nil
        )
        let weeklyWindow = AIUsageQuota(
            provider: "codex",
            label: "7d",
            usedPercentage: 0,
            remainingPercentage: 100,
            nextResetTimeMs: nil,
            nextResetISO: nil,
            usage: nil,
            remaining: nil
        )
        let snapshot = AIUsageQuotaSnapshot(generatedAt: nil, fetchedAt: Date(), quotas: [weekly, weeklyWindow])

        #expect(snapshot.quota(provider: "grok", preferredLabel: "Weekly") == weekly)
        #expect(snapshot.quota(provider: "codex", preferredLabel: "5h") == weeklyWindow)
        #expect(snapshot.quota(provider: "glm", preferredLabel: "5h") == nil)
    }

    @Test @MainActor func blankEndpointMakesNoRequest() async {
        let previous = UserDefaults.standard.string(forKey: AppState.aiUsageDashboardURLKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.aiUsageDashboardURLKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.aiUsageDashboardURLKey) }
        }
        let mock = MockAIUsageQuotaClient(result: .success(.init(generatedAt: nil, quotas: [])))
        let state = makeIsolatedAppState(aiUsageQuotaClient: mock)
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
        let state = makeIsolatedAppState(aiUsageQuotaClient: mock)
        state.addModelsToShortlist(testSeedPresets)
        state.aiUsageDashboardURL = "https://usage.example.com"
        state.selectedModelIndex = 1

        await state.refreshAIUsageQuotas(force: true)

        #expect(state.selectedModelQuota == quota)
        #expect(state.aiUsageQuotaTestOK)
        #expect(await mock.requestCount() == 1)
    }

    @Test @MainActor func refreshLoadsSelectedGrokQuota() async {
        let previous = UserDefaults.standard.string(forKey: AppState.aiUsageDashboardURLKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.aiUsageDashboardURLKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.aiUsageDashboardURLKey) }
        }
        let quota = AIUsageQuota(
            provider: "grok",
            label: "Weekly",
            usedPercentage: 18,
            remainingPercentage: 82,
            nextResetTimeMs: nil,
            nextResetISO: nil,
            usage: nil,
            remaining: nil
        )
        let mock = MockAIUsageQuotaClient(result: .success(.init(generatedAt: "2026-09-26T09:00:00", quotas: [quota])))
        let state = makeIsolatedAppState(aiUsageQuotaClient: mock)
        state.addModelsToShortlist(testSeedPresets)
        state.aiUsageDashboardURL = "https://usage.example.com"
        state.selectedModelIndex = testSeedPresets.firstIndex { $0.providerID == "xai" } ?? 0

        await state.refreshAIUsageQuotas(force: true)

        #expect(state.selectedModel?.providerID == "xai")
        #expect(state.selectedModelQuota == quota)
    }

    @Test @MainActor func manualRefreshUpdatesDashboardBeforeFetchingQuotas() async {
        let previous = UserDefaults.standard.string(forKey: AppState.aiUsageDashboardURLKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: AppState.aiUsageDashboardURLKey) }
            else { UserDefaults.standard.removeObject(forKey: AppState.aiUsageDashboardURLKey) }
        }
        let mock = MockAIUsageQuotaClient(result: .success(.init(generatedAt: nil, quotas: [])))
        let state = makeIsolatedAppState(aiUsageQuotaClient: mock)
        state.aiUsageDashboardURL = "https://usage.example.com"

        await state.refreshAIUsageDashboard()

        #expect(await mock.recordedEvents() == ["refresh", "fetch"])
        #expect(!state.isRefreshingAIUsageProviders)
    }

    @Test func resetCountdownLabelUsesFloorRules() {
        let cases: [(Int64, String)] = [
            (Int64(5.16 * 86_400), "5.1d"),
            (86_400, "1.0d"),
            (86_399, "23h"),
            (13 * 3_600 + 3_000, "13h"),
            (13 * 3_600 + 1, "13h"),
            (Int64(12.5 * 3_600), "12h"),
            (3_600, "1h"),
            (3_599, "<1h"),
            (1, "<1h"),
            (0, "0h"),
            (-90, "0h"),
        ]
        for (offset, expected) in cases {
            let sample = countdownQuota(resetOffsetSeconds: offset)
            #expect(sample.resetCountdownLabel(at: countdownNow) == expected)
        }

        let fiveDay = countdownQuota(remainingPercentage: 87, resetOffsetSeconds: Int64(5.16 * 86_400))
        #expect(fiveDay.resetCountdownLabel(at: countdownNow) == "5.1d")
        #expect(countdownPillText(fiveDay) == "87% / 5.1d")

        let missingMilliseconds = countdownQuota(nextResetISO: "2026-07-12T10:54:01")
        #expect(missingMilliseconds.resetCountdownLabel(at: countdownNow) == nil)
        #expect(countdownPillText(missingMilliseconds) == "71% @ 5h")

        let dirtySeconds = countdownQuota(nextResetTimeMs: 1_783_842_841, nextResetISO: "2026-07-12T10:54:01")
        #expect(dirtySeconds.resetCountdownLabel(at: countdownNow) == nil)
    }

    @Test func resetCountdownDaySuffixStaysDottedInChineseLocale() {
        let sample = countdownQuota(remainingPercentage: 87, resetOffsetSeconds: Int64(5.16 * 86_400))
        let label = sample.resetCountdownLabel(at: countdownNow)
        #expect(label == "5.1d")
        for identifier in ["zh_CN", "zh-Hans", "zh_Hans_CN", "de_DE"] {
            let localized = String(format: "%.1fd", locale: Locale(identifier: identifier), 5.1)
            #expect(label == "5.1d")
            #expect(label?.contains(",") == false)
            if localized.contains(",") {
                #expect(label != localized)
            }
        }
    }
}

private let countdownNow = Date(timeIntervalSince1970: 1_700_000_000)
private let countdownNowMs: Int64 = 1_700_000_000_000

private func countdownQuota(
    remainingPercentage: Int = 71,
    resetOffsetSeconds: Int64? = nil,
    nextResetTimeMs: Int64? = nil,
    nextResetISO: String? = nil
) -> AIUsageQuota {
    let milliseconds: Int64?
    if let nextResetTimeMs {
        milliseconds = nextResetTimeMs
    } else if let resetOffsetSeconds {
        milliseconds = countdownNowMs + resetOffsetSeconds * 1_000
    } else {
        milliseconds = nil
    }
    return AIUsageQuota(
        provider: "codex",
        label: "5h",
        usedPercentage: 0,
        remainingPercentage: remainingPercentage,
        nextResetTimeMs: milliseconds,
        nextResetISO: nextResetISO,
        usage: nil,
        remaining: nil
    )
}

private func countdownPillText(_ quota: AIUsageQuota) -> String {
    if let countdown = quota.resetCountdownLabel(at: countdownNow) {
        return "\(quota.clampedRemainingPercentage)% / \(countdown)"
    }
    return "\(quota.clampedRemainingPercentage)% @ \(quota.label)"
}
