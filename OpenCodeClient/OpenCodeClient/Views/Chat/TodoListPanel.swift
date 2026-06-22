//
//  TodoListPanel.swift
//  OpenCodeClient
//

import SwiftUI

struct TodoListPanel: View {
    let todos: [TodoItem]

    var body: some View {
        if todos.isEmpty {
            emptyView
        } else {
            contentView
        }
    }

    private var completedCount: Int {
        todos.count { $0.isCompleted }
    }

    private var totalCount: Int {
        todos.count
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if totalCount > 0 {
                ProgressView(value: Double(completedCount), total: Double(totalCount))
                    .tint(DesignColors.Brand.primary)
                    .padding(.horizontal, DesignSpacing.lg)
                    .padding(.top, DesignSpacing.md)
                    .padding(.bottom, 2)
                HStack {
                    Text(L10n.t(.todoPanelCompleted, Int32(completedCount), Int32(totalCount)))
                        .font(DesignTypography.meta)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.bottom, DesignSpacing.sm)
            }

            Divider()
                .padding(.horizontal, DesignSpacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    ForEach(todos) { todo in
                        HStack(alignment: .top, spacing: DesignSpacing.sm) {
                            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(todo.isCompleted ? DesignColors.Semantic.success : DesignColors.Neutral.textSecondary)
                                .font(DesignTypography.meta)
                                .padding(.top, 2)
                            Text(todo.content)
                                .font(DesignTypography.body)
                                .foregroundStyle(todo.isCompleted ? DesignColors.Neutral.textSecondary : DesignColors.Neutral.text)
                                .strikethrough(todo.isCompleted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, DesignSpacing.lg)
                    }
                }
                .padding(.vertical, DesignSpacing.sm)
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: DesignSpacing.lg) {
            Image(systemName: "checklist")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(L10n.t(.todoPanelEmpty))
                .font(DesignTypography.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
