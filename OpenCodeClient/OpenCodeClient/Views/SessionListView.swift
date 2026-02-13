//
//  SessionListView.swift
//  OpenCodeClient
//

import SwiftUI

struct SessionListView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if state.sessions.isEmpty {
                    ContentUnavailableView(
                        "暂无 Session",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("点击右上角新建，或下拉刷新获取已有 Session")
                    )
                } else {
                    List {
                        ForEach(state.sortedSessions) { session in
                            SessionRowView(
                                session: session,
                                status: state.sessionStatuses[session.id],
                                isSelected: state.currentSessionID == session.id
                            ) {
                                selectSession(session)
                            }
                        }
                    }
                    .refreshable {
                        await state.refreshSessions()
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await state.createSession()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .task {
            await state.refreshSessions()
        }
    }

    private func selectSession(_ session: Session) {
        state.selectSession(session)
        dismiss()
    }
}

struct SessionRowView: View {
    let session: Session
    let status: SessionStatus?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title.isEmpty ? "Untitled" : session.title)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    HStack(spacing: 8) {
                        Text(formattedDate(session.time.updated))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let summary = session.summary {
                            Text("\(summary.files) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let status {
                            Text(statusLabel(status))
                                .font(.caption)
                                .foregroundStyle(statusColor(status))
                        }
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.secondary.opacity(0.12) : Color.clear)
    }

    private func formattedDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_Hans")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func statusLabel(_ status: SessionStatus) -> String {
        switch status.type {
        case "busy": return "运行中"
        case "retry": return "重试中"
        default: return "空闲"
        }
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        // Keep session list typography neutral; selection uses background highlight.
        return .secondary
    }
}
