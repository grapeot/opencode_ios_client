import SwiftUI
import UniformTypeIdentifiers

struct ModelShortlistView: View {
    @Bindable var state: AppState
    @State private var showCatalog = false
    @State private var editingItem: ModelShortlistItem?
    @State private var draftShortName = ""
    @State private var draggingID: String?

    var body: some View {
        List {
            Section {
                if state.modelShortlist.isEmpty {
                    Text(L10n.t(.settingsModelShortlistEmpty))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.modelShortlist) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                                .contentShape(Rectangle())
                                .onDrag {
                                    draggingID = item.id
                                    return NSItemProvider(object: item.id as NSString)
                                }
                                .accessibilityLabel(L10n.t(.settingsModelShortlistReorder))
                            Button {
                                draftShortName = item.shortName
                                editingItem = item
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName)
                                        .foregroundStyle(.primary)
                                    Text("\(state.providerDisplayNames[item.providerID] ?? item.providerID) / \(item.modelID)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .accessibilityIdentifier("model-shortlist-row-\(item.providerID)-\(item.modelID)")
                        .onDrop(of: [UTType.plainText], delegate: ShortlistDropDelegate(
                            itemID: item.id,
                            items: state.modelShortlist,
                            draggingID: $draggingID,
                            move: { source, dest in
                                state.moveShortlist(from: source, to: dest)
                            }
                        ))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                state.removeShortlistItem(id: item.id)
                            } label: {
                                Text(L10n.t(.sessionsDelete))
                            }
                        }
                    }
                }
            } footer: {
                Text(L10n.t(.settingsModelShortlistHint))
            }
        }
        .navigationTitle(L10n.t(.settingsModelShortlist))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCatalog = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("model-shortlist-add")
            }
        }
        .sheet(isPresented: $showCatalog) {
            ModelCatalogPickerView(state: state, isPresented: $showCatalog)
        }
        .alert(
            L10n.t(.settingsModelShortlistEditName),
            isPresented: Binding(
                get: { editingItem != nil },
                set: { if !$0 { editingItem = nil } }
            )
        ) {
            TextField(L10n.t(.settingsModelShortlistShortName), text: $draftShortName)
            Button(L10n.t(.appDone)) {
                if let id = editingItem?.id {
                    state.updateShortlistShortName(id: id, shortName: draftShortName)
                }
                editingItem = nil
            }
            Button(L10n.t(.commonCancel), role: .cancel) {
                editingItem = nil
            }
        }
    }
}

struct ModelCatalogPickerView: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIDs: Set<String> = []

    private var existingIDs: Set<String> {
        Set(state.modelShortlist.map(\.id))
    }

    private var filteredCatalog: [ModelPreset] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.catalogModelPresets.filter { preset in
            guard !existingIDs.contains(preset.id) else { return false }
            guard !q.isEmpty else { return true }
            return preset.displayName.lowercased().contains(q)
                || preset.modelID.lowercased().contains(q)
                || preset.providerID.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(L10n.t(.settingsModelShortlistSearch), text: $query)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.secondary.opacity(0.45))
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.t(.settingsModelShortlistSearchClear))
                            .accessibilityIdentifier("model-catalog-search-clear")
                        }
                    }
                }
                if state.catalogModelPresets.isEmpty {
                    Text(L10n.t(.settingsModelShortlistCatalogEmpty))
                        .foregroundStyle(.secondary)
                } else if filteredCatalog.isEmpty {
                    Text(L10n.t(.configureModelNoMatches))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredCatalog) { preset in
                        Button {
                            if selectedIDs.contains(preset.id) {
                                selectedIDs.remove(preset.id)
                            } else {
                                selectedIDs.insert(preset.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.displayName)
                                        .foregroundStyle(.primary)
                                    Text("\(state.providerDisplayNames[preset.providerID] ?? preset.providerID)/\(preset.modelID)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if selectedIDs.contains(preset.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DesignColors.Brand.primary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("model-catalog-row-\(preset.providerID)-\(preset.modelID)")
                    }
                }
            }
            .navigationTitle(L10n.t(.settingsModelShortlistAdd))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t(.commonCancel)) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.settingsModelShortlistAddSelected)) {
                        let chosen = state.catalogModelPresets.filter { selectedIDs.contains($0.id) }
                        state.addModelsToShortlist(chosen)
                        isPresented = false
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("model-catalog-add-selected")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ShortlistDropDelegate: DropDelegate {
    let itemID: String
    let items: [ModelShortlistItem]
    @Binding var draggingID: String?
    let move: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != itemID,
              let from = items.firstIndex(where: { $0.id == draggingID }),
              let to = items.firstIndex(where: { $0.id == itemID })
        else { return }
        move(IndexSet(integer: from), to > from ? to + 1 : to)
    }
}
