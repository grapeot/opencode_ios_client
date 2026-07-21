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
        case "GPT-5.6 Terra": return "GPT-T"
        case let name where name.contains("Gemini"): return "Gemini"
        case let name where name.contains("GPT"): return "GPT"
        default: return displayName
        }
    }
}
