//
//  OpenCodeClientApp.swift
//  OpenCodeClient
//

import SwiftUI

#if os(visionOS)
private enum VisionWindowDefaults {
    static let width: CGFloat = 2304
    static let height: CGFloat = 1080
}
#endif

@main
struct OpenCodeClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(visionOS)
        .defaultSize(width: VisionWindowDefaults.width, height: VisionWindowDefaults.height)
        #endif
    }
}
