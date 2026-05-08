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
        case "DeepSeek V4 Pro": return "DS-Pro"
        case let name where name.contains("Gemini"): return "Gemini"
        case let name where name.contains("GPT"): return "GPT"
        default: return displayName
        }
    }
}
