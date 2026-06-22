import Foundation

extension AppState {
    func loadHostProfilesFromStorageOrLegacy() {
        if let data = UserDefaults.standard.data(forKey: Self.hostProfilesKey),
           let decoded = try? JSONDecoder().decode([HostProfile].self, from: data),
           !decoded.isEmpty {
            hostProfiles = decoded
            if let idString = UserDefaults.standard.string(forKey: Self.currentHostProfileIDKey),
               let id = UUID(uuidString: idString),
               decoded.contains(where: { $0.id == id }) {
                currentHostProfileID = id
            } else {
                currentHostProfileID = decoded[0].id
            }
            return
        }

        var profile = HostProfile.defaultProfile(serverURL: _serverURL)
        if !_username.isEmpty || !_password.isEmpty {
            let passwordID = Self.passwordKeychainID(for: profile.id)
            if !_password.isEmpty {
                KeychainHelper.save(_password, forKey: passwordID)
            }
            profile.basicAuth = BasicAuthConfig(username: _username, keychainPasswordID: passwordID)
        }

        #if !os(visionOS)
        if sshTunnelManager.config.isEnabled {
            profile.name = "SSH OpenCode"
            profile.transport = .sshTunnel
            profile.serverURL = APIClient.defaultServer
            profile.ssh = sshTunnelManager.config
        }
        #endif

        hostProfiles = [profile]
        currentHostProfileID = profile.id
        saveHostProfiles()
    }

    func saveHostProfiles() {
        guard !hostProfiles.isEmpty,
              let data = try? JSONEncoder().encode(hostProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.hostProfilesKey)
    }

    func applyCurrentHostProfileToRuntime(persistLegacy: Bool = true) {
        guard let profile = currentHostProfile else { return }

        _serverURL = profile.serverURL
        _username = profile.basicAuth?.username ?? ""
        if let passwordID = profile.basicAuth?.keychainPasswordID {
            _password = KeychainHelper.load(forKey: passwordID) ?? ""
        } else {
            _password = ""
        }

        if persistLegacy {
            UserDefaults.standard.set(_serverURL, forKey: Self.serverURLKey)
            UserDefaults.standard.set(_username, forKey: Self.usernameKey)
            if _password.isEmpty {
                KeychainHelper.delete(Self.passwordKeychainKey)
            } else {
                KeychainHelper.save(_password, forKey: Self.passwordKeychainKey)
            }
        }

        #if !os(visionOS)
        switch profile.transport {
        case .direct:
            var disabled = sshTunnelManager.config
            disabled.isEnabled = false
            sshTunnelManager.config = disabled
            sshTunnelManager.disconnect()
        case .sshTunnel:
            var config = profile.ssh ?? .default
            config.isEnabled = true
            sshTunnelManager.config = config
        }
        #endif
    }

    func persistRuntimeToCurrentHostProfile() {
        guard let index = hostProfiles.firstIndex(where: { $0.id == currentHostProfileID }) else { return }
        var profile = hostProfiles[index]
        profile.serverURL = serverURL
        profile.lastUsedAt = Date()

        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.isEmpty {
            if let oldID = profile.basicAuth?.keychainPasswordID {
                KeychainHelper.delete(oldID)
            }
            profile.basicAuth = nil
        } else {
            let passwordID = profile.basicAuth?.keychainPasswordID ?? Self.passwordKeychainID(for: profile.id)
            if password.isEmpty {
                KeychainHelper.delete(passwordID)
            } else {
                KeychainHelper.save(password, forKey: passwordID)
            }
            profile.basicAuth = BasicAuthConfig(username: username, keychainPasswordID: passwordID)
        }

        #if !os(visionOS)
        if profile.transport == .sshTunnel {
            profile.ssh = sshTunnelManager.config
        }
        #endif

        hostProfiles[index] = profile
    }

    func saveHostProfile(_ profile: HostProfile, password: String? = nil, makeCurrent: Bool = true) {
        var saved = profile
        if saved.transport == .sshTunnel {
            var ssh = saved.ssh ?? .default
            ssh.isEnabled = true
            saved.ssh = ssh
            saved.serverURL = APIClient.defaultServer
        }
        if let password {
            let username = profile.basicAuth?.username ?? ""
            if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.isEmpty {
                saved.basicAuth = nil
            } else {
                let passwordID = profile.basicAuth?.keychainPasswordID ?? Self.passwordKeychainID(for: profile.id)
                if password.isEmpty {
                    KeychainHelper.delete(passwordID)
                } else {
                    KeychainHelper.save(password, forKey: passwordID)
                }
                saved.basicAuth = BasicAuthConfig(username: username, keychainPasswordID: passwordID)
            }
        }

        if let index = hostProfiles.firstIndex(where: { $0.id == saved.id }) {
            hostProfiles[index] = saved
        } else {
            hostProfiles.append(saved)
        }

        if makeCurrent {
            currentHostProfileID = saved.id
            applyCurrentHostProfileToRuntime()
        }
    }

    func switchHostProfile(to id: UUID) async {
        guard id != currentHostProfileID,
              hostProfiles.contains(where: { $0.id == id }) else { return }
        persistRuntimeToCurrentHostProfile()
        disconnectSSE()
        #if !os(visionOS)
        sshTunnelManager.disconnect()
        #endif
        currentHostProfileID = id
        applyCurrentHostProfileToRuntime()
        resetConnectionRuntimeForHostSwitch()
        await refresh()
    }

    func deleteHostProfile(_ profile: HostProfile) throws {
        guard hostProfiles.count > 1 else { throw HostProfileError.cannotDeleteOnlyHost }
        let wasCurrent = profile.id == currentHostProfileID
        if let passwordID = profile.basicAuth?.keychainPasswordID {
            KeychainHelper.delete(passwordID)
        }
        hostProfiles.removeAll { $0.id == profile.id }
        if wasCurrent, let first = hostProfiles.first {
            currentHostProfileID = first.id
            applyCurrentHostProfileToRuntime()
            resetConnectionRuntimeForHostSwitch()
        }
    }

    func duplicateHostProfile(_ profile: HostProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.displayName) Copy"
        copy.lastUsedAt = nil
        if let auth = profile.basicAuth {
            let newPasswordID = Self.passwordKeychainID(for: copy.id)
            if let password = KeychainHelper.load(forKey: auth.keychainPasswordID) {
                KeychainHelper.save(password, forKey: newPasswordID)
            }
            copy.basicAuth = BasicAuthConfig(username: auth.username, keychainPasswordID: newPasswordID)
        }
        saveHostProfile(copy, makeCurrent: false)
    }

    func importHostProfile(from json: String) throws -> HostProfile {
        guard let data = json.data(using: .utf8) else {
            throw HostProfileError.invalidImport("Host config is not valid UTF-8.")
        }
        do {
            let payload = try JSONDecoder().decode(HostProfileImportPayload.self, from: data)
            return try payload.makeProfile()
        } catch let error as HostProfileError {
            throw error
        } catch {
            throw HostProfileError.invalidImport(error.localizedDescription)
        }
    }

    func resetConnectionRuntimeForHostSwitch() {
        isConnected = false
        connectionError = nil
        serverVersion = nil
        projects = []
        serverCurrentProjectWorktree = nil
        sessions = []
        currentSessionID = nil
        messages = []
        partsByMessage = [:]
        sessionDiffs = []
        fileTreeRoot = []
        pendingPermissions = []
        sessionStatuses = [:]
        sessionTodos = [:]
    }

    nonisolated static func passwordKeychainID(for profileID: UUID) -> String {
        "hostProfile.\(profileID.uuidString).password"
    }
}
