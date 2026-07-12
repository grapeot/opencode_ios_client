import Foundation

protocol AIUsageQuotaClientProtocol: Sendable {
    func fetchQuotas(from endpoint: URL) async throws -> AIUsageQuotasResponse
    func refreshDashboard(from quotasEndpoint: URL) async throws
}

actor AIUsageQuotaClient: AIUsageQuotaClientProtocol {
    func fetchQuotas(from endpoint: URL) async throws -> AIUsageQuotasResponse {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageQuotaClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIUsageQuotaClientError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(AIUsageQuotasResponse.self, from: data)
    }

    func refreshDashboard(from quotasEndpoint: URL) async throws {
        guard var components = URLComponents(url: quotasEndpoint, resolvingAgainstBaseURL: false),
              components.path.hasSuffix("/api/v1/quotas") else {
            throw AIUsageQuotaClientError.invalidURL
        }
        components.path.removeLast("/api/v1/quotas".count)
        components.path += "/api/v1/display/update"
        guard let endpoint = components.url else { throw AIUsageQuotaClientError.invalidURL }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "reason": "force_button",
            "view": "7d",
            "device_id": "opencode-ios",
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIUsageQuotaClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIUsageQuotaClientError.httpError(http.statusCode)
        }
    }
}

enum AIUsageQuotaClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid AI Usage Dashboard URL"
        case .invalidResponse: return "Invalid response from AI Usage Dashboard"
        case .httpError(let status): return "AI Usage Dashboard returned HTTP \(status)"
        }
    }
}
