//
//  OpenCodeClientApp.swift
//  OpenCodeClient
//

import SwiftUI

#if os(visionOS)
private enum VisionWindowDefaults {
    static let width: CGFloat = 2000
    static let height: CGFloat = 1188
}
#endif

@main
struct OpenCodeClientApp: App {
    var body: some Scene {
        #if os(visionOS)
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: VisionWindowDefaults.width, height: VisionWindowDefaults.height)

        WindowGroup("Image Preview", for: MarkdownImagePreviewItem.self) { item in
            if let item = item.wrappedValue {
                MarkdownImagePreviewWindow(item: item)
            } else {
                Text("No image selected")
            }
        }
        .defaultSize(width: 1200, height: 900)
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
