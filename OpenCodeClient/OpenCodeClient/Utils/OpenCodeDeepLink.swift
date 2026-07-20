import Foundation

nonisolated enum OpenCodeDeepLink: Equatable {
    case session(id: String)
    case clientActionReturn(ClientActionCallback)
}

nonisolated enum OpenCodeDeepLinkParseError: Error, Equatable {
    case unsupportedScheme
    case invalidSessionLink
    case invalidClientActionCallback
}

nonisolated enum OpenCodeDeepLinkParser {
    static let scheme = "opencode"

    static func handles(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    static func parse(_ url: URL) -> Result<OpenCodeDeepLink, OpenCodeDeepLinkParseError> {
        guard handles(url) else { return .failure(.unsupportedScheme) }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else {
            return .failure(.unsupportedScheme)
        }
        switch components.host?.lowercased() {
        case "session":
            return parseSession(components)
        case "client-action-return":
            return parseClientActionCallback(components)
        default:
            return .failure(.invalidSessionLink)
        }
    }

    private static func parseSession(_ components: URLComponents) -> Result<OpenCodeDeepLink, OpenCodeDeepLinkParseError> {
        guard components.user == nil,
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

    private static func parseClientActionCallback(_ components: URLComponents) -> Result<OpenCodeDeepLink, OpenCodeDeepLinkParseError> {
        guard components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil else {
            return .failure(.invalidClientActionCallback)
        }

        let encodedPath = components.percentEncodedPath
        guard encodedPath.hasPrefix("/"), encodedPath.count > 1 else {
            return .failure(.invalidClientActionCallback)
        }
        let encodedID = String(encodedPath.dropFirst())
        guard !encodedID.contains("/"),
              let callbackID = encodedID.removingPercentEncoding,
              encodedID == callbackID,
              ClientCapabilityCallbackStore.isValidCallbackID(callbackID) else {
            return .failure(.invalidClientActionCallback)
        }

        let allowedNames = Set(["status", "sent", "upserted", "failed", "error_code"])
        let items = components.queryItems ?? []
        guard !items.isEmpty,
              items.allSatisfy({ allowedNames.contains($0.name) }),
              Dictionary(grouping: items, by: \.name).values.allSatisfy({ $0.count == 1 }) else {
            return .failure(.invalidClientActionCallback)
        }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let statusValue = values["status"], let status = HealthExportStatus(rawValue: statusValue),
              let sent = parseCount(values["sent"]),
              let upserted = parseCount(values["upserted"]) else {
            return .failure(.invalidClientActionCallback)
        }

        let failed: [HealthExportCategory]
        if let raw = values["failed"], !raw.isEmpty {
            let values = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard Set(values).count == values.count else { return .failure(.invalidClientActionCallback) }
            let parsed = values.compactMap(HealthExportCategory.init(rawValue:))
            guard parsed.count == values.count else { return .failure(.invalidClientActionCallback) }
            failed = parsed
        } else {
            failed = []
        }

        let errorCode: HealthExportErrorCode?
        if let raw = values["error_code"], !raw.isEmpty {
            guard let parsed = HealthExportErrorCode(rawValue: raw) else {
                return .failure(.invalidClientActionCallback)
            }
            errorCode = parsed
        } else {
            errorCode = nil
        }

        let callback = ClientActionCallback(
            callbackID: callbackID,
            status: status,
            sent: sent,
            upserted: upserted,
            failedCategories: failed,
            errorCode: errorCode
        )
        return .success(.clientActionReturn(callback))
    }

    private static func parseCount(_ value: String?) -> Int? {
        guard let value, !value.isEmpty, value.allSatisfy(\.isNumber),
              let count = Int(value), count <= Int(Int32.max) else { return nil }
        return count
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
