//
//  ModelPreset.swift
//  OpenCodeClient
//

import Foundation

struct ModelPreset: Codable, Identifiable, Equatable {
    var id: String { "\(providerID)/\(modelID)" }
    let displayName: String
    let providerID: String
    let modelID: String
    var customShortName: String? = nil

    var shortName: String {
        let custom = customShortName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return Self.suggestedShortName(for: displayName)
    }

    static func suggestedShortName(for displayName: String) -> String {
        switch displayName {
        case "DeepSeek V4 Flash": return "DS-Flash"
        case "DeepSeek Local": return "DS-L"
        case "Ollama GLM 5.2": return "OGLM-5.2"
        case "GPT-5.6 Terra Fast": return "GPT-TF"
        case "GPT-5.6 Luna": return "GPT-L"
        case "Grok 4.6": return "Grok"
        case "Qwen 3.8 27B": return "Qwen"
        case let name where name.contains("Gemini"): return "Gemini"
        case let name where name.contains("GPT"): return "GPT"
        default: return displayName
        }
    }
}

struct ModelShortlistItem: Codable, Identifiable, Equatable {
    var providerID: String
    var modelID: String
    var displayName: String
    var shortName: String

    var id: String { "\(providerID)/\(modelID)" }

    func asPreset() -> ModelPreset {
        ModelPreset(
            displayName: displayName,
            providerID: providerID,
            modelID: modelID,
            customShortName: shortName
        )
    }

    static func from(_ preset: ModelPreset) -> ModelShortlistItem {
        ModelShortlistItem(
            providerID: preset.providerID,
            modelID: preset.modelID,
            displayName: preset.displayName,
            shortName: preset.shortName
        )
    }
}

/// Flat row model for the model picker: provider header rows interleaved
/// with model rows, rendered inside a single List Section.
enum ModelPickerItem: Identifiable, Equatable {
    case providerHeader(String)
    case model(index: Int, preset: ModelPreset)

    var id: String {
        switch self {
        case .providerHeader(let providerID): return "header:\(providerID)"
        case .model(_, let preset): return preset.id
        }
    }
}
