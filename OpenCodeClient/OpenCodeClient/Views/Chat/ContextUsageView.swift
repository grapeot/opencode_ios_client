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
        .help("Context usage")
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
                            Button("关闭") { showSheet = false }
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
                Section("Session") {
                    LabeledContent("Title", value: s.sessionTitle.isEmpty ? "Untitled" : s.sessionTitle)
                    LabeledContent("ID", value: s.sessionID)
                }

                Section("Model") {
                    LabeledContent("Provider", value: s.providerID)
                    LabeledContent("Model", value: s.modelID)
                    LabeledContent("Context limit", value: String(s.contextLimit))
                }

                Section("Tokens") {
                    LabeledContent("Total", value: String(s.tokens.total))
                    LabeledContent("Input", value: String(s.tokens.input))
                    LabeledContent("Output", value: String(s.tokens.output))
                    LabeledContent("Reasoning", value: String(s.tokens.reasoning))
                    LabeledContent("Cached read", value: String(s.tokens.cache?.read ?? 0))
                    LabeledContent("Cached write", value: String(s.tokens.cache?.write ?? 0))
                }

                Section("Cost") {
                    if let c = s.totalSessionCost {
                        LabeledContent("Total", value: String(format: "%.4f", c))
                    } else {
                        Text("No cost data")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    if isLoadingProviderConfig {
                        Text("Loading provider config...")
                            .foregroundStyle(.secondary)
                    } else if let err = providerConfigError, !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } else {
                        Text(hasProviderConfig ? "No usage data" : "Provider config not loaded")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Context")
        .navigationBarTitleDisplayMode(.inline)
    }
}
