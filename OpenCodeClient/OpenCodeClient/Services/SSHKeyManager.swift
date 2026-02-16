//
//  SSHKeyManager.swift
//  OpenCodeClient
//

import Foundation
import Crypto

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

    static func savePrivateKey(_ key: Data) {
        KeychainHelper.save(key, forKey: privateKeyKeychainKey)
    }
    
    static func loadPrivateKey() -> Data? {
        KeychainHelper.loadData(forKey: privateKeyKeychainKey)
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
        KeychainHelper.delete(privateKeyKeychainKey)
        UserDefaults.standard.removeObject(forKey: publicKeyUserDefaultsKey)
    }
    
    static func hasKeyPair() -> Bool {
        loadPrivateKey() != nil && getPublicKey() != nil
    }

    static func ensureKeyPair() throws -> String {
        if let existing = getPublicKey(), loadPrivateKey() != nil {
            return existing
        }

        if let privateKeyData = loadPrivateKey() {
            let repairedPublicKey = try publicKeyLine(fromPrivateKeyData: privateKeyData)
            savePublicKey(repairedPublicKey)
            return repairedPublicKey
        }
        
        let (privateKey, publicKey) = try generateKeyPair()
        savePrivateKey(privateKey)
        savePublicKey(publicKey)
        return publicKey
    }
    
    static func rotateKey() throws -> String {
        deleteKeyPair()
        return try ensureKeyPair()
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
