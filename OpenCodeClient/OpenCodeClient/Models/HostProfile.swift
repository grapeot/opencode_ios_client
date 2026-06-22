import Foundation

enum HostTransport: String, Codable, Equatable, CaseIterable, Identifiable {
    case direct
    case sshTunnel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .direct: return "Direct"
        case .sshTunnel: return "SSH Tunnel"
        }
    }
}

enum ConnectionPhase: String, Codable, Equatable {
    case idle
    case sshGateway
    case sshAuth
    case localTunnel
    case health
    case bootstrap
    case connected
    case failed

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .sshGateway: return "Connecting to SSH gateway"
        case .sshAuth: return "Authenticating with device key"
        case .localTunnel: return "Starting local tunnel"
        case .health: return "Checking OpenCode health"
        case .bootstrap: return "Loading projects and sessions"
        case .connected: return "Connected"
        case .failed: return "Connection failed"
        }
    }
}

struct ConnectionDiagnostic: Codable, Equatable {
    var hostProfileID: UUID?
    var phase: ConnectionPhase
    var message: String
    var recoveryHint: String?
    var timestamp: Date
}

struct BasicAuthConfig: Codable, Equatable {
    var username: String
    var keychainPasswordID: String
}

struct HostProfile: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var transport: HostTransport
    var serverURL: String
    var basicAuth: BasicAuthConfig?
    var ssh: SSHTunnelConfig?
    var lastUsedAt: Date?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Host" : trimmed
    }

    var connectionSummary: String {
        switch transport {
        case .direct:
            return serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        case .sshTunnel:
            guard let ssh else { return "SSH Tunnel" }
            let host = ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(host):\(ssh.port) -> :\(ssh.remotePort)"
        }
    }

    static func defaultProfile(serverURL: String = APIClient.defaultServer) -> HostProfile {
        HostProfile(
            name: "Local OpenCode",
            transport: .direct,
            serverURL: serverURL,
            basicAuth: nil,
            ssh: nil,
            lastUsedAt: Date()
        )
    }
}

struct HostProfileImportPayload: Codable {
    var version: Int?
    var name: String
    var transport: HostTransport
    var serverURL: String?
    var ssh: SSHTunnelConfig?

    func makeProfile() throws -> HostProfile {
        switch transport {
        case .direct:
            guard let serverURL, !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HostProfileError.invalidImport("Direct host config requires serverURL.")
            }
            return HostProfile(name: name, transport: .direct, serverURL: serverURL, basicAuth: nil, ssh: nil)
        case .sshTunnel:
            guard var ssh else {
                throw HostProfileError.invalidImport("SSH Tunnel host config requires ssh settings.")
            }
            ssh.isEnabled = true
            if let error = ssh.validationError {
                throw HostProfileError.invalidImport(error)
            }
            return HostProfile(
                name: name,
                transport: .sshTunnel,
                serverURL: serverURL ?? APIClient.defaultServer,
                basicAuth: nil,
                ssh: ssh
            )
        }
    }
}

struct HostProfileExportPayload: Codable, Equatable {
    var version = 1
    var name: String
    var transport: HostTransport
    var serverURL: String?
    var ssh: HostProfileExportSSH?
}

struct HostProfileExportSSH: Codable, Equatable {
    var host: String
    var port: Int
    var username: String
    var remotePort: Int
}

enum HostProfileError: LocalizedError, Equatable {
    case invalidImport(String)
    case cannotDeleteOnlyHost

    var errorDescription: String? {
        switch self {
        case .invalidImport(let message): return message
        case .cannotDeleteOnlyHost: return "Add another host before deleting this one."
        }
    }
}
