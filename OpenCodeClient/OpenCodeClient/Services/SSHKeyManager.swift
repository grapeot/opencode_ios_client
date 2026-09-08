//
//  SSHKeyManager.swift
//  OpenCodeClient
//

import Foundation
#if os(visionOS)
import CryptoKit
#else
import Crypto
#endif

enum SSHKeyManager {
    private static let privateKeyKeychainKey = "sshPrivateKey.ed25519"
    private static let publicKeyUserDefaultsKey = "sshPublicKey.ed25519"
    private static let keyComment = "opencode-ios"

    static func generateKeyPair() throws -> (privateKey: Data, publicKey: String) {
        let privateKey = Curve25519.Signing.PrivateKey()

        let privateKeyData = Data(privateKey.rawRepresentation)
        let openSSHPublicKey = makeOpenSSHEd25519PublicKey(publicKeyRaw: Data(privateKey.publicKey.rawRepresentation))
        let publicKeyLine = "ssh-ed25519 \(openSSHPublicKey) \(keyComment)"

        return (privateKeyData, publicKeyLine)
    }

    static func savePrivateKey(_ key: Data) throws {
        try KeychainHelper.save(key, forKey: privateKeyKeychainKey)
    }

    static func loadPrivateKey() throws -> Data? {
        try KeychainHelper.loadData(forKey: privateKeyKeychainKey)
    }

    static func savePublicKey(_ publicKey: String) {
        UserDefaults.standard.set(publicKey, forKey: publicKeyUserDefaultsKey)
    }

    static func getPublicKey() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: publicKeyUserDefaultsKey) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func deleteKeyPair() {
        try? KeychainHelper.delete(privateKeyKeychainKey)
        UserDefaults.standard.removeObject(forKey: publicKeyUserDefaultsKey)
    }

    static func hasKeyPair() -> Bool {
        (try? loadPrivateKey())?.isEmpty == false && getPublicKey() != nil
    }

    /// Read-only: never generates. Returns the cached public key after
    /// verifying it derives from the stored private key. Throws
    /// `SSHError.keyUnavailable` when the Keychain is transiently unreadable
    /// and `SSHError.keyNotFound` when no private key exists.
    static func getKeyPair() throws -> String {
        let privateKeyData: Data?
        do {
            privateKeyData = try loadPrivateKey()
        } catch {
            throw SSHError.keyUnavailable
        }
        guard let privateKeyData else {
            throw SSHError.keyNotFound
        }
        let derivedPublicKey = try publicKeyLine(fromPrivateKeyData: privateKeyData)
        if let cached = getPublicKey(), cached == derivedPublicKey {
            return cached
        }
        savePublicKey(derivedPublicKey)
        return derivedPublicKey
    }

    /// Generate authority is restricted to bootstrap: only generates when the
    /// private-key item is truly absent (`loadPrivateKey()` returns nil, i.e.
    /// `errSecItemNotFound`). Any other Keychain failure throws
    /// `SSHError.keyUnavailable` without touching stored keys.
    static func ensureKeyPair() throws -> String {
        let privateKeyData: Data?
        do {
            privateKeyData = try loadPrivateKey()
        } catch {
            throw SSHError.keyUnavailable
        }

        if let privateKeyData {
            let derivedPublicKey = try publicKeyLine(fromPrivateKeyData: privateKeyData)
            if getPublicKey() != derivedPublicKey {
                savePublicKey(derivedPublicKey)
            }
            return derivedPublicKey
        }

        let (newPrivateKey, publicKey) = try generateKeyPair()
        try savePrivateKey(newPrivateKey)
        savePublicKey(publicKey)
        return publicKey
    }

    static func rotateKey() throws -> String {
        let (newPrivateKey, newPublicKey) = try generateKeyPair()
        try savePrivateKey(newPrivateKey)
        savePublicKey(newPublicKey)
        return newPublicKey
    }

    // OpenSSH public key format (base64 of SSH wire encoding):
    // string "ssh-ed25519" + string keyBytes
    private static func makeOpenSSHEd25519PublicKey(publicKeyRaw: Data) -> String {
        var blob = Data()
        blob.append(sshString("ssh-ed25519"))
        blob.append(sshString(publicKeyRaw))
        return blob.base64EncodedString()
    }

    private static func sshString(_ s: String) -> Data {
        sshString(Data(s.utf8))
    }

    private static func sshString(_ data: Data) -> Data {
        var out = Data()
        var len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(data)
        return out
    }

    private static func publicKeyLine(fromPrivateKeyData privateKeyData: Data) throws -> String {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let openSSHPublicKey = makeOpenSSHEd25519PublicKey(publicKeyRaw: Data(privateKey.publicKey.rawRepresentation))
        return "ssh-ed25519 \(openSSHPublicKey) \(keyComment)"
    }
}
