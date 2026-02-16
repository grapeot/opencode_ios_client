//
//  ContextUsageView.swift
//  OpenCodeClient
//

import SwiftUI

struct ContextUsageSnapshot: Identifiable {
    var id: String { sessionID }
    let sessionID: String
    let sessionTitle: String
    let providerID: String
    let modelID: String
    let contextLimit: Int
    let tokens: Message.TokenInfo
    let latestMessageCost: Double?
    let totalSessionCost: Double?
}

extension AppState {
    var contextUsageSnapshot: ContextUsageSnapshot? {
        guard let sessionID = currentSessionID,
              let session = currentSession else { return nil }

        guard let last = messages.reversed().first(where: { $0.info.isAssistant && $0.info.tokens != nil }),
              let tokens = last.info.tokens,
              let model = last.info.resolvedModel else { return nil }

        let key = "\(model.providerID)/\(model.modelID)"
        guard let contextLimit = providerModelsIndex[key]?.limit?.context else { return nil }

        let sumCost = messages.compactMap { $0.info.cost }.reduce(0.0, +)
        let totalCost: Double? = sumCost > 0 ? sumCost : nil

        return ContextUsageSnapshot(
            sessionID: sessionID,
            sessionTitle: session.title,
            providerID: model.providerID,
            modelID: model.modelID,
            contextLimit: contextLimit,
            tokens: tokens,
            latestMessageCost: last.info.cost,
            totalSessionCost: totalCost
        )
    }
}

struct ContextUsageButton: View {
    @Bindable var state: AppState
    @State private var showSheet = false
    @State private var isLoadingProviderConfig = false
    @State private var detent: PresentationDetent = .large
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var preferLargeSheet: Bool { sizeClass == .regular }

    private var snapshot: ContextUsageSnapshot? { state.contextUsageSnapshot }

    private var progress: Double? {
        guard let s = snapshot else { return nil }
        guard s.contextLimit > 0 else { return nil }
        return min(1.0, Double(s.tokens.total) / Double(s.contextLimit))
    }

    private var ringColor: Color {
        guard let p = progress else { return .secondary.opacity(0.55) }
        if p >= 0.9 { return .red }
        if p >= 0.7 { return .orange }
        return .accentColor
    }

    var body: some View {
        Button {
            if state.providerModelsIndex.isEmpty, state.isConnected {
                isLoadingProviderConfig = true
                Task {
                    await state.loadProvidersConfig()
                    await MainActor.run { isLoadingProviderConfig = false }
                }
            }

            detent = preferLargeSheet ? .large : .medium
            showSheet = true
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                if let p = progress {
                    Circle()
                        .trim(from: 0, to: p)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t(.contextUsageHelp))
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                ContextUsageDetailView(
                    snapshot: snapshot,
                    hasProviderConfig: !state.providerModelsIndex.isEmpty,
                    isLoadingProviderConfig: isLoadingProviderConfig,
                    providerConfigError: state.providerConfigError
                )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.t(.contextUsageClose)) { showSheet = false }
                        }
                    }
            }
            .presentationDetents(preferLargeSheet ? [.large] : [.medium, .large], selection: $detent)
        }
    }
}

private struct ContextUsageDetailView: View {
    let snapshot: ContextUsageSnapshot?
    let hasProviderConfig: Bool
    let isLoadingProviderConfig: Bool
    let providerConfigError: String?

    var body: some View {
        List {
            if let s = snapshot {
                Section(L10n.t(.contextUsageSectionSession)) {
                    LabeledContent(L10n.t(.contextUsageTitleLabel), value: s.sessionTitle.isEmpty ? L10n.t(.sessionsUntitled) : s.sessionTitle)
                    LabeledContent(L10n.t(.contextUsageIdLabel), value: s.sessionID)
                }

                Section(L10n.t(.contextUsageSectionModel)) {
                    LabeledContent(L10n.t(.contextUsageProviderLabel), value: s.providerID)
                    LabeledContent(L10n.t(.contextUsageModelLabel), value: s.modelID)
                    LabeledContent(L10n.t(.contextUsageLimitLabel), value: String(s.contextLimit))
                }

                Section(L10n.t(.contextUsageSectionTokens)) {
                    LabeledContent(L10n.t(.contextUsageTotalLabel), value: String(s.tokens.total))
                    LabeledContent(L10n.t(.contextUsageInputLabel), value: String(s.tokens.input))
                    LabeledContent(L10n.t(.contextUsageOutputLabel), value: String(s.tokens.output))
                    LabeledContent(L10n.t(.contextUsageReasoningLabel), value: String(s.tokens.reasoning))
                    LabeledContent(L10n.t(.contextUsageCachedReadLabel), value: String(s.tokens.cache?.read ?? 0))
                    LabeledContent(L10n.t(.contextUsageCachedWriteLabel), value: String(s.tokens.cache?.write ?? 0))
                }

                Section(L10n.t(.contextUsageSectionCost)) {
                    if let c = s.totalSessionCost {
                        LabeledContent(L10n.t(.contextUsageTotalLabel), value: String(format: "%.4f", c))
                    } else {
                        Text(L10n.t(.contextUsageNoCostData))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    if isLoadingProviderConfig {
                        Text(L10n.t(.contextUsageLoadingConfig))
                            .foregroundStyle(.secondary)
                    } else if let err = providerConfigError, !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } else {
                        Text(hasProviderConfig ? L10n.t(.contextUsageNoUsageData) : L10n.t(.contextUsageConfigNotLoaded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(L10n.t(.contextUsageTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}
