//
//  FilesTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct FilesTabView: View {
    @Bindable var state: AppState
    var onFileSelect: ((String) -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.effectiveLayout) private var effectiveLayout

    var body: some View {
        NavigationStack(path: $state.filesNavigationPath) {
            FileTreeView(state: state, onFileSelect: onFileSelect)
                .fileSearchQueryHandlers(state: state)
            .navigationTitle(L10n.t(.navFiles))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sizeClass == .regular, effectiveLayout != .regular {
                    ToolbarItem(placement: .primaryAction) {
                        LayoutPreferenceMenu(state: state)
                    }
                }
            }
        }
        .onChange(of: state.filesNavigationPath) { oldPath, newPath in
            if newPath.count > oldPath.count, let last = newPath.last {
                state.adoptFilesPush(last)
                return
            }
            if state.ignoreNextFilesPathShrink {
                state.ignoreNextFilesPathShrink = false
                return
            }
            guard effectiveLayout == .compact, newPath.isEmpty, let closed = oldPath.last else { return }
            state.closeMatchingPreview(closed)
        }
    }
}

extension View {
    func fileSearchQueryHandlers(state: AppState) -> some View {
        modifier(FileSearchQueryModifier(state: state))
    }
}

private struct FileSearchQueryModifier: ViewModifier {
    @Bindable var state: AppState

    func body(content: Content) -> some View {
        if FileSearchFixture.isActive {
            content
                .searchable(
                    text: $state.fileSearchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L10n.t(.appSearchFiles)
                )
                .onSubmit(of: .search) {
                    Task { await state.submitFileSearch() }
                }
                .onChange(of: state.fileSearchQuery) { _, newValue in
                    state.fileSearchQueryChanged(newValue)
                }
        } else {
            content
                .searchable(text: $state.fileSearchQuery, prompt: L10n.t(.appSearchFiles))
                .onSubmit(of: .search) {
                    Task { await state.submitFileSearch() }
                }
                .onChange(of: state.fileSearchQuery) { _, newValue in
                    state.fileSearchQueryChanged(newValue)
                }
        }
    }
}
