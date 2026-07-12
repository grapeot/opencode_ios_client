import SwiftUI

struct AIUsageQuotaButton: View {
    @Bindable var state: AppState
    @State private var showSheet = false

    private var quota: AIUsageQuota? { state.selectedModelQuota }

    private var badgeColor: Color {
        guard !state.isSelectedModelQuotaStale, let remaining = quota?.clampedRemainingPercentage else {
            return DesignColors.Neutral.textSecondary
        }
        if remaining <= 10 { return DesignColors.Semantic.error }
        if remaining <= 20 { return DesignColors.Semantic.warning }
        return DesignColors.Neutral.textSecondary
    }

    private var badgeText: String {
        if state.isSelectedModelQuotaStale { return "stale @ 5h" }
        guard let quota else {
            if case .loading = state.aiUsageQuotaState { return "... @ 5h" }
            return "-- @ 5h"
        }
        return "\(quota.clampedRemainingPercentage)% @ \(quota.label)"
    }

    var body: some View {
        if state.isAIUsageQuotaConfigured, state.selectedModel?.primaryQuotaKey != nil {
            Button {
                showSheet = true
                Task { await state.refreshAIUsageQuotas(force: true) }
            } label: {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(
                        Capsule()
                            .stroke(badgeColor.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat-toolbar-quota")
            .accessibilityLabel(L10n.t(.quotaCurrentModelAccessibility, badgeText))
            .sheet(isPresented: $showSheet) {
                NavigationStack {
                    AIUsageQuotaDetailView(state: state)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L10n.t(.appDone)) { showSheet = false }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    Task { await state.refreshAIUsageDashboard() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled({
                                    if case .loading = state.aiUsageQuotaState { return true }
                                    return false
                                }())
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

struct AIUsageQuotaDetailView: View {
    @Bindable var state: AppState

    private var groupedQuotas: [(String, [AIUsageQuota])] {
        let quotas = state.aiUsageQuotaState.snapshot?.quotas ?? []
        return Dictionary(grouping: quotas, by: \AIUsageQuota.provider)
            .map { ($0.key, $0.value.sorted { $0.label < $1.label }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List {
            ForEach(groupedQuotas, id: \.0) { provider, quotas in
                if !quotas.isEmpty {
                    Section(providerDisplayName(provider)) {
                        ForEach(quotas) { quota in
                            quotaRow(quota)
                        }
                    }
                }
            }

            statusSection
        }
        .navigationTitle(L10n.t(.quotaTitle))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("quota-detail")
    }

    @ViewBuilder
    private var statusSection: some View {
        Section(L10n.t(.quotaDataSource)) {
            switch state.aiUsageQuotaState {
            case .idle:
                Text(L10n.t(.quotaNotLoaded)).foregroundStyle(.secondary)
            case .loading(let previous):
                HStack {
                    ProgressView()
                    Text(state.isRefreshingAIUsageProviders
                         ? L10n.t(.quotaRefreshingProviders)
                         : (previous == nil ? L10n.t(.quotaLoading) : L10n.t(.quotaRefreshing)))
                }
            case .empty:
                Text(L10n.t(.quotaNoCachedData)).foregroundStyle(.secondary)
            case .failed(_, let message):
                Label(L10n.t(.quotaStale), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary)
            case .ready(let snapshot):
                LabeledContent(L10n.t(.quotaLastFetched), value: snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
                if let generatedAt = snapshot.generatedAt {
                    LabeledContent(L10n.t(.quotaGeneratedAt), value: generatedAt)
                }
            }
            Text(state.aiUsageDashboardURL)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func quotaRow(_ quota: AIUsageQuota) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(quota.label)
                Spacer()
                Text(L10n.t(.quotaRemainingFormat, quota.clampedRemainingPercentage))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(quotaColor(quota.clampedRemainingPercentage))
            }
            ProgressView(value: Double(quota.clampedRemainingPercentage), total: 100)
                .tint(quotaColor(quota.clampedRemainingPercentage))
            HStack {
                Text(L10n.t(.quotaUsedFormat, quota.clampedUsedPercentage))
                Spacer()
                if let reset = quota.resetDate {
                    Text(L10n.t(.quotaResetFormat, reset.formatted(date: .abbreviated, time: .shortened)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func quotaColor(_ remaining: Int) -> Color {
        if remaining <= 10 { return DesignColors.Semantic.error }
        if remaining <= 20 { return DesignColors.Semantic.warning }
        return DesignColors.Brand.primary
    }

    private func providerDisplayName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "codex": return "OpenAI / Codex"
        case "glm": return "Z.ai / GLM"
        case "ollama": return "Ollama Cloud"
        case "claude": return "Claude"
        case "antigravity": return "Antigravity"
        default: return provider
        }
    }
}
