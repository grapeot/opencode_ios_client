//
//  SSHTunnelManager.swift
//  OpenCodeClient
//

import Foundation
import Combine
#if os(visionOS)
import CryptoKit
#else
import Citadel
import NIOCore
import Crypto
import NIOSSH
import Network
#endif

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

enum SSHKnownHostStore {
    private static let userDefaultsKey = "sshKnownHosts.openSSH"

    static func trustedOpenSSHKey(host: String, port: Int) -> String? {
        loadMap()[identity(host: host, port: port)]
    }

    static func trust(host: String, port: Int, openSSHKey: String) {
        var map = loadMap()
        map[identity(host: host, port: port)] = openSSHKey
        UserDefaults.standard.set(map, forKey: userDefaultsKey)
    }

    static func clear(host: String, port: Int) {
        var map = loadMap()
        map.removeValue(forKey: identity(host: host, port: port))
        UserDefaults.standard.set(map, forKey: userDefaultsKey)
    }

    static func fingerprint(host: String, port: Int) -> String? {
        guard let key = trustedOpenSSHKey(host: host, port: port) else { return nil }
        return fingerprint(openSSHKey: key)
    }

    static func fingerprint(openSSHKey: String) -> String {
        let components = openSSHKey.split(separator: " ")
        guard components.count >= 2, let keyData = Data(base64Encoded: String(components[1])) else {
            return "SHA256:invalid"
        }
        let digest = SHA256.hash(data: keyData)
        return "SHA256:\(Data(digest).base64EncodedString())"
    }

    private static func loadMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
    }

    private static func identity(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }
}

#if !os(visionOS)
private final class SSHTOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        if let trusted = SSHKnownHostStore.trustedOpenSSHKey(host: host, port: port) {
            if trusted == presented {
                validationCompletePromise.succeed(())
                return
            }
            validationCompletePromise.fail(
                SSHError.hostKeyMismatch(
                    expected: SSHKnownHostStore.fingerprint(openSSHKey: trusted),
                    got: SSHKnownHostStore.fingerprint(openSSHKey: presented)
                )
            )
            return
        }

        // TOFU: trust the first successful host key for this host:port.
        SSHKnownHostStore.trust(host: host, port: port, openSSHKey: presented)
        validationCompletePromise.succeed(())
    }
}
#endif

struct SSHTunnelConfig: Codable, Equatable {
    var isEnabled: Bool = false
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var remotePort: Int = 18080
    
    var isValid: Bool {
        !host.isEmpty && !username.isEmpty && port > 0 && remotePort > 0
    }

    var validationError: String? {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "VPS Host is required"
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "SSH Username is required"
        }
        if port <= 0 {
            return "SSH Port must be > 0"
        }
        if remotePort <= 0 {
            return "VPS Port must be > 0"
        }
        return nil
    }
    
    static let `default` = SSHTunnelConfig()
}

#if os(visionOS)
@MainActor
final class SSHTunnelManager: ObservableObject {
    @Published private(set) var status: SSHConnectionStatus = .disconnected
    @Published private(set) var trustedHostFingerprint: String?
    @Published var config: SSHTunnelConfig {
        didSet { saveConfig() }
    }

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

    var reverseTunnelCommand: String? {
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = config.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !username.isEmpty, config.remotePort > 0, config.port > 0 else { return nil }

        let portArg = config.port == 22 ? "" : " -p \(config.port)"
        return "ssh -N -T -R 127.0.0.1:\(config.remotePort):127.0.0.1:4096\(portArg) \(username)@\(host)"
    }

    func connect() async {
        status = .error("SSH tunnels are not available in the visionOS build yet. Connect directly to an OpenCode server instead.")
    }

    func disconnect(updateStatus: Bool = true) {
        if updateStatus {
            status = .disconnected
        }
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

    func clearTrustedHost() {
        trustedHostFingerprint = nil
    }
}
#else
@MainActor
final class SSHTunnelManager: ObservableObject {
    @Published private(set) var status: SSHConnectionStatus = .disconnected
    @Published private(set) var trustedHostFingerprint: String?
    @Published var config: SSHTunnelConfig {
        didSet {
            saveConfig()
            trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: config.host, port: config.port)
        }
    }
    
    private var sshClient: SSHClient?
    private var listener: NWListener?
    private var tunnelTask: Task<Void, Never>?
    private let localPort: NWEndpoint.Port = 4096
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "sshTunnelConfig"),
           let decoded = try? JSONDecoder().decode(SSHTunnelConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
        self.trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: self.config.host, port: self.config.port)
    }
    
    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: "sshTunnelConfig")
    }

    var reverseTunnelCommand: String? {
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = config.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !username.isEmpty, config.remotePort > 0, config.port > 0 else { return nil }

        let portArg = config.port == 22 ? "" : " -p \(config.port)"
        return "ssh -N -T -R 127.0.0.1:\(config.remotePort):127.0.0.1:4096\(portArg) \(username)@\(host)"
    }
    
    func connect() async {
        if let err = config.validationError {
            status = .error(err)
            return
        }

        // Ensure key pair exists (first run auto-generates).
        _ = try? SSHKeyManager.ensureKeyPair()

        guard let privateKeyData = SSHKeyManager.loadPrivateKey() else {
            status = .error("No SSH key found. Please generate a key pair first.")
            return
        }
        
        status = .connecting
        
        do {
            try await establishTunnel(privateKeyData: privateKeyData)
            status = .connected
        } catch {
            disconnect()
            status = .error(error.localizedDescription)
        }
    }
    
    private func establishTunnel(privateKeyData: Data) async throws {
        #if DEBUG
        print("[SSH] Connecting to \(config.host):\(config.port) as \(config.username)")
        print("[SSH] Remote port: \(config.remotePort)")
        #endif
        
        guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
            throw SSHError.invalidKeyFormat
        }
        
        let username = config.username
        let settings = SSHClientSettings(
            host: config.host,
            port: config.port,
            authenticationMethod: { .ed25519(username: username, privateKey: privateKey) },
            hostKeyValidator: .custom(SSHTOFUHostKeyValidator(host: config.host, port: config.port))
        )
        
        let client = try await SSHClient.connect(to: settings)
        self.sshClient = client
        self.trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: config.host, port: config.port)
        
        #if DEBUG
        print("[SSH] Connected successfully")
        #endif
        
        try startLocalListener(sshClient: client)
    }

    private func startLocalListener(sshClient: SSHClient) throws {
        if let listener {
            listener.cancel()
            self.listener = nil
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback

        let listener = try NWListener(using: params, on: localPort)
        self.listener = listener

        let queue = DispatchQueue(label: "com.opencode.ssh.tunnel.listener")
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .failed(let err):
                Task { @MainActor in
                    self.status = .error("Local listener failed: \(err.localizedDescription)")
                    self.disconnect(updateStatus: false)
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { @MainActor in
                self.handleLocalConnection(conn, sshClient: sshClient)
            }
        }

        listener.start(queue: queue)
    }

    nonisolated private func handleLocalConnection(_ conn: NWConnection, sshClient: SSHClient) {
        let queue = DispatchQueue(label: "com.opencode.ssh.tunnel.conn")
        conn.stateUpdateHandler = { state in
            switch state {
            case .failed:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: queue)

        Task { [weak self] in
            let snapshot = await self?.connectionSnapshot() ?? (localPort: 4096, remotePort: 18080)

            do {
                let originator = try SocketAddress(ipAddress: "127.0.0.1", port: snapshot.localPort)

                let channel = try await sshClient.createDirectTCPIPChannel(
                    using: SSHChannelType.DirectTCPIP(
                        targetHost: "127.0.0.1",
                        targetPort: snapshot.remotePort,
                        originatorAddress: originator
                    )
                ) { channel in
                    channel.pipeline.addHandler(NIOToNWConnectionHandler(nwConnection: conn))
                }

                Self.startReceiveLoop(from: conn, to: channel)
            } catch {
                conn.cancel()
                await self?.setErrorIfStillConnected(error.localizedDescription)
            }
        }
    }

    nonisolated private static func startReceiveLoop(from conn: NWConnection, to channel: Channel) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                channel.eventLoop.execute {
                    var buffer = channel.allocator.buffer(capacity: data.count)
                    buffer.writeBytes(data)
                    channel.writeAndFlush(buffer, promise: nil)
                }
            }

            if isComplete || error != nil {
                channel.eventLoop.execute {
                    channel.close(promise: nil)
                }
                conn.cancel()
                return
            }

            Self.startReceiveLoop(from: conn, to: channel)
        }
    }
    
    func disconnect(updateStatus: Bool = true) {
        tunnelTask?.cancel()
        tunnelTask = nil

        listener?.cancel()
        listener = nil
        
        if let client = sshClient {
            Task {
                try? await client.close()
            }
        }
        sshClient = nil

        if updateStatus {
            status = .disconnected
        }
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

    func clearTrustedHost() {
        SSHKnownHostStore.clear(host: config.host, port: config.port)
        trustedHostFingerprint = SSHKnownHostStore.fingerprint(host: config.host, port: config.port)
    }

    private func connectionSnapshot() -> (localPort: Int, remotePort: Int) {
        (Int(localPort.rawValue), config.remotePort)
    }

    private func setErrorIfStillConnected(_ description: String) {
        if status == .connected {
            status = .error(description)
        }
    }
}

private final class NIOToNWConnectionHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let nwConnection: NWConnection

    nonisolated init(nwConnection: NWConnection) {
        self.nwConnection = nwConnection
    }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        guard !bytes.isEmpty else { return }

        nwConnection.send(content: Data(bytes), completion: .contentProcessed { error in
            if let error {
                #if DEBUG
                print("[SSH Tunnel] send failed: \(error)")
                #endif
                context.eventLoop.execute {
                    context.close(promise: nil)
                }
            }
        })
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        #if DEBUG
        print("[SSH Tunnel] channel error: \(error)")
        #endif
        context.close(promise: nil)
        nwConnection.cancel()
    }
}
#endif

enum SSHError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case keyNotFound
    case invalidKeyFormat
    case tunnelFailed(String)
    case hostKeyMismatch(expected: String, got: String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed. Please check your public key is added to the server."
        case .keyNotFound:
            return "SSH key not found. Please generate a key pair first."
        case .invalidKeyFormat:
            return "Invalid SSH key format."
        case .tunnelFailed(let reason):
            return "Tunnel failed: \(reason)"
        case .hostKeyMismatch(let expected, let got):
            return "Host key mismatch. Expected \(expected), got \(got). This may be a MITM attack or a reinstalled server. Reset trusted host and verify fingerprint before reconnecting."
        }
    }
}
