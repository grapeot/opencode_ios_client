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
}
