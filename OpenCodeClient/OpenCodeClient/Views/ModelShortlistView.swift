import SwiftUI
import UIKit

struct ModelShortlistView: View {
    @Bindable var state: AppState
    @State private var showCatalog = false
    @State private var editingItem: ModelShortlistItem?
    @State private var draftShortName = ""
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var listOrigin: CGPoint = .zero
    @State private var listFrameReady = false

    var body: some View {
        List {
            Section {
                if state.modelShortlist.isEmpty {
                    Text(L10n.t(.settingsModelShortlistEmpty))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.modelShortlist) { item in
                        HStack(spacing: 12) {
                            reorderGrip(for: item)
                            Button {
                                draftShortName = item.shortName
                                editingItem = item
                            } label: {
                                shortlistLabel(item)
                            }
                            .buttonStyle(.plain)
                        }
                        .opacity(draggingID == item.id ? 0.35 : 1)
                        .background {
                            ShortlistRowFrameReader(isEnabled: draggingID == nil) { frame in
                                rowFrames[item.id] = frame
                            }
                        }
                        .accessibilityIdentifier("model-shortlist-row-\(item.providerID)-\(item.modelID)")
                        .shortlistDropHighlight(isDropTarget(item))
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
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        listOrigin = geo.frame(in: .global).origin
                        listFrameReady = true
                    }
                    .onChange(of: geo.frame(in: .global).origin) { _, origin in
                        guard draggingID == nil else { return }
                        listOrigin = origin
                        listFrameReady = true
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            dragPreview
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

    private func reorderGrip(for item: ModelShortlistItem) -> some View {
        ShortlistReorderGrip(
            onChanged: { translation in
                if draggingID != item.id {
                    draggingID = item.id
                }
                dragTranslation = translation
            },
            onEnded: { translation in
                commitReorder(id: item.id, translation: translation)
            }
        )
        .frame(width: 28, height: 44)
        .overlay {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(L10n.t(.settingsModelShortlistReorder))
        .accessibilityIdentifier("model-shortlist-handle-\(item.providerID)-\(item.modelID)")
    }

    private func shortlistLabel(_ item: ModelShortlistItem) -> some View {
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

    @ViewBuilder
    private var dragPreview: some View {
        if listFrameReady,
           let draggingID,
           let item = state.modelShortlist.first(where: { $0.id == draggingID }),
           let frame = rowFrames[draggingID] {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                shortlistLabel(item)
            }
            .padding(.horizontal, 16)
            .frame(width: frame.width, height: frame.height, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
            .offset(x: frame.minX - listOrigin.x, y: frame.minY - listOrigin.y + dragTranslation)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func isDropTarget(_ item: ModelShortlistItem) -> Bool {
        guard let draggingID, draggingID != item.id, let target = dragTargetIndex else { return false }
        return state.modelShortlist.firstIndex(where: { $0.id == item.id }) == target
    }

    private var dragTargetIndex: Int? {
        guard let draggingID,
              let start = state.modelShortlist.firstIndex(where: { $0.id == draggingID })
        else { return nil }
        return ShortlistReorderMath.targetIndex(
            start: start,
            translation: dragTranslation,
            rowHeight: rowFrames[draggingID]?.height ?? 56,
            count: state.modelShortlist.count
        )
    }

    private func commitReorder(id: String, translation: CGFloat) {
        let start = state.modelShortlist.firstIndex(where: { $0.id == id })
        let height = rowFrames[id]?.height ?? 56
        let count = state.modelShortlist.count
        draggingID = nil
        dragTranslation = 0
        guard let start else { return }
        let target = ShortlistReorderMath.targetIndex(
            start: start,
            translation: translation,
            rowHeight: height,
            count: count
        )
        guard target != start else { return }
        state.moveShortlist(
            from: IndexSet(integer: start),
            to: ShortlistReorderMath.moveDestination(from: start, to: target)
        )
    }
}

enum ShortlistReorderMath {
    static func targetIndex(start: Int, translation: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let height = rowHeight > 1 ? rowHeight : 56
        let steps = Int((translation / height).rounded(.toNearestOrAwayFromZero))
        return min(max(start + steps, 0), count - 1)
    }

    static func moveDestination(from start: Int, to target: Int) -> Int {
        target > start ? target + 1 : target
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
                Section {
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
                                        Text("\(state.providerDisplayNames[preset.providerID] ?? preset.providerID) / \(preset.modelID)")
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
                } footer: {
                    Text(L10n.t(.settingsModelShortlistCatalogHint))
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

private extension View {
    @ViewBuilder
    func shortlistDropHighlight(_ on: Bool) -> some View {
        if on {
            listRowBackground(DesignColors.Brand.primary.opacity(0.16))
        } else {
            self
        }
    }
}

private struct ShortlistRowFrameReader: View {
    var isEnabled: Bool
    var onFrame: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { report(geo) }
                .onChange(of: geo.frame(in: .global).minY) { _, _ in
                    report(geo)
                }
        }
    }

    private func report(_ geo: GeometryProxy) {
        guard isEnabled else { return }
        onFrame(geo.frame(in: .global))
    }
}

private struct ShortlistReorderGrip: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> ShortlistReorderGripView {
        let view = ShortlistReorderGripView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: ShortlistReorderGripView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let basis = pan.view?.window ?? pan.view
            let translation = pan.translation(in: basis).y
            switch pan.state {
            case .began, .changed:
                onChanged(translation)
            case .ended, .cancelled, .failed:
                onEnded(translation)
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

private final class ShortlistReorderGripView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01, bounds.contains(point) else {
            return nil
        }
        return self
    }
}
