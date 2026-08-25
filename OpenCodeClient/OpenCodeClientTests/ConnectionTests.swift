//
//  ConnectionTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

// MARK: - Host Profiles

@Suite(.serialized)
struct HostProfileTests {
    @Test func importDirectHostProfile() throws {
        let json = """
        {
          "version": 1,
          "name": "Office Mac",
          "transport": "direct",
          "serverURL": "https://opencode.example.invalid"
        }
        """

        let profile = try HostProfileImportPayload.makeProfile(from: json)

        #expect(profile.name == "Office Mac")
        #expect(profile.transport == .direct)
        #expect(profile.serverURL == "https://opencode.example.invalid")
        #expect(profile.ssh == nil)
        #expect(profile.basicAuth == nil)
    }

    @Test func importSSHTunnelHostProfileUsesTunnelDefaults() throws {
        let json = """
        {
          "version": 1,
          "name": "SSH Lab",
          "transport": "sshTunnel",
          "ssh": {
            "host": "gateway.example.invalid",
            "port": 8006,
            "username": "opencode",
            "remotePort": 19001
          }
        }
        """

        let profile = try HostProfileImportPayload.makeProfile(from: json)

        #expect(profile.name == "SSH Lab")
        #expect(profile.transport == .sshTunnel)
        #expect(profile.serverURL == APIClient.defaultServer)
        #expect(profile.ssh?.isEnabled == true)
        #expect(profile.ssh?.host == "gateway.example.invalid")
        #expect(profile.ssh?.port == 8006)
        #expect(profile.ssh?.username == "opencode")
        #expect(profile.ssh?.remotePort == 19001)
        #expect(profile.basicAuth == nil)
    }

    @Test func importRejectsDirectProfileWithoutServerURL() throws {
        let json = """
        {"name":"Broken","transport":"direct"}
        """

        #expect(throws: HostProfileError.invalidImport("Direct host config requires serverURL.")) {
            try HostProfileImportPayload.makeProfile(from: json)
        }
    }

    @Test @MainActor func defaultProfileMigratesFromLegacyServerURL() {
        withIsolatedHostProfileDefaults {
            UserDefaults.standard.set("https://legacy.example.invalid", forKey: AppState.serverURLKey)

            let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())

            #expect(state.hostProfiles.count == 1)
            #expect(state.currentHostProfile?.displayName == "Local OpenCode")
            #expect(state.currentHostProfile?.transport == .direct)
            #expect(state.currentHostProfile?.serverURL == "https://legacy.example.invalid")
            #expect(state.serverURL == "https://legacy.example.invalid")
        }
    }

    @Test @MainActor func applySSHTunnelProfileToRuntime() {
        withIsolatedHostProfileDefaults {
            let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
            let profile = HostProfile(
                name: "SSH Lab",
                transport: .sshTunnel,
                serverURL: "https://ignored.example.invalid",
                basicAuth: nil,
                ssh: SSHTunnelConfig(isEnabled: false, host: "gateway.example.invalid", port: 8006, username: "opencode", remotePort: 19001)
            )

            state.saveHostProfile(profile, makeCurrent: true)

            #expect(state.currentHostProfileID == profile.id)
            #expect(state.serverURL == APIClient.defaultServer)
            #expect(state.sshTunnelManager.config.isEnabled == true)
            #expect(state.sshTunnelManager.config.host == "gateway.example.invalid")
            #expect(state.sshTunnelManager.config.remotePort == 19001)
        }
    }

    @Test @MainActor func exportSSHTunnelHostConfigOmitsSecretsAndRuntimeState() throws {
        withIsolatedHostProfileDefaults {
            let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
            let profile = HostProfile(
                name: "SSH Lab",
                transport: .sshTunnel,
                serverURL: APIClient.defaultServer,
                basicAuth: BasicAuthConfig(username: "admin", keychainPasswordID: "secret-password-id"),
                ssh: SSHTunnelConfig(isEnabled: true, host: "gateway.example.invalid", port: 8006, username: "opencode", remotePort: 19001)
            )

            let json = try! state.hostConfigJSON(for: profile)

            #expect(json.contains("\"transport\" : \"sshTunnel\""))
            #expect(json.contains("\"host\" : \"gateway.example.invalid\""))
            #expect(json.contains("\"remotePort\" : 19001"))
            #expect(!json.contains("secret-password-id"))
            #expect(!json.contains("basicAuth"))
            #expect(!json.contains("isEnabled"))
        }
    }

    @Test @MainActor func friendlyConnectionErrorMapsRawAPIError() {
        withIsolatedHostProfileDefaults {
            let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())

            let message = state.friendlyConnectionError(APIError.invalidURL, phase: .health)

            #expect(message == "Invalid OpenCode URL. Check the host address and port.")
            #expect(!message.contains("APIError"))
        }
    }

    @Test @MainActor func deleteOnlyHostThrows() throws {
        withIsolatedHostProfileDefaults {
            let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager())
            let profile = state.currentHostProfile!

            #expect(throws: HostProfileError.cannotDeleteOnlyHost) {
                try state.deleteHostProfile(profile)
            }
            #expect(state.hostProfiles.count == 1)
        }
    }
}

private extension HostProfileImportPayload {
    static func makeProfile(from json: String) throws -> HostProfile {
        let payload = try JSONDecoder().decode(HostProfileImportPayload.self, from: Data(json.utf8))
        return try payload.makeProfile()
    }
}

@MainActor
private func withIsolatedHostProfileDefaults(_ body: () -> Void) {
    let keys = [
        AppState.serverURLKey,
        AppState.usernameKey,
        AppState.hostProfilesKey,
        AppState.currentHostProfileIDKey,
        "sshTunnelConfig",
    ]
    let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    defer {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        for (key, value) in previous {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    body()
}

// MARK: - AppError Tests

struct AppErrorTests {
    
    @Test func appErrorConnectionFailed() {
        let error = AppError.connectionFailed("Network unreachable")
        #expect(error.localizedDescription == L10n.errorMessage(.errorConnectionFailed, "Network unreachable"))
        #expect(error.isConnectionError == true)
        #expect(error.isRecoverable == true)
    }
    
    @Test func appErrorUnauthorized() {
        let error = AppError.unauthorized
        #expect(error.localizedDescription == L10n.t(.errorUnauthorized))
        #expect(error.isRecoverable == true)
    }
    
    @Test func appErrorFromFileNotFound() {
        let error = AppError.fileNotFound("/path/to/file.swift")
        #expect(error.localizedDescription == L10n.errorMessage(.errorFileNotFound, "/path/to/file.swift"))
        #expect(error.isRecoverable == false)
    }
    
    @Test func appErrorFromNSError() {
        let nsError = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "Request timed out"])
        let appError = AppError.from(nsError)
        if case .connectionFailed = appError {
            #expect(Bool(true))
        } else {
            Issue.record("Expected connectionFailed error")
        }
    }
    
    @Test func appErrorEquality() {
        let e1 = AppError.connectionFailed("test")
        let e2 = AppError.connectionFailed("test")
        let e3 = AppError.connectionFailed("other")
        #expect(e1 == e2)
        #expect(e1 != e3)
    }
}

// MARK: - APIConstants Tests

struct APIConstantsTests {
    
    @Test func defaultServer() {
        #expect(APIConstants.defaultServer == "127.0.0.1:4096")
    }

    @Test func legacyDefaultServer() {
        #expect(APIConstants.legacyDefaultServer == "localhost:4096")
    }
    
    @Test func sseEndpoint() {
        #expect(APIConstants.sseEndpoint == "/global/event")
    }
    
    @Test func healthEndpoint() {
        #expect(APIConstants.healthEndpoint == "/global/health")
    }
    
    @Test func timeoutValues() {
        #expect(APIConstants.Timeout.connection > 0)
        #expect(APIConstants.Timeout.request > APIConstants.Timeout.connection)
    }
}

// MARK: - SSH Tunnel Tests

struct SSHTunnelTests {

    @Test func sshTunnelConfigDefault() {
        let config = SSHTunnelConfig()
        #expect(config.isEnabled == false)
        #expect(config.host == "")
        #expect(config.port == 8006)
        #expect(config.username == "opencode")
        #expect(config.remotePort == 19001)
    }

    @Test func sshTunnelConfigValidation() {
        var config = SSHTunnelConfig()
        #expect(config.isValid == false)
        
        config.host = "example.com"
        config.username = "user"
        #expect(config.isValid == true)
        
        config.port = 0
        #expect(config.isValid == false)
        
        config.port = 22
        config.remotePort = 0
        #expect(config.isValid == false)
    }

    @Test func sshTunnelConfigCoding() throws {
        var config = SSHTunnelConfig()
        config.isEnabled = true
        config.host = "vps.example.com"
        config.port = 2222
        config.username = "testuser"
        config.remotePort = 8080
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SSHTunnelConfig.self, from: data)
        
        #expect(decoded.isEnabled == true)
        #expect(decoded.host == "vps.example.com")
        #expect(decoded.port == 2222)
        #expect(decoded.username == "testuser")
        #expect(decoded.remotePort == 8080)
    }

    @Test func sshTunnelConfigEquatable() {
        let c1 = SSHTunnelConfig(isEnabled: true, host: "a.com", port: 8006, username: "u", remotePort: 19001)
        let c2 = SSHTunnelConfig(isEnabled: true, host: "a.com", port: 8006, username: "u", remotePort: 19001)
        let c3 = SSHTunnelConfig(isEnabled: false, host: "a.com", port: 8006, username: "u", remotePort: 19001)
        
        #expect(c1 == c2)
        #expect(c1 != c3)
    }

    @Test func sshConnectionStatusEquatable() {
        #expect(SSHConnectionStatus.disconnected == SSHConnectionStatus.disconnected)
        #expect(SSHConnectionStatus.connecting == SSHConnectionStatus.connecting)
        #expect(SSHConnectionStatus.connected == SSHConnectionStatus.connected)
        #expect(SSHConnectionStatus.error("msg") == SSHConnectionStatus.error("msg"))
        #expect(SSHConnectionStatus.error("a") != SSHConnectionStatus.error("b"))
        #expect(SSHConnectionStatus.disconnected != SSHConnectionStatus.connected)
    }

    @Test func sshErrorDescriptions() {
        #expect(SSHError.connectionFailed("timeout").errorDescription?.contains("timeout") == true)
        #expect(SSHError.authenticationFailed.errorDescription?.contains("Authentication") == true)
        #expect(SSHError.keyNotFound.errorDescription?.contains("key not found") == true)
        #expect(SSHError.invalidKeyFormat.errorDescription?.contains("Invalid") == true)
        #expect(SSHError.tunnelFailed("x").errorDescription?.contains("Tunnel") == true)
        #expect(SSHError.hostKeyMismatch(expected: "a", got: "b", presentedOpenSSHKey: "ssh-ed25519 AAAA").errorDescription?.contains("Host key mismatch") == true)
    }

    @Test @MainActor func sshTunnelManagerInitialStatus() {
        let manager = SSHTunnelManager()
        #expect(manager.status == .disconnected)
        #expect(manager.config.isEnabled == false)
    }

    @Test @MainActor func sshTunnelManagerConfigPersistence() {
        let manager = SSHTunnelManager()
        manager.config.host = "test.example.com"
        manager.config.port = 2222
        manager.config.username = "testuser"
        manager.config.remotePort = 9999
        
        // Create a new manager to test persistence
        let manager2 = SSHTunnelManager()
        #expect(manager2.config.host == "test.example.com")
        #expect(manager2.config.port == 2222)
        #expect(manager2.config.username == "testuser")
        #expect(manager2.config.remotePort == 9999)
        
        // Clean up
        manager2.config = .default
    }
}

// MARK: - SSH Key Manager Tests

struct SSHKeyManagerTests {

    @Test func sshKeyGenerationProducesValidKeys() throws {
        let (privateKey, publicKey) = try SSHKeyManager.generateKeyPair()
        
        #expect(!privateKey.isEmpty)
        #expect(!publicKey.isEmpty)
        #expect(publicKey.hasPrefix("ssh-ed25519 "))
        #expect(publicKey.contains("opencode-ios"))
    }

    @Test func ensureKeyPairRepairsMissingPublicKeyFromPrivateKey() throws {
        SSHKeyManager.deleteKeyPair()
        defer { SSHKeyManager.deleteKeyPair() }

        let (privateKey, _) = try SSHKeyManager.generateKeyPair()
        SSHKeyManager.savePrivateKey(privateKey)
        SSHKeyManager.savePublicKey("   ")

        let repaired = try SSHKeyManager.ensureKeyPair()

        #expect(!repaired.isEmpty)
        #expect(repaired.hasPrefix("ssh-ed25519 "))
        #expect(SSHKeyManager.getPublicKey() == repaired)
    }

}

struct SSHKnownHostStoreTests {

    @Test func knownHostTrustAndClear() throws {
        let host = "unit-test.example.com"
        let port = 2222
        SSHKnownHostStore.clear(host: host, port: port)

        let (_, publicKey) = try SSHKeyManager.generateKeyPair()
        SSHKnownHostStore.trust(host: host, port: port, openSSHKey: publicKey)

        #expect(SSHKnownHostStore.trustedOpenSSHKey(host: host, port: port) == publicKey)
        #expect((SSHKnownHostStore.fingerprint(host: host, port: port) ?? "").hasPrefix("SHA256:"))

        SSHKnownHostStore.clear(host: host, port: port)
        #expect(SSHKnownHostStore.trustedOpenSSHKey(host: host, port: port) == nil)
    }
}
