import SwiftUI

@MainActor @Observable
final class SessionArchiveSelection {
    private(set) var scope: SessionArchiveScope?
    private(set) var selected = Set<String>()
    private(set) var isRunning = false
    private(set) var outcome: SessionArchiveOutcome?
    private(set) var successToast: SuccessToast?
    private var task: Task<Void, Never>?

    struct SuccessToast: Identifiable {
        let id = UUID()
        let count: Int
    }

    func begin(in scope: SessionArchiveScope) {
        selected.removeAll()
        outcome = nil
        successToast = nil
        self.scope = scope
    }

    func cancel() {
        guard !isRunning else { return }
        scope = nil
        selected.removeAll()
        outcome = nil
        successToast = nil
    }

    func scopeChanged() {
        task?.cancel()
        cancel()
    }

    func toggle(_ id: String) {
        guard !isRunning else { return }
        outcome = nil
        if !selected.insert(id).inserted { selected.remove(id) }
    }

    func submit(_ plan: SessionArchivePlan, state: AppState) {
        guard let scope, scope == state.sessionArchiveScope, state.isConnected,
              !isRunning, !plan.ids.isEmpty else { return }
        isRunning = true
        outcome = nil
        task = Task {
            let result = await state.archiveSessions(plan, in: scope)
            isRunning = false
            task = nil
            guard scope == state.sessionArchiveScope, !Task.isCancelled else { cancel(); return }
            selected.subtract(result.archived.union(result.missing))
            if result.remaining == 0 {
                cancel()
                if !result.archived.isEmpty { successToast = SuccessToast(count: result.archived.count) }
            } else {
                outcome = result
            }
        }
    }

    func dismissOutcome() { outcome = nil }
    func dismissSuccessToast(id: UUID) {
        if successToast?.id == id { successToast = nil }
    }
}

struct SessionArchiveSuccessOverlay: ViewModifier {
    let selection: SessionArchiveSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomLeading) {
            if let toast = selection.successToast {
                let message = L10n.t(.sessionsBatchArchived, toast.count)
                let shape = RoundedRectangle(cornerRadius: DesignCorners.medium)
                HStack(spacing: DesignSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignColors.Brand.primary)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(DesignTypography.body.weight(.semibold))
                        .foregroundStyle(DesignColors.Neutral.text)
                        .accessibilityIdentifier("session-archive-result")
                }
                .padding(.horizontal, DesignSpacing.md)
                .padding(.vertical, DesignSpacing.sm)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(colorScheme == .dark ? 0.16 : 0.10)))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.12), radius: 8, y: 3)
                .padding(DesignSpacing.md)
                .allowsHitTesting(false)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                .task(id: toast.id) {
                    AccessibilityNotification.Announcement(message).post()
                    do {
                        try await Task.sleep(for: .seconds(3))
                        selection.dismissSuccessToast(id: toast.id)
                    } catch { /* View disappeared or toast was replaced. */ }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: selection.successToast?.id)
    }
}

struct SessionArchiveBar: View {
    let selection: SessionArchiveSelection
    let state: AppState

    var body: some View {
        let plan = SessionArchivePlan(sessions: selection.scope == nil ? [] : state.sessions, selected: selection.selected)
        if selection.scope == state.sessionArchiveScope || selection.outcome != nil {
            VStack(spacing: DesignSpacing.xs) {
                if let result = selection.outcome {
                    HStack {
                        Text(L10n.t(.sessionsBatchIncomplete, result.archived.count, result.remaining))
                            .accessibilityIdentifier("session-archive-result")
                        Button(action: selection.dismissOutcome) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(L10n.t(.sessionsClose))
                    }
                    .font(DesignTypography.meta)
                }
                if selection.scope == state.sessionArchiveScope {
                    if selection.isRunning {
                        ProgressView(L10n.t(.sessionsBatchArchiving))
                    } else {
                        if selection.outcome?.foundMoreChildren == true {
                            Text(L10n.t(.sessionsBatchReviewChildren))
                                .font(DesignTypography.meta)
                        }
                        if plan.additionalCount > 0 {
                            Text(L10n.t(.sessionsBatchChildren, plan.additionalCount))
                                .font(DesignTypography.meta)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            selection.submit(plan, state: state)
                        } label: {
                            Label(L10n.t(.sessionsBatchArchive, plan.ids.count), systemImage: "archivebox")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.ids.isEmpty || !state.isConnected || state.isLoadingMoreSessions)
                        .accessibilityIdentifier("session-archive-submit")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSpacing.sm)
            .background(.regularMaterial)
        }
    }
}

struct SessionArchiveSelectButton: View {
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.t(.sessionsBatchSelect), systemImage: "checkmark.circle")
                .labelStyle(.iconOnly)
                .frame(minWidth: 32, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? DesignColors.Neutral.textTertiary : DesignColors.Brand.primary)
        .help(L10n.t(.sessionsBatchSelect))
        .accessibilityIdentifier("session-archive-select")
        .disabled(disabled)
    }
}
