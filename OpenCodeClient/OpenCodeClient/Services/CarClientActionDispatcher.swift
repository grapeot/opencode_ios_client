import Foundation
#if os(iOS)
import UIKit
#endif

enum CarClientActionDispatcher {
    static func navigationURL(for action: CarClientAction) -> URL? {
        let destination = action.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard action.type == "open_navigation", !destination.isEmpty, destination.count <= 240 else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        var queryItems = [
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "dirflg", value: "d"),
        ]
        if let waypoints = action.waypoints, !waypoints.isEmpty {
            let validWaypoints = waypoints
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 240 }
                .prefix(3)
            if !validWaypoints.isEmpty {
                queryItems.append(URLQueryItem(name: "waypoints", value: validWaypoints.joined(separator: "|")))
            }
        }
        components.queryItems = queryItems
        return components.url
    }

    @MainActor
    static func dispatch(_ action: CarClientAction) async -> Bool {
        guard let url = navigationURL(for: action) else { return false }
        #if os(iOS)
        return await UIApplication.shared.open(url)
        #else
        return false
        #endif
    }
}
