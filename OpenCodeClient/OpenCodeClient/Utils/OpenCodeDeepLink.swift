import Foundation

nonisolated enum OpenCodeDeepLink: Equatable {
    case session(id: String)
}

nonisolated enum OpenCodeDeepLinkParseError: Error, Equatable {
    case unsupportedScheme
    case invalidSessionLink
}

nonisolated enum OpenCodeDeepLinkParser {
    static let scheme = "opencode"

    static func handles(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    static func parse(_ url: URL) -> Result<OpenCodeDeepLink, OpenCodeDeepLinkParseError> {
        guard handles(url) else { return .failure(.unsupportedScheme) }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == "session",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else {
            return .failure(.invalidSessionLink)
        }

        let encodedPath = components.percentEncodedPath
        guard encodedPath.hasPrefix("/"), encodedPath.count > 1 else {
            return .failure(.invalidSessionLink)
        }
        let encodedSessionID = String(encodedPath.dropFirst())
        guard !encodedSessionID.contains("/"),
              let sessionID = encodedSessionID.removingPercentEncoding,
              isValidSessionID(sessionID) else {
            return .failure(.invalidSessionLink)
        }

        return .success(.session(id: sessionID))
    }

    private static func isValidSessionID(_ value: String) -> Bool {
        guard value.hasPrefix("ses_"), value.count > 4, value.count <= 256 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
    }
}
