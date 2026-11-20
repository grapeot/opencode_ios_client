import SwiftUI

@MainActor @Observable
final class SessionArchiveSelection {
    private(set) var scope: SessionArchiveScope?
    private(set) var selected = Set<String>()
    private(set) var isRunning = false
    private(set) var outcome: SessionArchiveOutcome?

    func begin(in scope: SessionArchiveScope) {
        selected.removeAll()
        outcome = nil
        self.scope = scope
    }

    func cancel() {
        guard !isRunning else { return }
        scope = nil
        selected.removeAll()
        outcome = nil
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
        Task {
            let result = await state.archiveSessions(plan, in: scope)
            isRunning = false
            guard scope == state.sessionArchiveScope else { cancel(); return }
            selected.subtract(result.archived)
            if result.remaining == 0 { cancel() }
            outcome = result
        }
    }

    func dismissOutcome() { outcome = nil }
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
                        Text(result.remaining == 0
                             ? L10n.t(.sessionsBatchArchived, result.archived.count)
                             : L10n.t(.sessionsBatchIncomplete, result.archived.count, result.remaining))
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
                        if plan.additionalCount > 0 {
                            Text(L10n.t(.sessionsBatchChildren, plan.additionalCount))
                                .font(DesignTypography.meta)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            selection.submit(plan, state: state)
                        } label: {
                            Label(L10n.t(.sessionsBatchArchive, plan.ids.count), systemImage: "archivebox")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.ids.isEmpty || !state.isConnected)
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
                .frame(minWidth: 28, minHeight: 44)
        }
        .help(L10n.t(.sessionsBatchSelect))
        .accessibilityIdentifier("session-archive-select")
        .disabled(disabled)
    }
}
