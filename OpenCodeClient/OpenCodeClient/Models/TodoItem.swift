//
//  TodoItem.swift
//  OpenCodeClient
//

import Foundation

struct TodoItem: Codable, Identifiable, Hashable {
    let content: String
    let status: String
    let priority: String
    let id: String

    var isCompleted: Bool {
        status == "completed" || status == "cancelled"
    }
}
