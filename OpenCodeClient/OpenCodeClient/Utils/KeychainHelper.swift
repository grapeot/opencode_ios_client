//
//  KeychainHelper.swift
//  OpenCodeClient
//

import Foundation
import Security

/// Minimal Keychain helper for storing sensitive credentials (e.g. password).
/// Uses kSecClassGenericPassword with service = bundle ID, account = key.
enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return L10n.t(.keychainErrorUnhandledStatus, Int32(status))
        }
    }
}

enum KeychainHelper {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.opencode.client"
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    static func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unhandledStatus(errSecInvalidData)
        }
        try save(data, forKey: key)
    }

    static func save(_ data: Data, forKey key: String) throws {
        var query = baseQuery
        query[kSecAttrAccount as String] = key
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecSuccess || updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(updateStatus)
        }
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unhandledStatus(status)
            }
        }
    }

    static func load(forKey key: String) throws -> String? {
        guard let data = try loadData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns nil only when the item is truly absent (`errSecItemNotFound`);
    /// throws on any other Keychain failure (e.g. `errSecInteractionNotAllowed`).
    static func loadData(forKey key: String) throws -> Data? {
        var query = baseQuery
        query[kSecAttrAccount as String] = key
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unhandledStatus(errSecInvalidData)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func delete(_ key: String) throws {
        var query = baseQuery
        query[kSecAttrAccount as String] = key
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }
}
