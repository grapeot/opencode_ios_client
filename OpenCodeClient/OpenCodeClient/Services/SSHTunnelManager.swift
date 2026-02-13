//
//  SSHTunnelManager.swift
//  OpenCodeClient
//

import Foundation
import Combine
import Network

enum SSHConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    static func == (lhs: SSHConnectionStatus, rhs: SSHConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

struct SSHTunnelConfig: Codable, Equatable {
    var isEnabled: Bool = false
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var remotePort: Int = 18080
    
    var isValid: Bool {
        !host.isEmpty && !username.isEmpty && port > 0 && remotePort > 0
    }
    
    static let `default` = SSHTunnelConfig()
}

@MainActor
final class SSHTunnelManager: ObservableObject {
    @Published private(set) var status: SSHConnectionStatus = .disconnected
    @Published var config: SSHTunnelConfig {
        didSet { saveConfig() }
    }
    
    private var sshClient: Any?
    private var tunnelChannel: Any?
    private var listener: NWListener?
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "sshTunnelConfig"),
           let decoded = try? JSONDecoder().decode(SSHTunnelConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }
    
    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: "sshTunnelConfig")
    }
    
    func connect() async {
        guard config.isValid else {
            status = .error("Invalid configuration")
            return
        }
        
        guard let privateKeyData = SSHKeyManager.loadPrivateKey() else {
            status = .error("No SSH key found. Please generate a key pair first.")
            return
        }
        
        status = .connecting
        
        do {
            try await establishTunnel(privateKey: privateKeyData)
            status = .connected
        } catch {
            status = .error(error.localizedDescription)
        }
    }
    
    private func establishTunnel(privateKey: Data) async throws {
        #if DEBUG
        print("[SSH] Connecting to \(config.host):\(config.port) as \(config.username)")
        print("[SSH] Remote port: \(config.remotePort), Local port: 4096")
        print("[SSH] NOTE: Citadel dependency required for actual SSH connection")
        #endif
        
        throw SSHError.notImplemented
    }
    
    func disconnect() {
        listener?.cancel()
        listener = nil
        tunnelChannel = nil
        sshClient = nil
        status = .disconnected
    }
    
    func getPublicKey() -> String? {
        SSHKeyManager.getPublicKey()
    }
    
    func generateOrGetPublicKey() throws -> String {
        try SSHKeyManager.ensureKeyPair()
    }
    
    func rotateKey() throws -> String {
        try SSHKeyManager.rotateKey()
    }
}

enum SSHError: LocalizedError {
    case notImplemented
    case connectionFailed(String)
    case authenticationFailed
    case keyNotFound
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "SSH tunnel requires Citadel library. Please add the package dependency."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed. Please check your public key is added to the server."
        case .keyNotFound:
            return "SSH key not found."
        }
    }
}
