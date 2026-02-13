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
    @State private var publicKeyForSheet = ""
    @State private var sshConfig: SSHTunnelConfig = .default

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection") {
                    let info = AppState.serverURLInfo(state.serverURL)

                    TextField("Address", text: $state.serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    TextField("Username", text: $state.username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $state.password)
                        .textContentType(.password)

                    if let scheme = info.scheme {
                        HStack(spacing: 4) {
                            LabeledContent("Scheme", value: scheme.uppercased())
                                .foregroundStyle(scheme == "http" ? .red : .secondary)
                            if scheme == "http" {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.red)
                                    .help(schemeHelpText(info: info))
                            }
                        }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        if state.isConnected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Disconnected", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    if let error = state.connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Test Connection") {
                        Task { await state.refresh() }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Toggle("Enable SSH Tunnel", isOn: $sshConfig.isEnabled)
                        .onChange(of: sshConfig.isEnabled) { _, newValue in
                            state.sshTunnelManager.config.isEnabled = newValue
                            if newValue {
                                Task { await state.sshTunnelManager.connect() }
                            } else {
                                state.sshTunnelManager.disconnect()
                            }
                        }

                    if sshConfig.isEnabled {
                        TextField("VPS Host", text: $sshConfig.host)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .onChange(of: sshConfig.host) { _, newValue in
                                state.sshTunnelManager.config.host = newValue
                            }
                        
                        HStack {
                            Text("SSH Port")
                            Spacer()
                            TextField("", value: $sshConfig.port, formatter: NumberFormatter())
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: sshConfig.port) { _, newValue in
                                    state.sshTunnelManager.config.port = newValue
                                }
                        }
                        
                        TextField("Username", text: $sshConfig.username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .onChange(of: sshConfig.username) { _, newValue in
                                state.sshTunnelManager.config.username = newValue
                            }
                        
                        HStack {
                            Text("VPS Port")
                            Spacer()
                            TextField("", value: $sshConfig.remotePort, formatter: NumberFormatter())
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: sshConfig.remotePort) { _, newValue in
                                    state.sshTunnelManager.config.remotePort = newValue
                                }
                        }

                        Button("Set Server Address to 127.0.0.1:4096") {
                            state.serverURL = "127.0.0.1:4096"
                        }
                        .buttonStyle(.plain)

                        HStack {
                            Text("Status")
                            Spacer()
                            switch state.sshTunnelManager.status {
                            case .disconnected:
                                Label("Disconnected", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            case .connecting:
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Connecting...")
                                }
                            case .connected:
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .error(let msg):
                                Text(msg)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Known Host")
                            Spacer()
                            Text(state.sshTunnelManager.trustedHostFingerprint ?? "Untrusted")
                                .font(.caption.monospaced())
                                .foregroundStyle(state.sshTunnelManager.trustedHostFingerprint == nil ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                        }

                        Button("Reset Trusted Host") {
                            state.sshTunnelManager.clearTrustedHost()
                        }
                        .buttonStyle(.plain)
                        .disabled(state.sshTunnelManager.trustedHostFingerprint == nil)

                    }

                    Button("View / Copy Public Key") {
                        do {
                            publicKeyForSheet = try state.sshTunnelManager.generateOrGetPublicKey()
                            showPublicKeySheet = true
                        } catch {
                            publicKeyForSheet = ""
                            // Error handled by manager (status)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("SSH Tunnel")
                } footer: {
                    Text("Forwards iOS 127.0.0.1:4096 to VPS 127.0.0.1:<VPS Port>. 1) View/copy your public key and add it to the VPS's ~/.ssh/authorized_keys. 2) First connect uses TOFU to trust host key; later connections must match. 3) Set Server Address to 127.0.0.1:4096.")
                        .font(.caption)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $state.themePreference) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section("Speech Recognition") {
                    TextField("AI Builder Base URL", text: $state.aiBuilderBaseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    SecureField("AI Builder Token", text: $state.aiBuilderToken)
                        .textContentType(.password)

                    TextField("Custom Prompt", text: $state.aiBuilderCustomPrompt, axis: .vertical)
                        .lineLimit(3...6)

                    TextField("Terminology (comma-separated)", text: $state.aiBuilderTerminology)
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
                                    Text("Testing...")
                                }
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(
                            state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || state.isTestingAIBuilderConnection
                        )
                        Spacer()
                        if state.aiBuilderConnectionOK {
                            Label("OK", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if let err = state.aiBuilderConnectionError {
                            Text(err)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section("About") {
                    if let version = state.serverVersion {
                        LabeledContent("Server Version", value: version)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                sshConfig = state.sshTunnelManager.config
            }
            .sheet(isPresented: $showPublicKeySheet) {
                PublicKeySheet(
                    publicKey: publicKeyForSheet,
                    onRotate: {
                        showRotateKeyAlert = true
                    }
                )
            }
            .alert("Rotate SSH Key?", isPresented: $showRotateKeyAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Rotate", role: .destructive) {
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
                Text("This will generate a new key pair. You'll need to update the public key on your VPS.")
            }
        }
    }

    private func schemeHelpText(info: AppState.ServerURLInfo) -> String {
        if info.isLocal {
            return "LAN: HTTP allowed. Recommended only on trusted networks. Warning: HTTP is insecure."
        } else {
            return "WAN: HTTPS required (HTTP will be blocked). Warning: HTTP is insecure."
        }
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
                    Text("Your Public Key")
                } footer: {
                    Text("Add this key to your VPS: ~/.ssh/authorized_keys")
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
                        Text(copied ? "Copied!" : "Copy to Clipboard")
                    }
                }
                .disabled(publicKey.isEmpty)

                Button("Rotate Key", role: .destructive) {
                    onRotate()
                    dismiss()
                }
                .disabled(publicKey.isEmpty)
            }
            .navigationTitle("SSH Public Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
