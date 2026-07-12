import Foundation

extension AppState {
    nonisolated static func aiUsageQuotaEndpointURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let corrected = Self.correctMalformedServerURL(trimmed) ?? trimmed
        let info = Self.serverURLInfo(corrected)
        guard info.isAllowed, let normalized = info.normalized else { return nil }
        let normalizedEndpoint = normalized
        guard var components = URLComponents(string: normalizedEndpoint), components.host != nil else { return nil }

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath != "api/v1/quotas" {
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = components.path.isEmpty ? "/api/v1/quotas" : "/\(components.path)/api/v1/quotas"
        }
        return components.url
    }

    var isAIUsageQuotaConfigured: Bool {
        Self.aiUsageQuotaEndpointURL(aiUsageDashboardURL) != nil
    }

    var selectedModelQuota: AIUsageQuota? {
        guard let key = selectedModel?.primaryQuotaKey else { return nil }
        return aiUsageQuotaState.snapshot?.quota(provider: key.provider, label: key.label)
    }

    var isSelectedModelQuotaStale: Bool {
        guard let snapshot = aiUsageQuotaState.snapshot else { return false }
        if case .failed = aiUsageQuotaState { return true }
        return Date().timeIntervalSince(snapshot.fetchedAt) > 300
    }

    func refreshAIUsageQuotas(force: Bool = false) async {
        guard let endpoint = Self.aiUsageQuotaEndpointURL(aiUsageDashboardURL) else {
            aiUsageQuotaState = .idle
            return
        }

        if !force,
           let snapshot = aiUsageQuotaState.snapshot,
           Date().timeIntervalSince(snapshot.fetchedAt) < 60 {
            return
        }

        let previous = aiUsageQuotaState.snapshot
        aiUsageQuotaState = .loading(previous: previous)
        do {
            let response = try await aiUsageQuotaClient.fetchQuotas(from: endpoint)
            if response.quotas.isEmpty {
                aiUsageQuotaState = .empty(generatedAt: response.generatedAt)
            } else {
                aiUsageQuotaState = .ready(.init(
                    generatedAt: response.generatedAt,
                    fetchedAt: Date(),
                    quotas: response.quotas
                ))
            }
            aiUsageQuotaTestOK = true
            aiUsageQuotaError = nil
        } catch {
            let message = error.localizedDescription
            aiUsageQuotaState = .failed(previous: previous, message: message)
            aiUsageQuotaTestOK = false
            aiUsageQuotaError = message
        }
    }

    func refreshAIUsageDashboard() async {
        guard let endpoint = Self.aiUsageQuotaEndpointURL(aiUsageDashboardURL) else {
            aiUsageQuotaState = .idle
            return
        }

        let previous = aiUsageQuotaState.snapshot
        isRefreshingAIUsageProviders = true
        aiUsageQuotaState = .loading(previous: previous)
        defer { isRefreshingAIUsageProviders = false }

        do {
            try await aiUsageQuotaClient.refreshDashboard(from: endpoint)
            let response = try await aiUsageQuotaClient.fetchQuotas(from: endpoint)
            if response.quotas.isEmpty {
                aiUsageQuotaState = .empty(generatedAt: response.generatedAt)
            } else {
                aiUsageQuotaState = .ready(.init(
                    generatedAt: response.generatedAt,
                    fetchedAt: Date(),
                    quotas: response.quotas
                ))
            }
            aiUsageQuotaTestOK = true
            aiUsageQuotaError = nil
        } catch {
            let message = error.localizedDescription
            aiUsageQuotaState = .failed(previous: previous, message: message)
            aiUsageQuotaTestOK = false
            aiUsageQuotaError = message
        }
    }
}
