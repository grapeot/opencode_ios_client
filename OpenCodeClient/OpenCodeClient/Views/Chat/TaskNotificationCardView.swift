//
//  TaskNotificationCardView.swift
//  OpenCodeClient
//

import SwiftUI

struct TaskNotificationCardView<Result: View>: View {
    let notification: TaskNotification
    let onOpenSession: () -> Void
    private let result: () -> Result

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool

    init(
        notification: TaskNotification,
        onOpenSession: @escaping () -> Void,
        @ViewBuilder result: @escaping () -> Result
    ) {
        self.notification = notification
        self.onOpenSession = onOpenSession
        self.result = result
        let count = notification.resultText.trimmingCharacters(in: .whitespacesAndNewlines).count
        self._isExpanded = State(initialValue: count <= TaskNotificationParser.defaultExpandedCharacterLimit)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                if notification.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.t(.taskNotificationNoOutput))
                        .font(DesignTypography.meta)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    result()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: onOpenSession) {
                    Text(L10n.t(.taskNotificationOpenSession))
                        .font(DesignTypography.micro)
                        .foregroundStyle(DesignColors.Brand.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DesignSpacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(TaskNotificationParser.openSessionAccessibilityIdentifier)
                .accessibilityLabel(L10n.t(.taskNotificationOpenSession))
            }
            .padding(.top, DesignSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        } label: {
            HStack(spacing: DesignSpacing.xs) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .font(DesignTypography.meta)
                if let statusLabel {
                    Text(statusLabel)
                        .font(DesignTypography.micro)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(notification.displayTitle)
                    .font(DesignTypography.meta)
                    .foregroundStyle(DesignColors.Neutral.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .tint(DesignColors.Brand.primary)
        .accessibilityIdentifier(TaskNotificationParser.cardAccessibilityIdentifier)
        .padding(DesignSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for: colorScheme)))
        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
    }

    private var statusSymbol: String {
        switch notification.state {
        case .completed: return "checkmark.seal.fill"
        case .error: return "xmark.seal.fill"
        case .running: return "hourglass"
        }
    }

    private var statusColor: Color {
        switch notification.state {
        case .completed: return DesignColors.Semantic.success
        case .error: return DesignColors.Semantic.error
        case .running: return DesignColors.Neutral.textSecondary
        }
    }

    private var statusLabel: String? {
        switch notification.state {
        case .completed: return L10n.t(.taskNotificationCompleted)
        case .error: return L10n.t(.taskNotificationFailed)
        case .running: return nil
        }
    }
}
