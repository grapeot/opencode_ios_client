import SwiftUI

struct CurrentHostSummaryView: View {
    @Bindable var state: AppState

    var body: some View {
        let profile = state.currentHostProfile
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile?.displayName ?? L10n.t(.hostNoHost))
                    .font(.headline)
                Spacer()
                Text(profile?.transport.label ?? "")
                    .font(.caption)
                    .foregroundStyle(DesignColors.Brand.primary)
            }
            Text(profile?.connectionSummary ?? L10n.t(.hostAddToConnect))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack {
                if state.isConnected {
                    Label(L10n.t(.settingsConnected), systemImage: "checkmark.circle")
                } else {
                    Label(L10n.t(.settingsDisconnected), systemImage: "xmark.circle")
                }
                Spacer()
                if let version = state.serverVersion {
                    Text(version)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct HostProfilesView: View {
    @Bindable var state: AppState
    @State private var editorMode: HostProfileEditorMode?
    @State private var publicKeyCopied = false
    @State private var errorMessage: String?
    @State private var showRotateKeyAlert = false

    var body: some View {
        Form {
            Section {
                if let current = state.currentHostProfile {
                    CurrentHostCard(state: state, profile: current)
                        .accessibilityIdentifier("hosts-current-card")
                }
            } header: {
                Text(L10n.t(.hostCurrent))
            } footer: {
                Text(L10n.t(.hostCurrentFooter))
            }

            Section(L10n.t(.hostHosts)) {
                ForEach(state.hostProfiles) { profile in
                    NavigationLink {
                        HostProfileDetailView(state: state, profileID: profile.id) { selected in
                            editorMode = .edit(selected)
                        }
                    } label: {
                        HostProfileRow(state: state, profile: profile)
                    }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                do {
                                    try state.deleteHostProfile(profile)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            } label: {
                                Label(L10n.t(.hostDelete), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                state.duplicateHostProfile(profile)
                            } label: {
                                Label(L10n.t(.hostDuplicate), systemImage: "plus.square.on.square")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            Button(L10n.t(.hostEdit)) { editorMode = .edit(profile) }
                            Button(L10n.t(.hostDuplicate)) { state.duplicateHostProfile(profile) }
                            Button(L10n.t(.hostDelete), role: .destructive) {
                                do { try state.deleteHostProfile(profile) } catch { errorMessage = error.localizedDescription }
                            }
                        }
                }

                Button {
                    editorMode = .add
                } label: {
                    Label(L10n.t(.hostAdd), systemImage: "plus.circle")
                }
                .accessibilityIdentifier("hosts-add-host")
            }
            .accessibilityIdentifier("hosts-list-section")

            #if !os(visionOS)
            Section(L10n.t(.hostDeviceKey)) {
                Button {
                    copyPublicKey()
                } label: {
                    Label(publicKeyCopied ? L10n.t(.settingsPublicKeyCopied) : L10n.t(.hostCopyDevicePublicKey), systemImage: publicKeyCopied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("hosts-copy-device-public-key")
                Button(role: .destructive) {
                    showRotateKeyAlert = true
                } label: {
                    Label(L10n.t(.settingsPublicKeyRotate), systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("hosts-rotate-device-public-key")
                Text(L10n.t(.hostDeviceKeyFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .navigationTitle(L10n.t(.hostHosts))
        .sheet(item: $editorMode) { mode in
            HostProfileEditorView(state: state, mode: mode)
        }
        .alert(L10n.t(.hostErrorTitle), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.t(.commonOk), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(L10n.t(.settingsRotateKeyTitle), isPresented: $showRotateKeyAlert) {
            Button(L10n.t(.commonCancel), role: .cancel) {}
            Button(L10n.t(.settingsRotate), role: .destructive) {
                rotatePublicKey()
            }
        } message: {
            Text(L10n.t(.settingsRotateKeyPrompt))
        }
    }

    private func copyPublicKey() {
        #if !os(visionOS)
        do {
            let key = try state.sshTunnelManager.generateOrGetPublicKey()
            UIPasteboard.general.string = key
            publicKeyCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { publicKeyCopied = false }
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    private func rotatePublicKey() {
        #if !os(visionOS)
        do {
            let key = try state.sshTunnelManager.rotateKey()
            UIPasteboard.general.string = key
            publicKeyCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { publicKeyCopied = false }
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }
}

private struct CurrentHostCard: View {
    @Bindable var state: AppState
    let profile: HostProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(profile.displayName)
                    .font(.headline)
                Spacer()
                Label(profile.transport.label, systemImage: profile.transport == .sshTunnel ? "terminal" : "network")
                    .font(.caption)
                    .foregroundStyle(DesignColors.Brand.primary)
            }
            Text(profile.connectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if state.isConnected {
                    Label(L10n.t(.settingsConnected), systemImage: "checkmark.circle")
                } else {
                    Label(L10n.t(.settingsDisconnected), systemImage: "xmark.circle")
                }
                Spacer()
                Button(L10n.t(.settingsTestConnection)) {
                    Task { await state.refresh() }
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let diagnostic = state.connectionDiagnostic, diagnostic.hostProfileID == profile.id {
                DiagnosticSummaryView(diagnostic: diagnostic)
            } else if let error = state.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DiagnosticSummaryView: View {
    let diagnostic: ConnectionDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(diagnostic.phase.label, systemImage: diagnostic.phase == .connected ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(diagnostic.phase == .connected ? DesignColors.Semantic.success : .orange)
            Text(diagnostic.message)
                .font(.caption)
                .foregroundStyle(diagnostic.phase == .connected ? Color.secondary : Color.red)
            if let recoveryHint = diagnostic.recoveryHint {
                Text(recoveryHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("host-connection-diagnostic")
    }
}

private struct HostProfileRow: View {
    @Bindable var state: AppState
    let profile: HostProfile

    private var isCurrent: Bool { profile.id == state.currentHostProfileID }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isCurrent ? DesignColors.Brand.primary : Color.clear)
                .frame(width: 3, height: 42)
            Image(systemName: profile.transport == .sshTunnel ? "terminal" : "network")
                .frame(width: 24)
                .foregroundStyle(isCurrent ? DesignColors.Brand.primary : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .foregroundStyle(.primary)
                Text(profile.connectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(lastUsedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(DesignColors.Brand.primary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("host-profile-\(profile.id.uuidString)")
    }

    private var lastUsedText: String {
        guard let lastUsedAt = profile.lastUsedAt,
              lastUsedAt.timeIntervalSince1970 > 60 * 60 * 24 * 365 else {
            return L10n.t(.hostNeverConnected)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.currentLocale
        formatter.unitsStyle = .abbreviated
        return L10n.t(.hostLastUsed, formatter.localizedString(for: lastUsedAt, relativeTo: Date()))
    }
}

private struct HostProfileDetailView: View {
    @Bindable var state: AppState
    let profileID: UUID
    let onEdit: (HostProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copiedHostConfig = false
    @State private var copiedPublicKey = false
    @State private var errorMessage: String?

    private var profile: HostProfile? {
        state.hostProfiles.first { $0.id == profileID }
    }

    private var isCurrent: Bool {
        profileID == state.currentHostProfileID
    }

    var body: some View {
        Form {
            if let profile {
                Section(L10n.t(.hostOverview)) {
                    LabeledContent(L10n.t(.hostName), value: profile.displayName)
                    LabeledContent(L10n.t(.hostTransport), value: profile.transport.label)
                    LabeledContent(L10n.t(.hostOpenCodeURL), value: profile.transport == .sshTunnel ? L10n.t(.hostManagedBySSHTunnel) : profile.serverURL)
                    LabeledContent(L10n.t(.hostStatus), value: isCurrent ? L10n.t(.hostCurrent) : L10n.t(.hostSavedHost))
                }
                .accessibilityIdentifier("host-detail-overview")

                if profile.transport == .sshTunnel, let ssh = profile.ssh {
                    Section(L10n.t(.hostSSHGateway)) {
                        HostDetailField(title: L10n.t(.hostGatewayHost), value: ssh.host, accessibilityID: "host-detail-ssh-host")
                        HostDetailField(title: L10n.t(.hostSSHPort), value: String(ssh.port), accessibilityID: "host-detail-ssh-port")
                        HostDetailField(title: L10n.t(.hostSSHUsername), value: ssh.username, accessibilityID: "host-detail-ssh-username")
                        HostDetailField(title: L10n.t(.hostAssignedRemotePort), value: String(ssh.remotePort), accessibilityID: "host-detail-ssh-remote-port")
                    }
                    .accessibilityIdentifier("host-detail-ssh-gateway")
                }

                if let diagnostic = state.connectionDiagnostic, diagnostic.hostProfileID == profile.id {
                    Section(L10n.t(.hostConnectionDiagnostics)) {
                        DiagnosticSummaryView(diagnostic: diagnostic)
                    }
                    .accessibilityIdentifier("host-detail-diagnostics")
                }

                Section {
                    if !isCurrent {
                        Button(L10n.t(.hostUseThisHost)) {
                            Task {
                                await state.switchHostProfile(to: profile.id)
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("host-detail-use-this-host")
                    }
                    Button(L10n.t(.settingsTestConnection)) {
                        if !isCurrent {
                            Task {
                                await state.switchHostProfile(to: profile.id)
                                await state.refresh()
                            }
                        } else {
                            Task { await state.refresh() }
                        }
                    }
                    Button(L10n.t(.hostEdit)) { onEdit(profile) }
                        .accessibilityIdentifier("host-detail-edit")
                    Button(copiedHostConfig ? L10n.t(.hostConfigCopied) : L10n.t(.hostCopyConfigJSON)) {
                        copyHostConfig(profile)
                    }
                    .accessibilityIdentifier("host-detail-copy-config")
                    #if !os(visionOS)
                    if profile.transport == .sshTunnel {
                        Button(copiedPublicKey ? L10n.t(.settingsPublicKeyCopied) : L10n.t(.hostCopyDevicePublicKey)) {
                            copyPublicKey()
                        }
                        .accessibilityIdentifier("host-detail-copy-device-public-key")
                    }
                    #endif
                }
            } else {
                Text(L10n.t(.hostNotFound))
            }
        }
        .navigationTitle(profile?.displayName ?? L10n.t(.hostTitle))
        .alert(L10n.t(.hostErrorTitle), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.t(.commonOk), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func copyHostConfig(_ profile: HostProfile) {
        do {
            let json = try state.hostConfigJSON(for: profile)
            #if !os(visionOS)
            UIPasteboard.general.string = json
            #endif
            copiedHostConfig = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedHostConfig = false }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyPublicKey() {
        #if !os(visionOS)
        do {
            UIPasteboard.general.string = try state.sshTunnelManager.generateOrGetPublicKey()
            copiedPublicKey = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedPublicKey = false }
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }
}

private struct HostDetailField: View {
    let title: String
    let value: String
    let accessibilityID: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityID)
    }
}

enum HostProfileEditorMode: Identifiable {
    case add
    case edit(HostProfile)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let profile): return profile.id.uuidString
        }
    }
}

struct HostProfileEditorView: View {
    @Bindable var state: AppState
    let mode: HostProfileEditorMode
    @Environment(\.dismiss) private var dismiss

    @State private var profile: HostProfile
    @State private var password: String
    @State private var importText = ""
    @State private var errorMessage: String?
    @State private var publicKeyCopied = false

    init(state: AppState, mode: HostProfileEditorMode) {
        self.state = state
        self.mode = mode
        let initial: HostProfile
        switch mode {
        case .add:
            initial = HostProfile(name: "", transport: .direct, serverURL: "", basicAuth: nil, ssh: nil)
        case .edit(let profile):
            initial = profile
        }
        _profile = State(initialValue: initial)
        _password = State(initialValue: initial.basicAuth.flatMap { KeychainHelper.load(forKey: $0.keychainPasswordID) } ?? "")
        _importText = State(initialValue: Self.uiTestImportJSON)
    }

    var body: some View {
        NavigationStack {
            Form {
                if case .add = mode {
                    Section {
                        TextEditor(text: $importText)
                            .frame(minHeight: 80)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("host-import-json")
                        Button {
                            do {
                                profile = try state.importHostProfile(from: importText)
                                importText = ""
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Label(L10n.t(.hostImportConfig), systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("host-import-config")
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } footer: {
                        Text(L10n.t(.hostImportFooter))
                    }
                }

                Section {
                    Picker(L10n.t(.hostConnectionType), selection: $profile.transport) {
                        ForEach(HostTransport.allCases) { transport in
                            Text(transport.label).tag(transport)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("host-transport-picker")
                    .onChange(of: profile.transport) { _, newValue in
                        if newValue == .sshTunnel {
                            profile.serverURL = APIClient.defaultServer
                            if profile.ssh == nil { profile.ssh = .default }
                        } else {
                            profile.ssh = nil
                        }
                    }
                } footer: {
                    Text(L10n.t(.hostTransportFooter))
                }

                Section(L10n.t(.hostTitle)) {
                    TextField(L10n.t(.hostName), text: $profile.name)
                        .accessibilityIdentifier("host-name")
                    if profile.transport == .direct {
                        TextField(L10n.t(.hostOpenCodeURL), text: $profile.serverURL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("host-server-url")
                    } else {
                        LabeledContent(L10n.t(.hostOpenCodeURL)) {
                            Text(L10n.t(.hostManagedBySSHTunnel))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if profile.transport == .sshTunnel {
                    Section {
                        TextField(L10n.t(.hostGatewayHost), text: sshHostBinding)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("host-ssh-gateway")
                        LabeledNumberField(title: L10n.t(.hostSSHPort), value: sshPortBinding, accessibilityID: "host-ssh-port")
                        TextField(L10n.t(.hostSSHUsername), text: sshUsernameBinding)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("host-ssh-username")
                        LabeledNumberField(title: L10n.t(.hostAssignedRemotePort), value: sshRemotePortBinding, accessibilityID: "host-ssh-remote-port")
                    } header: {
                        Text(L10n.t(.hostSSHGateway))
                    } footer: {
                        Text(L10n.t(.hostSSHGatewayFooter))
                    }
                    .accessibilityIdentifier("host-ssh-gateway-section")

                    #if !os(visionOS)
                    Section(L10n.t(.hostDeviceKey)) {
                        Button {
                            copyPublicKey()
                        } label: {
                            Label(publicKeyCopied ? L10n.t(.settingsPublicKeyCopied) : L10n.t(.hostCopyDevicePublicKey), systemImage: publicKeyCopied ? "checkmark" : "doc.on.doc")
                        }
                        .accessibilityIdentifier("host-editor-copy-device-public-key")
                        Text(L10n.t(.hostDeviceKeySendFooter))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }

                Section(L10n.t(.hostBasicAuth)) {
                    TextField(L10n.t(.settingsUsername), text: basicAuthUsernameBinding)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                    SecureField(L10n.t(.settingsPassword), text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button(L10n.t(.settingsTestConnection)) {
                        save(makeCurrent: true)
                        Task { await state.refresh() }
                    }
                    .disabled(!canSave)
                    Text(L10n.t(.hostSaveHelp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isEditing ? L10n.t(.hostEditTitle) : L10n.t(.hostAddTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t(.commonCancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.hostSave)) {
                        save(makeCurrent: true)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("host-save")
                }
            }
            .alert(L10n.t(.hostErrorTitle), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(L10n.t(.commonOk), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private static var uiTestImportJSON: String {
        guard ProcessInfo.processInfo.arguments.contains("UITEST_HOST_IMPORT_JSON_PREFILL") else { return "" }
        return #"{"version":1,"name":"Imported SSH","transport":"sshTunnel","ssh":{"host":"gateway.example.invalid","port":8006,"username":"opencode","remotePort":19001}}"#
    }

    private var canSave: Bool {
        let nameOK = !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch profile.transport {
        case .direct:
            return nameOK && !profile.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sshTunnel:
            return nameOK && (profile.ssh?.isValid ?? false)
        }
    }

    private var basicAuthUsernameBinding: Binding<String> {
        Binding {
            profile.basicAuth?.username ?? ""
        } set: { newValue in
            if newValue.isEmpty && password.isEmpty {
                profile.basicAuth = nil
            } else {
                let passwordID = profile.basicAuth?.keychainPasswordID ?? AppState.passwordKeychainID(for: profile.id)
                profile.basicAuth = BasicAuthConfig(username: newValue, keychainPasswordID: passwordID)
            }
        }
    }

    private var sshHostBinding: Binding<String> {
        Binding { profile.ssh?.host ?? "" } set: { updateSSH { $0.host = $1 }($0) }
    }

    private var sshUsernameBinding: Binding<String> {
        Binding { profile.ssh?.username ?? "opencode" } set: { updateSSH { $0.username = $1 }($0) }
    }

    private var sshPortBinding: Binding<Int> {
        Binding { profile.ssh?.port ?? 8006 } set: { newValue in updateSSH { $0.port = newValue } }
    }

    private var sshRemotePortBinding: Binding<Int> {
        Binding { profile.ssh?.remotePort ?? 19001 } set: { newValue in updateSSH { $0.remotePort = newValue } }
    }

    private func updateSSH(_ edit: (inout SSHTunnelConfig) -> Void) {
        var ssh = profile.ssh ?? .default
        ssh.isEnabled = true
        edit(&ssh)
        profile.ssh = ssh
        profile.serverURL = APIClient.defaultServer
    }

    private func updateSSH(_ edit: @escaping (inout SSHTunnelConfig, String) -> Void) -> (String) -> Void {
        { value in
            var ssh = profile.ssh ?? .default
            ssh.isEnabled = true
            edit(&ssh, value)
            profile.ssh = ssh
            profile.serverURL = APIClient.defaultServer
        }
    }

    private func save(makeCurrent: Bool) {
        var toSave = profile
        if toSave.transport == .sshTunnel {
            var ssh = toSave.ssh ?? .default
            ssh.isEnabled = true
            toSave.ssh = ssh
            toSave.serverURL = APIClient.defaultServer
        }
        state.saveHostProfile(toSave, password: password, makeCurrent: makeCurrent)
    }

    private func copyPublicKey() {
        #if !os(visionOS)
        do {
            let key = try state.sshTunnelManager.generateOrGetPublicKey()
            UIPasteboard.general.string = key
            publicKeyCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { publicKeyCopied = false }
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }
}

private struct LabeledNumberField: View {
    let title: String
    @Binding var value: Int
    let accessibilityID: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, formatter: NumberFormatter())
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .accessibilityIdentifier(accessibilityID)
        }
    }
}
