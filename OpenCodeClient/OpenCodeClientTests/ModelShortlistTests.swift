import Foundation
import SwiftUI
import Testing
@testable import OpenCodeClient

struct ModelShortlistTests {

    // MARK: - Dynamic model picker

    private static func makeRegistryProvider(
        id: String,
        name: String? = nil,
        models: [(id: String, name: String?, chatCapable: Bool?)]
    ) -> ConfigProvider {
        var modelDict: [String: ProviderModel] = [:]
        for m in models {
            var caps: ProviderModelCapabilities? = nil
            if let capable = m.chatCapable {
                caps = ProviderModelCapabilities(
                    reasoning: nil,
                    toolCall: nil,
                    attachment: nil,
                    input: nil,
                    output: ProviderModelIO(text: capable, audio: nil, image: nil, video: nil, pdf: nil)
                )
            }
            modelDict[m.id] = ProviderModel(id: m.id, name: m.name, providerID: id, limit: nil, capabilities: caps)
        }
        return ConfigProvider(id: id, name: name, models: modelDict)
    }

    @MainActor
    private static func isolatedShortlistState() -> AppState {
        let defaults = UserDefaults(suiteName: "opencode.tests.shortlist.\(UUID().uuidString)")!
        return AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(),
            userDefaults: defaults
        )
    }

    @Test @MainActor func dynamicPickerUsesConnectedProvidersAndFiltersNonChatModels() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        let registry = ProviderRegistryResponse(
            providers: [
                // Connected custom Ollama provider (issue #144 scenario):
                // keyless local endpoint, models must show up.
                Self.makeRegistryProvider(
                    id: "ollama",
                    name: "Ollama (local)",
                    models: [
                        ("qwen3-vl:8b", "Qwen3 VL 8B", nil),
                        ("llama3:latest", nil, nil)
                    ]
                ),
                // Connected provider with a chat model + a TTS-only model.
                Self.makeRegistryProvider(
                    id: "google",
                    name: "Google",
                    models: [
                        ("gemini-3.7-flash", "Gemini 3.7 Flash", true),
                        ("gemini-3.1-flash-tts-preview", "Gemini TTS", false)
                    ]
                ),
                // NOT connected: must be excluded entirely.
                Self.makeRegistryProvider(
                    id: "openrouter",
                    name: "OpenRouter",
                    models: [("some-model", "Some Model", true)]
                )
            ],
            connectedProviderIDs: ["ollama", "google"]
        )

        state.rebuildDynamicModelPresets(from: registry)

        let ids = state.dynamicModelPresets.map(\.id)
        #expect(ids.contains("ollama/qwen3-vl:8b"))
        #expect(ids.contains("ollama/llama3:latest"))
        #expect(ids.contains("google/gemini-3.7-flash"))
        // TTS-only model filtered out by capability.
        #expect(!ids.contains("google/gemini-3.1-flash-tts-preview"))
        // Disconnected provider excluded.
        #expect(!ids.contains("openrouter/some-model"))
        // Provider display names captured for grouping.
        #expect(state.providerDisplayNames["ollama"] == "Ollama (local)")
        // Display name falls back to the model id when server has none.
        #expect(state.dynamicModelPresets.first(where: { $0.id == "ollama/llama3:latest" })?.displayName == "llama3:latest")
    }

    @Test @MainActor func dynamicPickerPrefersCuratedOrderThenSortsByName() {
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        let registry = ProviderRegistryResponse(
            providers: [
                Self.makeRegistryProvider(id: "xai", name: "xAI", models: [("grok-4.6", "Grok 4.6", true)]),
                Self.makeRegistryProvider(id: "zai-coding-plan", name: "ZAI", models: [("glm-5.3", "GLM-5.3", true)]),
                Self.makeRegistryProvider(id: "aaa", name: "AAA", models: [("zzz-model", "ZZZ", true)])
            ],
            connectedProviderIDs: ["xai", "zai-coding-plan", "aaa"]
        )

        state.rebuildDynamicModelPresets(from: registry)

        #expect(state.catalogModelPresets.map(\.id) == [
            "aaa/zzz-model",
            "xai/grok-4.6",
            "zai-coding-plan/glm-5.3"
        ])
    }

    @Test @MainActor func dynamicPickerReanchorsSelectionAndKeepsSessionModel() {
        let state = Self.isolatedShortlistState()
        state.currentSessionID = "s1"
        state.selectedModelIDBySessionID["s1"] = "ollama/qwen3-vl:8b"
        let registry = ProviderRegistryResponse(
            providers: [
                Self.makeRegistryProvider(
                    id: "ollama",
                    name: "Ollama (local)",
                    models: [("qwen3-vl:8b", "Qwen3 VL 8B", true), ("llama3:latest", nil, true)]
                )
            ],
            connectedProviderIDs: ["ollama"]
        )

        state.addModelsToShortlist([
            ModelPreset(displayName: "Qwen3 VL 8B", providerID: "ollama", modelID: "qwen3-vl:8b")
        ])
        state.rebuildDynamicModelPresets(from: registry)

        #expect(state.selectedModel?.id == "ollama/qwen3-vl:8b")
        #expect(state.pickerModelPresets.map(\.id).contains("ollama/qwen3-vl:8b"))
    }

    @Test @MainActor func pickerUsesShortlistNotCatalogOrPresets() {
        let state = Self.isolatedShortlistState()
        #expect(state.catalogModelPresets.isEmpty)
        #expect(state.pickerModelPresets.isEmpty)
        state.addModelsToShortlist([
            ModelPreset(displayName: "GLM-5.3", providerID: "zai-coding-plan", modelID: "glm-5.3")
        ])
        #expect(state.pickerModelPresets.map(\.id) == ["zai-coding-plan/glm-5.3"])
    }

    @Test @MainActor func shortlistAddIsDedupedAndRemoveUpdatesPicker() {
        let state = Self.isolatedShortlistState()
        let glm = ModelPreset(displayName: "GLM-5.3", providerID: "zai-coding-plan", modelID: "glm-5.3")
        let flash = ModelPreset(displayName: "Gemini 3.5 Flash", providerID: "google", modelID: "gemini-3.5-flash")
        state.addModelsToShortlist([glm, flash, glm])
        #expect(state.modelShortlist.map(\.id) == [
            "zai-coding-plan/glm-5.3",
            "google/gemini-3.5-flash"
        ])
        state.removeShortlistItem(id: "google/gemini-3.5-flash")
        #expect(state.pickerModelPresets.map(\.id) == ["zai-coding-plan/glm-5.3"])
    }

    @Test @MainActor func shortlistShortNameOverrideAndEmptyFallback() {
        let state = Self.isolatedShortlistState()
        state.addModelsToShortlist([
            ModelPreset(displayName: "Gemini 3.5 Flash", providerID: "google", modelID: "gemini-3.5-flash")
        ])
        #expect(state.selectedModel?.shortName == "Gemini")
        state.updateShortlistShortName(id: "google/gemini-3.5-flash", shortName: "G35")
        #expect(state.pickerModelPresets.first?.shortName == "G35")
        state.updateShortlistShortName(id: "google/gemini-3.5-flash", shortName: "   ")
        #expect(state.pickerModelPresets.first?.shortName == "Gemini")
    }

    @Test @MainActor func catalogRefreshUpdatesShortlistDisplayNames() {
        let state = Self.isolatedShortlistState()
        state.addModelsToShortlist([
            ModelPreset(displayName: "Old Name", providerID: "google", modelID: "gemini-3.5-flash")
        ])
        let registry = ProviderRegistryResponse(
            providers: [
                Self.makeRegistryProvider(
                    id: "google",
                    name: "Google",
                    models: [("gemini-3.5-flash", "Gemini 3.5 Flash", true)]
                )
            ],
            connectedProviderIDs: ["google"]
        )
        state.rebuildDynamicModelPresets(from: registry)
        #expect(state.modelShortlist.first?.displayName == "Gemini 3.5 Flash")
        #expect(state.catalogModelPresets.map(\.id) == ["google/gemini-3.5-flash"])
    }

    @Test @MainActor func shortlistReorderMatchesPickerOrder() {
        let state = Self.isolatedShortlistState()
        state.addModelsToShortlist([
            ModelPreset(displayName: "GLM-5.3", providerID: "zai-coding-plan", modelID: "glm-5.3"),
            ModelPreset(displayName: "Gemini 3.5 Flash", providerID: "google", modelID: "gemini-3.5-flash"),
            ModelPreset(displayName: "Grok 4.6", providerID: "xai", modelID: "grok-4.6")
        ])
        state.moveShortlist(from: IndexSet(integer: 2), to: 0)
        #expect(state.modelShortlist.map(\.id) == [
            "xai/grok-4.6",
            "zai-coding-plan/glm-5.3",
            "google/gemini-3.5-flash"
        ])
        #expect(state.pickerModelPresets.map(\.id) == state.modelShortlist.map(\.id))
        state.rebuildPickerModelItems(reason: "test")
        let pickerIDs = state.pickerModelItems.compactMap { item -> String? in
            if case .model(_, let preset) = item { return preset.id }
            return nil
        }
        #expect(pickerIDs == state.modelShortlist.map(\.id))
    }

    @Test @MainActor func revealModelShortlistJumpsToSettingsFocus() {
        let state = Self.isolatedShortlistState()
        state.selectedTab = RootTab.chat.rawValue
        state.revealModelShortlistInSettings()
        #expect(state.selectedTab == RootTab.settings.rawValue)
        #expect(state.settingsFocus == .modelShortlist)
    }

    @Test @MainActor func applySavedModelAddsCatalogEntryToShortlist() {
        let state = Self.isolatedShortlistState()
        state.currentSessionID = "s1"
        state.selectedModelIDBySessionID["s1"] = "google/gemini-3.5-flash"
        state.rebuildDynamicModelPresets(from: ProviderRegistryResponse(
            providers: [
                Self.makeRegistryProvider(
                    id: "google",
                    name: "Google",
                    models: [("gemini-3.5-flash", "Gemini 3.5 Flash", true)]
                )
            ],
            connectedProviderIDs: ["google"]
        ))
        #expect(state.modelShortlist.isEmpty)
        state.applySavedModelForCurrentSession()
        #expect(state.pickerModelPresets.map(\.id) == ["google/gemini-3.5-flash"])
        #expect(state.selectedModel?.id == "google/gemini-3.5-flash")
    }

    @Test @MainActor func syncModelFromMessageHistoryAddsAdHocEntryForUnknownModel() async {
        let apiClient = MockAPIClient()
        UserDefaults.standard.removeObject(forKey: AppState.modelShortlistKey)
        let state = AppState(apiClient: apiClient, sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
        if !state.modelShortlist.isEmpty { state.modelShortlist = [] }
        state.currentSessionID = "s1"
        // Session was created elsewhere with a model not in any picker list,
        // but the provider config index knows its display name.
        state.providerModelsIndex["ollama/orcarouter/Qwen3.8-27B-Uncensored:latest"] =
            ProviderModel(id: "orcarouter/Qwen3.8-27B-Uncensored:latest", name: "Qwen3.8 27B Uncensored", providerID: "ollama", limit: nil)

        let info = Message(
            id: "m1",
            sessionID: "s1",
            role: "assistant",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: Message.ModelInfo(providerID: "ollama", modelID: "orcarouter/Qwen3.8-27B-Uncensored:latest"),
            error: nil,
            time: Message.TimeInfo(created: 1, completed: 1),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        state.messages = [MessageWithParts(info: info, parts: [])]

        state.syncModelFromMessageHistory()

        // Toolbar now reflects the session's real model via an ad-hoc entry.
        #expect(state.selectedModel?.id == "ollama/orcarouter/Qwen3.8-27B-Uncensored:latest")
        #expect(state.selectedModel?.displayName == "Qwen3.8 27B Uncensored")
        #expect(state.selectedModelIDBySessionID["s1"] == "ollama/orcarouter/Qwen3.8-27B-Uncensored:latest")
    }
}
