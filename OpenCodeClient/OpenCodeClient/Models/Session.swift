//
//  Session.swift
//  OpenCodeClient
//

import Foundation

struct Session: Identifiable, Equatable {
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
    var revert: RevertInfo? = nil

    var isArchived: Bool {
        guard let archived = time.archived else { return false }
        return archived > 0
    }

    struct TimeInfo: Codable, Equatable {
        let created: Int
        let updated: Int
        let archived: Int?
    }

    struct ShareInfo: Codable, Equatable {
        let url: String
    }

    struct SummaryInfo: Codable, Equatable {
        let additions: Int
        let deletions: Int
        let files: Int
    }

    struct RevertInfo: Codable, Equatable {
        let messageID: String
        let partID: String?
        let snapshot: String?
        let diff: String?
    }
}

nonisolated extension Session: Codable {}

struct SessionStatus: Codable, Equatable {
    let type: String // "idle" | "busy" | "retry"
    let attempt: Int?
    let message: String?
    let next: Int?
}
