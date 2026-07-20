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

                HStack(alignment: .top, spacing: DesignSpacing.sm) {
                    Button {
                        Task { await state.resolveClientCapabilityPermission(allow: true) }
                    } label: {
                        permissionButtonLabel(L10n.t(.capabilityAllowOnce))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("capability-allow-once")

                    Button {
                        Task { await state.resolveClientCapabilityPermission(allow: true, always: true) }
                    } label: {
                        permissionButtonLabel(L10n.t(.capabilityAllowAlways))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("capability-allow-always")

                    Button(role: .cancel) {
                        Task { await state.resolveClientCapabilityPermission(allow: false) }
                    } label: {
                        permissionButtonLabel(L10n.t(.commonCancel))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("capability-cancel")
                }
                .controlSize(.large)
            }
            .padding(DesignSpacing.lg)
            .navigationTitle(L10n.t(.capabilityPermissionTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private func permissionButtonLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}
