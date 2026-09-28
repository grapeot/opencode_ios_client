//
//  AgentInfo.swift
//  OpenCodeClient
//

import Foundation

/// Represents an agent from the OpenCode server.
/// Used for agent selection in the Chat toolbar.
struct AgentInfo: Codable, Identifiable, Hashable {
    var id: String { name }
    
    let name: String              // Agent name, e.g. "Sisyphus (Ultraworker)"
    let description: String?      // Human-readable description
    let mode: String?             // "primary" or "subagent"
    let hidden: Bool?             // If true, should not be shown in UI
    let native: Bool?             // If true, it's a built-in agent
    
    /// Short display name for UI (first word before space or parenthesis)
    var shortName: String {
        // Extract first word or name before parenthesis
        if let parenIndex = name.firstIndex(of: "(") {
            return String(name[..<parenIndex]).trimmingCharacters(in: .whitespaces)
        }
        if let spaceIndex = name.firstIndex(of: " ") {
            return String(name[..<spaceIndex])
        }
        return name
    }
    
    /// Whether this agent should be shown in the UI selector
    /// Filters out hidden agents and subagents (only primary/all modes shown)
    var isVisible: Bool {
        guard hidden != true else { return false }
        guard let mode = mode else { return true }
        return mode == "primary" || mode == "all"
    }

    static let fallbackAgentName = "build"

    /// Keep `selection` when the server catalog is empty or contains it.
    /// Otherwise use the first visible agent, then `fallbackAgentName`.
    static func effectiveSelectedAgent(selection: String, agents: [AgentInfo]) -> String {
        guard !agents.isEmpty else { return selection }
        if agents.contains(where: { $0.name == selection }) {
            return selection
        }
        return agents.first(where: { $0.isVisible })?.name ?? fallbackAgentName
    }
}
