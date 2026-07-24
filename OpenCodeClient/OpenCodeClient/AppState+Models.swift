import Foundation
import os

/// Model + agent selection bookkeeping. Per-session model is persisted
/// via `selectedModelIDBySessionID` (see `AppState+Drafts.swift` for the
/// persist call); agents are session-agnostic. Includes the
/// `canonicalModelPresetID` map that ages old saved IDs forward to the
/// current preset slot.
extension AppState {
    func setSelectedModelIndex(_ index: Int) {
        guard modelPresets.indices.contains(index) else { return }
        selectedModelIndex = index
        guard let sessionID = currentSessionID else { return }
        selectedModelIDBySessionID[sessionID] = modelPresets[index].id
        persistSelectedModelMap()
    }

    func canonicalModelPresetID(for savedID: String) -> String {
        switch savedID {
        case "zai-coding-plan/glm-5.2", "zai-coding-plan/glm-5.1", "zai-coding-plan/glm-5-turbo":
            return "zai-coding-plan/glm-5.2"
        case "openai/gpt-5.4", "openai/gpt-5.5", "openai/gpt-5.6-sol-pro":
            return "openai/gpt-5.6-sol"
        case "ollama-cloud/kimi-k2.6":
            return "ollama-cloud/glm-5.2"
        default:
            return savedID
        }
    }

    func setSelectedAgentIndex(_ index: Int) {
        let visibleAgents = agents.filter { $0.isVisible }
        guard visibleAgents.indices.contains(index) else { return }
        selectedAgentIndex = index
    }

    func applySavedModelForCurrentSession() {
        guard let sessionID = currentSessionID else { return }
        guard let saved = selectedModelIDBySessionID[sessionID] else { return }
        let canonicalSaved = canonicalModelPresetID(for: saved)
        if canonicalSaved != saved {
            selectedModelIDBySessionID[sessionID] = canonicalSaved
            persistSelectedModelMap()
        }
        guard let idx = modelPresets.firstIndex(where: { $0.id == canonicalSaved }) else { return }
        selectedModelIndex = idx
    }

    func syncModelFromMessageHistory() {
        guard let sessionID = currentSessionID else { return }

        guard let info = messages.reversed().compactMap({ $0.info.resolvedModel }).first else { return }
        let canonicalModelID = canonicalModelPresetID(for: "\(info.providerID)/\(info.modelID)")
        guard let idx = modelPresets.firstIndex(where: { $0.id == canonicalModelID }) else {
            Self.logger.warning("syncModelFromMessageHistory: model \(info.providerID, privacy: .public)/\(info.modelID, privacy: .public) not in presets, keeping current selection")
            return
        }

        selectedModelIndex = idx
        selectedModelIDBySessionID[sessionID] = modelPresets[idx].id
        persistSelectedModelMap()
    }

    /// Groups `modelPresets` by provider, in provider-first-appearance order, for the model
    /// picker sheet. Needed once the list is populated from the live server (see
    /// `applyDynamicModelPresets`): multiple providers commonly serve identically-named models
    /// (e.g. a "Claude Sonnet 5" available via both `anthropic` and `openrouter`), and a flat
    /// list makes those indistinguishable while scrolling. Falls back to the raw provider ID as
    /// the group label when `providersResponse` hasn't loaded (or failed to load) yet.
    var groupedModelPresetIndices: [(providerID: String, providerName: String, indices: [Int])] {
        var order: [String] = []
        var buckets: [String: [Int]] = [:]
        for (index, preset) in modelPresets.enumerated() {
            if buckets[preset.providerID] == nil {
                order.append(preset.providerID)
                buckets[preset.providerID] = []
            }
            buckets[preset.providerID]?.append(index)
        }
        let providerNames = Dictionary(
            uniqueKeysWithValues: (providersResponse?.providers ?? []).map { ($0.id, $0.name ?? $0.id) }
        )
        return order.map { providerID in
            (providerID: providerID, providerName: providerNames[providerID] ?? providerID, indices: buckets[providerID] ?? [])
        }
    }
}
