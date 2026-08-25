import Foundation
import os

/// Model + agent selection bookkeeping. Per-session model is persisted
/// via `selectedModelIDBySessionID` (see `AppState+Drafts.swift` for the
/// persist call); agents are session-agnostic. Includes the
/// `canonicalModelPresetID` map that ages old saved IDs forward to the
/// current preset slot.
extension AppState {
    func setSelectedModelIndex(_ index: Int) {
        guard pickerModelPresets.indices.contains(index) else { return }
        selectedModelIndex = index
        guard let sessionID = currentSessionID else { return }
        selectedModelIDBySessionID[sessionID] = pickerModelPresets[index].id
        persistSelectedModelMap()
    }

    func canonicalModelPresetID(for savedID: String) -> String {
        switch savedID {
        case "zai-coding-plan/glm-5.3", "zai-coding-plan/glm-5.2", "zai-coding-plan/glm-5.1", "zai-coding-plan/glm-5-turbo":
            return "zai-coding-plan/glm-5.3"
        case "openai/gpt-5.4", "openai/gpt-5.5", "openai/gpt-5.6-sol-pro", "openai/gpt-5.6-sol-fast":
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
        if let idx = pickerModelPresets.firstIndex(where: { $0.id == canonicalSaved }) {
            selectedModelIndex = idx
            return
        }
        if let catalog = catalogModelPresets.first(where: { $0.id == canonicalSaved }) {
            addModelsToShortlist([catalog])
            if let idx = pickerModelPresets.firstIndex(where: { $0.id == canonicalSaved }) {
                selectedModelIndex = idx
            }
        }
    }

    func syncModelFromMessageHistory() {
        guard let sessionID = currentSessionID else { return }

        guard let info = messages.reversed().compactMap({ $0.info.resolvedModel }).first else { return }
        let modelID = "\(info.providerID)/\(info.modelID)"

        if let idx = pickerModelPresets.firstIndex(where: { $0.id == modelID }) {
            selectedModelIndex = idx
            selectedModelIDBySessionID[sessionID] = pickerModelPresets[idx].id
            persistSelectedModelMap()
            return
        }
        // The session used a model outside the picker (e.g. provider not
        // connected anymore, or a dynamic model while the picker fell back
        // to presets). Surface it as an explicit ad-hoc entry so the
        // toolbar still shows what the session is actually running.
        if pickerModelPresets.firstIndex(where: { $0.id == modelID }) == nil {
            let name = providerModelsIndex[modelID]?.name ?? info.modelID
            addModelsToShortlist([
                ModelPreset(displayName: name, providerID: info.providerID, modelID: info.modelID)
            ])
            if let idx = pickerModelPresets.firstIndex(where: { $0.id == modelID }) {
                selectedModelIndex = idx
                selectedModelIDBySessionID[sessionID] = modelID
                persistSelectedModelMap()
            }
            return
        }
        Self.logger.warning("syncModelFromMessageHistory: model \(info.providerID, privacy: .public)/\(info.modelID, privacy: .public) not in picker, keeping current selection")
    }
}
