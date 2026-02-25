//
//  SettingsTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct SettingsTabView: View {
    @Bindable var state: AppState
    
    @State private var showPublicKeySheet = false
    @State private var showRotateKeyAlert = false
    @State private var copiedPublicKey = false
    @State private var copiedTunnelCommand = false
    @State private var publicKeyForSheet = ""
    @State private var sshConfig: SSHTunnelConfig = .default
    @State private var publicKeyLoadError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t(.settingsServerConnection)) {
                    let info = AppState.serverURLInfo(state.serverURL)

                    TextField(L10n.t(.settingsAddress), text: $state.serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    TextField(L10n.t(.settingsUsername), text: $state.username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField(L10n.t(.settingsPassword), text: $state.password)
                        .textContentType(.password)

                    if let scheme = info.scheme {
                        let shouldWarnInsecureHTTP = scheme == "http" && !sshConfig.isEnabled
                        HStack(spacing: 4) {
                            LabeledContent(L10n.t(.settingsScheme), value: scheme.uppercased())
                                .foregroundStyle(shouldWarnInsecureHTTP ? .red : .secondary)
                            if shouldWarnInsecureHTTP {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.red)
                                    .help(schemeHelpText(info: info))
                            }
                        }
                    }

                    HStack {
                        Text(L10n.t(.settingsStatus))
                        Spacer()
                        if state.isConnected {
                            Label(L10n.t(.settingsConnected), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(L10n.t(.settingsDisconnected), systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    if let error = state.connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(L10n.t(.settingsTestConnection)) {
                        Task { await state.refresh() }
                    }
                    .buttonStyle(.plain)
                }

                Section(L10n.t(.settingsProject)) {
                    Picker(L10n.t(.settingsProject), selection: Binding(
                        get: { state.selectedProjectWorktree ?? "" },
                        set: { state.selectedProjectWorktree = $0.isEmpty ? nil : $0 }
                    )) {
                        Text(L10n.t(.settingsProjectServerDefault)).tag("")
                        ForEach(state.projects) { project in
                            Text(project.displayName).tag(project.worktree)
                        }
                        Text(L10n.t(.settingsProjectCustomPath)).tag(AppState.customProjectSentinel)
                    }
                    .disabled(!state.isConnected || state.isLoadingProjects)

                    if state.selectedProjectWorktree == AppState.customProjectSentinel {
                        TextField(L10n.t(.settingsProjectCustomPathPlaceholder), text: $state.customProjectPath)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .onChange(of: state.customProjectPath) { _, _ in
                                Task { await state.refreshSessions() }
                            }
                    }
                }
                .onChange(of: state.selectedProjectWorktree) { _, _ in
                    Task { await state.refreshSessions() }
                }

                Section {
                    Toggle(L10n.t(.settingsEnableSshTunnel), isOn: $sshConfig.isEnabled)
                        .onChange(of: sshConfig.isEnabled) { _, newValue in
                            state.sshTunnelManager.config.isEnabled = newValue
                            if newValue {
                                _ = try? state.sshTunnelManager.generateOrGetPublicKey()
                                Task {
                                    state.sshTunnelManager.disconnect()
                                    await state.sshTunnelManager.connect()
                                }
                            } else {
                                state.sshTunnelManager.disconnect()
                            }
                        }

                    Text(L10n.t(.settingsAfterEnableSshTip))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if sshConfig.isEnabled {
                        TextField(L10n.t(.settingsVpsHost), text: $sshConfig.host)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .onChange(of: sshConfig.host) { _, newValue in
                                state.sshTunnelManager.config.host = newValue
                                reconnectSSHTunnelIfNeeded()
                            }
                        
                        HStack {
                            Text(L10n.t(.settingsSshPort))
                            Spacer()
                            TextField("", value: $sshConfig.port, formatter: NumberFormatter())
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: sshConfig.port) { _, newValue in
                                    state.sshTunnelManager.config.port = newValue
                                    reconnectSSHTunnelIfNeeded()
                                }
                        }
                        
                        TextField(L10n.t(.settingsUsername), text: $sshConfig.username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .onChange(of: sshConfig.username) { _, newValue in
                                state.sshTunnelManager.config.username = newValue
                                reconnectSSHTunnelIfNeeded()
                            }
                        
                        HStack {
                            Text(L10n.t(.settingsVpsPort))
                            Spacer()
                            TextField("", value: $sshConfig.remotePort, formatter: NumberFormatter())
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: sshConfig.remotePort) { _, newValue in
                                    state.sshTunnelManager.config.remotePort = newValue
                                    reconnectSSHTunnelIfNeeded()
                                }
                        }

                        HStack {
                            Spacer(minLength: 0)
                            Button(L10n.t(.settingsSetServerAddress)) {
                                state.serverURL = "127.0.0.1:4096"
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            Spacer(minLength: 0)
                        }

                        HStack {
                            Text(L10n.t(.settingsStatus))
                            Spacer()
                            switch state.sshTunnelManager.status {
                            case .disconnected:
                                Label(L10n.t(.settingsDisconnected), systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            case .connecting:
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(L10n.t(.settingsConnecting))
                                }
                            case .connected:
                                Label(L10n.t(.settingsConnected), systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .error(let msg):
                                Text(msg)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.t(.settingsKnownHost))
                            Spacer()
                            Text(state.sshTunnelManager.trustedHostFingerprint ?? L10n.t(.settingsUntrusted))
                                .font(.caption.monospaced())
                                .foregroundStyle(state.sshTunnelManager.trustedHostFingerprint == nil ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                        }

                        Button(L10n.t(.settingsResetTrustedHost)) {
                            state.sshTunnelManager.clearTrustedHost()
                        }
                        .buttonStyle(.plain)
                        .disabled(state.sshTunnelManager.trustedHostFingerprint == nil)

                    }

                    HStack(spacing: 12) {
                        Button {
                            do {
                                let key = try state.sshTunnelManager.generateOrGetPublicKey()
                                UIPasteboard.general.string = key
                                copiedPublicKey = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedPublicKey = false
                                }
                            } catch {
                                copiedPublicKey = false
                            }
                        } label: {
                            Label(copiedPublicKey ? L10n.t(.settingsPublicKeyCopied) : L10n.t(.settingsCopyPublicKey), systemImage: copiedPublicKey ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button(L10n.t(.settingsViewPublicKey)) {
                            loadPublicKeyForSheet()
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                    }

                    if let command = state.sshTunnelManager.reverseTunnelCommand {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t(.settingsReverseTunnelCommand))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(command)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = command
                                copiedTunnelCommand = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedTunnelCommand = false
                                }
                            } label: {
                                Label(copiedTunnelCommand ? L10n.t(.settingsCommandCopied) : L10n.t(.settingsCopyCommand), systemImage: copiedTunnelCommand ? "checkmark" : "terminal")
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text(L10n.t(.settingsNoTunnelCommand))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.t(.settingsSshTunnel))
                } footer: {
                    Text(L10n.t(.settingsSshTunnelHelp))
                        .font(.caption)
                }

                Section(L10n.t(.settingsAppearance)) {
                    Picker(L10n.t(.settingsTheme), selection: $state.themePreference) {
                        Text(L10n.t(.settingsAutoTheme)).tag("auto")
                        Text(L10n.t(.settingsLightTheme)).tag("light")
                        Text(L10n.t(.settingsDarkTheme)).tag("dark")
                    }
                    
                    Toggle(L10n.t(.settingsShowArchivedSessions), isOn: $state.showArchivedSessions)
                }

                Section(L10n.t(.settingsSpeechRecognition)) {
                    TextField(L10n.t(.settingsAiBuilderBaseURL), text: $state.aiBuilderBaseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    SecureField(L10n.t(.settingsAiBuilderToken), text: $state.aiBuilderToken)
                        .textContentType(.password)

                    TextField(L10n.t(.settingsCustomPrompt), text: $state.aiBuilderCustomPrompt, axis: .vertical)
                        .lineLimit(3...6)

                    TextField(L10n.t(.settingsTerminology), text: $state.aiBuilderTerminology)
                        .textContentType(.none)
                        .autocapitalization(.none)

                    HStack {
                        Button {
                            Task { await state.testAIBuilderConnection() }
                        } label: {
                            if state.isTestingAIBuilderConnection {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                    Text(L10n.t(.settingsTesting))
                                }
                            } else {
                                Text(L10n.t(.settingsTestConnection))
                            }
                        }
                        .disabled(
                            state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || state.isTestingAIBuilderConnection
                        )
                        Spacer()
                        if state.aiBuilderConnectionOK {
                            Label(L10n.t(.commonOk), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if let err = state.aiBuilderConnectionError {
                            Text(err)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section(L10n.t(.settingsAbout)) {
                    if let version = state.serverVersion {
                        LabeledContent(L10n.t(.settingsServerVersion), value: version)
                    }
                }
            }
            .navigationTitle(L10n.t(.settingsTitle))
            .onAppear {
                sshConfig = state.sshTunnelManager.config
                _ = try? state.sshTunnelManager.generateOrGetPublicKey()
                reconnectSSHTunnelIfNeeded(force: false)
            }
            .sheet(isPresented: $showPublicKeySheet) {
                PublicKeySheet(
                    publicKey: publicKeyForSheet,
                    onRotate: {
                        showRotateKeyAlert = true
                    }
                )
            }
            .alert(L10n.t(.settingsRotateKeyTitle), isPresented: $showRotateKeyAlert) {
                Button(L10n.t(.commonCancel), role: .cancel) {}
                Button(L10n.t(.settingsRotate), role: .destructive) {
                    do {
                        let newKey = try state.sshTunnelManager.rotateKey()
                        publicKeyForSheet = newKey
                        UIPasteboard.general.string = newKey
                        copiedPublicKey = true
                    } catch {
                        // Error handled by manager
                    }
                }
            } message: {
                Text(L10n.t(.settingsRotateKeyPrompt))
            }
            .alert(L10n.t(.settingsPublicKeyErrorTitle), isPresented: Binding(
                get: { publicKeyLoadError != nil },
                set: { newValue in
                    if !newValue { publicKeyLoadError = nil }
                }
            )) {
                Button(L10n.t(.commonOk), role: .cancel) {}
            } message: {
                Text(publicKeyLoadError ?? L10n.t(.settingsPublicKeyCopyFailed))
            }
        }
    }

    private func reconnectSSHTunnelIfNeeded(force: Bool = true) {
        guard sshConfig.isEnabled else { return }
        if !force {
            if case .connected = state.sshTunnelManager.status {
                return
            }
        }
        Task {
            state.sshTunnelManager.disconnect()
            await state.sshTunnelManager.connect()
        }
    }

    private func loadPublicKeyForSheet() {
        do {
            let key = try state.sshTunnelManager.generateOrGetPublicKey().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw SSHError.keyNotFound
            }
            publicKeyForSheet = key
            showPublicKeySheet = true
        } catch {
            publicKeyForSheet = ""
            publicKeyLoadError = error.localizedDescription
        }
    }

    private func schemeHelpText(info: AppState.ServerURLInfo) -> String {
        L10n.helpForURLScheme(info.isLocal)
    }
}

struct PublicKeySheet: View {
    let publicKey: String
    let onRotate: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(publicKey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text(L10n.t(.settingsPublicKeyTitle))
                } footer: {
                    Text(L10n.t(.settingsPublicKeyFooter))
                        .font(.caption)
                }

                Button {
                    UIPasteboard.general.string = publicKey
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? L10n.t(.settingsPublicKeyCopied) : L10n.t(.settingsCopyToClipboard))
                    }
                }
                .disabled(publicKey.isEmpty)

                Button(L10n.t(.settingsPublicKeyRotate), role: .destructive) {
                    onRotate()
                    dismiss()
                }
                .disabled(publicKey.isEmpty)
            }
            .navigationTitle(L10n.t(.settingsPublicKeyTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.appDone)) { dismiss() }
                }
            }
        }
    }
}
