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

    init(
        provider: String,
        label: String,
        usedPercentage: Int,
        remainingPercentage: Int,
        nextResetTimeMs: Int64?,
        nextResetISO: String?,
        usage: Int?,
        remaining: Int?
    ) {
        self.provider = provider
        self.label = label
        self.usedPercentage = usedPercentage
        self.remainingPercentage = remainingPercentage
        self.nextResetTimeMs = nextResetTimeMs
        self.nextResetISO = nextResetISO
        self.usage = usage
        self.remaining = remaining
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        label = try container.decode(String.self, forKey: .label)
        usedPercentage = try container.decodeRoundedPercentage(forKey: .usedPercentage)
        remainingPercentage = try container.decodeRoundedPercentage(forKey: .remainingPercentage)
        nextResetTimeMs = try container.decodeIfPresent(Int64.self, forKey: .nextResetTimeMs)
        nextResetISO = try container.decodeIfPresent(String.self, forKey: .nextResetISO)
        usage = try container.decodeIfPresent(Int.self, forKey: .usage)
        remaining = try container.decodeIfPresent(Int.self, forKey: .remaining)
    }

    var clampedUsedPercentage: Int { min(max(usedPercentage, 0), 100) }
    var clampedRemainingPercentage: Int { min(max(remainingPercentage, 0), 100) }
    var resetDate: Date? {
        nextResetTimeMs.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
    }

    func resetCountdownLabel(at now: Date) -> String? {
        guard let nextResetTimeMs, nextResetTimeMs >= 1_000_000_000_000 else { return nil }
        let nowMs = Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        let remainingMs = nextResetTimeMs - nowMs
        if remainingMs <= 0 { return "0h" }
        if remainingMs < 3_600_000 { return "<1h" }
        if remainingMs < 86_400_000 {
            return "\(remainingMs / 3_600_000)h"
        }
        let tenths = remainingMs / 8_640_000
        return "\(tenths / 10).\(tenths % 10)d"
    }
}

private extension KeyedDecodingContainer {
    func decodeRoundedPercentage(forKey key: Key) throws -> Int {
        let value = try decode(Double.self, forKey: key)
        guard value.isFinite, let rounded = Int(exactly: value.rounded()) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "percentage value \(value) is out of range"
            )
        }
        return rounded
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

    func quota(provider: String, preferredLabel: String) -> AIUsageQuota? {
        if let exact = quota(provider: provider, label: preferredLabel) {
            return exact
        }
        let matches = quotas.filter { $0.provider.caseInsensitiveCompare(provider) == .orderedSame }
        for label in ["5h", "7d", "Weekly"] {
            if let found = matches.first(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
                return found
            }
        }
        return matches.min { $0.label < $1.label }
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
        case "xai": return AIUsageQuotaKey(provider: "grok", label: "Weekly")
        default: return nil
        }
    }
}
