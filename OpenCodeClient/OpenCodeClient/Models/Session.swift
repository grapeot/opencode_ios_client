//
//  Session.swift
//  OpenCodeClient
//

import Foundation

struct Session: Identifiable {
    let id: String
    let slug: String
    let projectID: String
    let directory: String
    let parentID: String?
    let title: String
    let version: String
    let time: TimeInfo
    let share: ShareInfo?
    let summary: SummaryInfo?

    var isArchived: Bool {
        guard let archived = time.archived else { return false }
        return archived > 0
    }

    struct TimeInfo: Codable {
        let created: Int
        let updated: Int
        let archived: Int?
    }

    struct ShareInfo: Codable {
        let url: String
    }

    struct SummaryInfo: Codable {
        let additions: Int
        let deletions: Int
        let files: Int
    }
}

nonisolated extension Session: Codable {}

struct SessionStatus: Codable {
    let type: String // "idle" | "busy" | "retry"
    let attempt: Int?
    let message: String?
    let next: Int?
}
