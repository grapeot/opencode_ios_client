//
//  PermissionCardView.swift
//  OpenCodeClient
//

import SwiftUI

struct PermissionCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let permission: PendingPermission
    let onRespond: (APIClient.PermissionResponse) -> Void

    // Action cards speak a single language: a left electric-blue accent bar
    // plus plain text actions. Blue is the only color — green/orange/red are
    // dropped so the card reads as "decision needed", not "alarm".
    private let accent = DesignColors.Brand.primary

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                if let name = permission.permission, !name.isEmpty {
                    Text(name)
                        .font(DesignTypography.body.weight(.semibold))
                }

                Text(permission.description)
                    .font(DesignTypography.body)
                    .foregroundStyle(DesignColors.Neutral.text)

                if !permission.patterns.isEmpty {
                    Text(permission.patterns.joined(separator: ", "))
                        .font(DesignTypography.microMono)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: DesignSpacing.lg) {
                    Button {
                        onRespond(.once)
                    } label: {
                        Text(L10n.t(.permissionAllowOnce))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)

                    if permission.allowAlways {
                        Button {
                            onRespond(.always)
                        } label: {
                            Text(L10n.t(.permissionAllowAlways))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onRespond(.reject)
                    } label: {
                        Text(L10n.t(.permissionReject))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignColors.Neutral.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .padding(DesignSpacing.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for: colorScheme)))
        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
    }
}
