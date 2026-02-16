//
//  FilesTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct FilesTabView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            FileTreeView(state: state)
                .searchable(text: $state.fileSearchQuery, prompt: L10n.t(.appSearchFiles))
                .onSubmit(of: .search) {
                    Task { await state.searchFiles(query: state.fileSearchQuery) }
                }
                .onChange(of: state.fileSearchQuery) { _, newValue in
                    if newValue.isEmpty {
                        state.fileSearchResults = []
                    } else {
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await state.searchFiles(query: newValue)
                        }
                    }
                }
            .navigationTitle(L10n.t(.navFiles))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
