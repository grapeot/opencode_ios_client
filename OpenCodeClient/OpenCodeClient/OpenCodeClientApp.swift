//
//  OpenCodeClientApp.swift
//  OpenCodeClient
//

import SwiftUI

#if os(visionOS)
private enum VisionWindowDefaults {
    static let width: CGFloat = 1382
    static let height: CGFloat = 1188
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
