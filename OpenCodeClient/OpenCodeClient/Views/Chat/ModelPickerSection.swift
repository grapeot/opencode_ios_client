//
//  ModelPickerSection.swift
//  OpenCodeClient
//
//  Shared model-picker list: searchable, grouped by connected provider,
//  with the curated presets as fallback when the server registry is
//  unavailable. Used by the Chat configure sheet and Settings.
//

import SwiftUI

struct ModelPickerSection: View {
    @Bindable var state: AppState
    @Binding var searchText: String

    private var filteredGroups: [(providerID: String, entries: [(index: Int, preset: ModelPreset)])] {
        let presets = state.pickerModelPresets
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty
            ? presets
            : presets.filter {
                $0.displayName.lowercased().contains(query)
                    || $0.modelID.lowercased().contains(query)
                    || $0.providerID.lowercased().contains(query)
            }
        var byProvider: [String: [(Int, ModelPreset)]] = [:]
        var order: [String] = []
        for (idx, preset) in filtered.enumerated() {
            let pid = preset.providerID
            if byProvider[pid] == nil { order.append(pid) }
            byProvider[pid]?.append((idx, preset))
        }
        return order.map { ($0, byProvider[$0] ?? []) }
    }

    var body: some View {
        let groups = filteredGroups
        if state.dynamicModelPresets.isEmpty {
            // Fallback: curated presets (registry unavailable).
            Section(L10n.t(.configureModel)) {
                ForEach(Array(state.pickerModelPresets.enumerated()), id: \.element.id) { index, preset in
                    row(index: index, preset: preset)
                }
            }
        } else {
            ForEach(groups, id: \.providerID) { group in
                Section(
                    header: Text(state.providerDisplayNames[group.providerID] ?? group.providerID)
                ) {
                    ForEach(group.entries, id: \.preset.id) { entry in
                        row(index: entry.index, preset: entry.preset)
                    }
                }
            }
            if groups.isEmpty {
                Section {
                    Text(L10n.t(.configureModelNoMatches))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func row(index: Int, preset: ModelPreset) -> some View {
        Button {
            state.setSelectedModelIndex(index)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                    if preset.displayName != preset.modelID {
                        Text(preset.modelID)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if state.selectedModelIndex == index {
                    Image(systemName: "checkmark")
                        .foregroundColor(DesignColors.Brand.primary)
                }
            }
        }
        .foregroundColor(.primary)
        .accessibilityIdentifier("model-picker-row-\(preset.providerID)-\(preset.modelID)")
    }
}
