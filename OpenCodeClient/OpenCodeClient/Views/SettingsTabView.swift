//
//  SettingsTabView.swift
//  OpenCodeClient
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsTabView: View {
    @Bindable var state: AppState
    @Binding var isCarModeEnabled: Bool
    @FocusState private var isServerAddressFocused: Bool

    @State private var showPublicKeySheet = false
    @State private var showRotateKeyAlert = false
    @State private var copiedPublicKey = false
    @State private var publicKeyForSheet = ""
    @State private var publicKeyLoadError: String?

    private var supportsCarMode: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HostProfilesView(state: state)
                    } label: {
                        CurrentHostSummaryView(state: state)
                    }
                    .accessibilityIdentifier("settings-current-host")

                    Button(L10n.t(.settingsTestConnection)) {
                        Task { await state.refresh() }
                    }
                    .accessibilityIdentifier("settings-test-connection")

                    if let diagnostic = state.connectionDiagnostic {
                        DiagnosticSummaryView(diagnostic: diagnostic)
                    } else if let error = state.connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(L10n.t(.hostCurrent))
                } footer: {
                    Text(L10n.t(.hostCurrentFooter))
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

                if let warning = state.projectMismatchWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section(L10n.t(.settingsAppearance)) {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        Text(L10n.t(.settingsTheme))
                        Picker(L10n.t(.settingsTheme), selection: $state.themePreference) {
                            Text(L10n.t(.settingsAutoTheme)).tag("auto")
                            Text(L10n.t(.settingsLightTheme)).tag("light")
                            Text(L10n.t(.settingsDarkTheme)).tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        Text(L10n.t(.settingsLanguage))
                        Picker(L10n.t(.settingsLanguage), selection: $state.languagePreference) {
                            Text(L10n.t(.settingsLanguageSystem)).tag(L10n.LanguagePreference.system)
                            Text(L10n.t(.settingsLanguageEnglish)).tag(L10n.LanguagePreference.en)
                            Text(L10n.t(.settingsLanguageChinese)).tag(L10n.LanguagePreference.zh)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                Section {
                    if supportsCarMode {
                        HStack {
                            Text(L10n.t(.settingsCarMode))
                            Spacer()
                            Toggle("", isOn: $isCarModeEnabled)
                                .labelsHidden()
                                .accessibilityLabel(L10n.t(.settingsCarMode))
                                .accessibilityIdentifier("settings-car-mode-toggle")
                        }
                    }

                    Text(L10n.t(.settingsAIUsageDashboard))
                        .font(.subheadline.weight(.semibold))

                    TextField(L10n.t(.settingsAIUsageDashboardURL), text: $state.aiUsageDashboardURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .accessibilityIdentifier("settings-ai-usage-url")

                    HStack {
                        Button(L10n.t(.settingsTestConnection)) {
                            Task { await state.refreshAIUsageQuotas(force: true) }
                        }
                        .disabled(!state.isAIUsageQuotaConfigured || {
                            if case .loading = state.aiUsageQuotaState { return true }
                            return false
                        }())
                        .accessibilityIdentifier("settings-ai-usage-test")

                        Spacer()
                        if case .loading = state.aiUsageQuotaState {
                            ProgressView()
                        } else if state.aiUsageQuotaTestOK {
                            Label(L10n.t(.commonOk), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(DesignColors.Semantic.success)
                        } else if state.aiUsageQuotaError != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DesignColors.Semantic.warning)
                        }
                    }

                    if let error = state.aiUsageQuotaError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(L10n.t(.settingsExperimentalFeatures))
                } footer: {
                    Text(L10n.t(.settingsAIUsageDashboardFooter))
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
                                .foregroundStyle(DesignColors.Semantic.success)
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
                #if !os(visionOS)
                _ = try? state.sshTunnelManager.generateOrGetPublicKey()
                #endif
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
            .alert(
                L10n.t(.settingsTrustHostKeyTitle),
                isPresented: Binding(
                    get: { state.pendingSSHHostKeyMismatch != nil },
                    set: { if !$0 { state.dismissPendingSSHHostKeyMismatch() } }
                ),
                presenting: state.pendingSSHHostKeyMismatch
            ) { _ in
                Button(L10n.t(.commonCancel), role: .cancel) {
                    state.dismissPendingSSHHostKeyMismatch()
                }
                Button(L10n.t(.settingsTrustHostKeyConfirm)) {
                    Task { await state.trustPendingSSHHostKeyAndReconnect() }
                }
            } message: { mismatch in
                Text(L10n.t(
                    .settingsTrustHostKeyMessage,
                    mismatch.host,
                    mismatch.port,
                    mismatch.expectedFingerprint,
                    mismatch.presentedFingerprint
                ))
            }
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
        L10n.helpForURLScheme(isLocal: info.isLocal, isTailscale: info.isTailscale)
    }

    /// Normalizes server URL in place: fix malformed host://host:port, then ensure http:// prefix.
    /// User sees the explicit URL in the text field, avoiding iOS URL parsing quirks.
    private func normalizeServerURLInPlace(state: AppState) {
        var current = state.serverURL
        if let corrected = AppState.correctMalformedServerURL(current) {
            current = corrected
        }
        if let withScheme = AppState.ensureServerURLHasScheme(current) {
            current = withScheme
        }
        if current != state.serverURL {
            state.serverURL = current
        }
    }
}

struct SSHTunnelSetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.t(.settingsSshSetupGuideBody))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle(L10n.t(.settingsSshSetupGuideTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.appDone)) { dismiss() }
                }
            }
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
