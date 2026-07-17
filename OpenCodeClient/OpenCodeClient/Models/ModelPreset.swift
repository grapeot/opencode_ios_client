//
//  ModelPreset.swift
//  OpenCodeClient
//

import Foundation

struct ModelPreset: Codable, Identifiable {
    var id: String { "\(providerID)/\(modelID)" }
    let displayName: String
    let providerID: String
    let modelID: String
    
    var shortName: String {
        switch displayName {
        case "DeepSeek V4 Flash": return "DS-Flash"
        case "DeepSeek Local": return "DS-L"
        case "DeepSeek V4 Pro": return "DS-Pro"
        case "Ollama GLM 5.2": return "OGLM-5.2"
        case "GPT-5.6 Sol Fast": return "GPT-F"
        case let name where name.contains("Gemini"): return "Gemini"
        case let name where name.contains("GPT"): return "GPT"
        default: return Self.truncated(displayName)
        }
    }

    /// Generic fallback for names not covered by the special cases above — mainly
    /// dynamically-loaded models from the server's `/config/providers` response (see
    /// `AppState.applyDynamicModelPresets`). Keeps the toolbar chip label from growing
    /// unbounded for long server-provided model names.
    private static func truncated(_ name: String, maxLength: Int = 16) -> String {
        guard name.count > maxLength else { return name }
        let cutoff = name.index(name.startIndex, offsetBy: maxLength)
        return String(name[..<cutoff]) + "…"
    }
}
