//
//  LayoutConstants.swift
//  OpenCodeClient
//

import Foundation
import SwiftUI

enum LayoutConstants {
    // MARK: - iPad Split View Column Widths
    enum SplitView {
        /// Sidebar (Workspace) width as fraction of total width
        static let sidebarWidthFraction: CGFloat = 1.0 / 6.0
        /// Preview column width as fraction of total width
        static let previewWidthFraction: CGFloat = 5.0 / 12.0
        /// Chat column width as fraction of total width
        static let chatWidthFraction: CGFloat = 5.0 / 12.0
        
        /// Minimum sidebar width as fraction (10% of total)
        static let sidebarMinFraction: CGFloat = 0.10
        /// Maximum sidebar width as fraction (33% of total)
        static let sidebarMaxFraction: CGFloat = 0.33
        /// Minimum preview/chat width as fraction (25% of total)
        static let paneMinFraction: CGFloat = 0.25
        /// Maximum preview/chat width as fraction (70% of total)
        static let paneMaxFraction: CGFloat = 0.70
    }
    
    // MARK: - Animation Durations
    enum Animation {
        static let defaultDuration: Double = 0.25
        static let shortDuration: Double = 0.15
        static let longDuration: Double = 0.35
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let compact: CGFloat = 4
        static let standard: CGFloat = 8
        static let comfortable: CGFloat = 12
        static let spacious: CGFloat = 16
    }
    
    // MARK: - Message List
    enum MessageList {
        static let spacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 10
    }
    
    // MARK: - Toolbar
    enum Toolbar {
        static let buttonSpacing: CGFloat = 12
        static let modelButtonSpacing: CGFloat = 6
    }
}

enum APIConstants {
    static let defaultServer = "127.0.0.1:4096"
    static let legacyDefaultServer = "localhost:4096"
    static let sseEndpoint = "/global/event"
    static let healthEndpoint = "/global/health"
    
    enum Timeout {
        static let connection: TimeInterval = 30
        static let request: TimeInterval = 60
    }
}

enum StorageKeys {
    static let serverURL = "serverURL"
    static let username = "username"
    static let password = "password"
    static let themePreference = "themePreference"
    static let draftInputsBySession = "draftInputsBySession"
    static let selectedModelBySession = "selectedModelBySession"
    static let aiBuilderBaseURL = "aiBuilderBaseURL"
    static let aiBuilderToken = "aiBuilderToken"
    static let aiBuilderLastOKSignature = "aiBuilderLastOKSignature"
    static let aiBuilderLastTestedAt = "aiBuilderLastTestedAt"
}
