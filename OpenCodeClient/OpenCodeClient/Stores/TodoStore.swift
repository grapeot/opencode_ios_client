//
//  TodoStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
final class TodoStore {
    var sessionTodos: [String: [TodoItem]] = [:]
}
