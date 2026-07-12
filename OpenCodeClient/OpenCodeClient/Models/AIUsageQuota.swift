import Foundation

struct AIUsageQuotasResponse: Decodable, Equatable {
    let generatedAt: String?
    let quotas: [AIUsageQuota]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case quotas
    }
}

struct AIUsageQuota: Decodable, Equatable, Identifiable {
    var id: String { "\(provider)|\(label)" }

    let provider: String
    let label: String
    let usedPercentage: Int
    let remainingPercentage: Int
    let nextResetTimeMs: Int64?
    let nextResetISO: String?
    let usage: Int?
    let remaining: Int?

    enum CodingKeys: String, CodingKey {
        case provider, label, usage, remaining
        case usedPercentage = "used_percentage"
        case remainingPercentage = "remaining_percentage"
        case nextResetTimeMs = "next_reset_time_ms"
        case nextResetISO = "next_reset_iso"
    }

    var clampedUsedPercentage: Int { min(max(usedPercentage, 0), 100) }
    var clampedRemainingPercentage: Int { min(max(remainingPercentage, 0), 100) }
    var resetDate: Date? {
        nextResetTimeMs.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
    }
}

struct AIUsageQuotaSnapshot: Equatable {
    let generatedAt: String?
    let fetchedAt: Date
    let quotas: [AIUsageQuota]

    func quota(provider: String, label: String) -> AIUsageQuota? {
        quotas.first {
            $0.provider.caseInsensitiveCompare(provider) == .orderedSame
                && $0.label.caseInsensitiveCompare(label) == .orderedSame
        }
    }
}

enum AIUsageQuotaState: Equatable {
    case idle
    case loading(previous: AIUsageQuotaSnapshot?)
    case ready(AIUsageQuotaSnapshot)
    case empty(generatedAt: String?)
    case failed(previous: AIUsageQuotaSnapshot?, message: String)

    var snapshot: AIUsageQuotaSnapshot? {
        switch self {
        case .ready(let snapshot), .loading(let snapshot?), .failed(let snapshot?, _):
            return snapshot
        case .idle, .loading(nil), .empty, .failed(nil, _):
            return nil
        }
    }
}

struct AIUsageQuotaKey: Equatable {
    let provider: String
    let label: String
}

extension ModelPreset {
    var primaryQuotaKey: AIUsageQuotaKey? {
        switch providerID {
        case "openai": return AIUsageQuotaKey(provider: "codex", label: "5h")
        case "zai-coding-plan": return AIUsageQuotaKey(provider: "glm", label: "5h")
        case "ollama-cloud": return AIUsageQuotaKey(provider: "ollama", label: "5h")
        default: return nil
        }
    }
}
