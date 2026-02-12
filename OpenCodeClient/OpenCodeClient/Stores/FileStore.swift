//
//  FileStore.swift
//  OpenCodeClient
//

import Foundation
import Observation

@Observable
final class FileStore {
    var sessionDiffs: [FileDiff] = []
    var selectedDiffFile: String?
    var fileTreeRoot: [FileNode] = []
    var fileStatusMap: [String: String] = [:]
    var expandedPaths: Set<String> = []
    var fileChildrenCache: [String: [FileNode]] = [:]
    var fileSearchQuery: String = ""
    var fileSearchResults: [String] = []
}
