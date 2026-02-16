//
//  PermissionCardView.swift
//  OpenCodeClient
//

import SwiftUI

struct PermissionCardView: View {
    let permission: PendingPermission
    let onRespond: (APIClient.PermissionResponse) -> Void

    private let accent = Color.orange
    private let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(accent)
                    .font(.title3)
                Text(L10n.t(.permissionRequired))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }

            if let name = permission.permission, !name.isEmpty {
                Text(name)
                    .font(.callout.weight(.semibold))
            }

            Text(permission.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !permission.patterns.isEmpty {
                Text(permission.patterns.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        onRespond(.once)
                    } label: {
                        Text(L10n.t(.permissionAllowOnce))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        onRespond(.always)
                    } label: {
                        Text(L10n.t(.permissionAllowAlways))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(!permission.allowAlways)
                }

                Button {
                    onRespond(.reject)
                } label: {
                    Text(L10n.t(.permissionReject))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(accent.opacity(0.14), lineWidth: 1)
        )
    }
}
