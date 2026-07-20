import SwiftUI

struct ClientCapabilityPermissionView: View {
    @Bindable var state: AppState
    let request: PendingClientCapabilityRequest

    private var reason: String {
        request.action.reason ?? L10n.t(.capabilityHealthExportDescription)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                Label(L10n.t(.capabilityHealthExportTitle), systemImage: "heart.text.clipboard")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text(L10n.t(.capabilityReason))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(reason)
                        .font(.body)
                }

                Text(L10n.t(.capabilityPermissionFooter))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(L10n.t(.capabilityAllowOnce)) {
                    Task { await state.resolveClientCapabilityPermission(allow: true) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("capability-allow-once")

                Button(L10n.t(.capabilityAllowAlways)) {
                    Task { await state.resolveClientCapabilityPermission(allow: true, always: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("capability-allow-always")

                Button(L10n.t(.commonCancel), role: .cancel) {
                    Task { await state.resolveClientCapabilityPermission(allow: false) }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("capability-cancel")
            }
            .padding(DesignSpacing.lg)
            .navigationTitle(L10n.t(.capabilityPermissionTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}
