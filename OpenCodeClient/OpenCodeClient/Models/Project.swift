//
//  Project.swift
//  OpenCodeClient
//

import Foundation

struct Project: Codable, Identifiable {
    let id: String
    let worktree: String
    let vcs: String?
    let icon: IconInfo?
    let time: TimeInfo?
    let sandboxes: [Sandbox]?

    struct IconInfo: Codable {
        let color: String?
    }

    struct TimeInfo: Codable {
        let created: Int?
        let updated: Int?
    }

    struct Sandbox: Codable {
        // Server may return sandbox config; we don't need to decode details.
    }

    /// Display name for UI: last path component of worktree (e.g. "knowledge_working")
    var displayName: String {
        (worktree as NSString).lastPathComponent
    }
}
