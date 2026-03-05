//
//  QuestionCardView.swift
//  OpenCodeClient
//

import SwiftUI

struct QuestionCardView: View {
    let request: PendingQuestion
    let onReply: ([[String]]) -> Void
    let onReject: () -> Void

    @State private var selectedLabelsByQuestionID: [String: Set<String>] = [:]
    @State private var customAnswerByQuestionID: [String: String] = [:]

    private let accent = Color.indigo
    private let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(accent)
                    .font(.title3)
                Text(L10n.t(.questionNeedsReply))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }

            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.header)
                        .font(.callout.weight(.semibold))

                    Text(question.question)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !question.options.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(question.options) { option in
                                Button {
                                    toggleOption(option, for: question)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isSelected(option, in: question) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected(option, in: question) ? accent : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.label)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            if !option.description.isEmpty {
                                                Text(option.description)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected(option, in: question) ? accent.opacity(0.12) : Color(.systemGray6))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if question.custom {
                        TextField(
                            L10n.t(.questionCustomAnswerPlaceholder),
                            text: Binding(
                                get: { customAnswerByQuestionID[question.id] ?? "" },
                                set: { customAnswerByQuestionID[question.id] = $0 }
                            ),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onReply(composeAnswers())
                } label: {
                    Text(L10n.t(.questionSubmit))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    onReject()
                } label: {
                    Text(L10n.t(.questionReject))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(accent.opacity(0.14), lineWidth: 1)
        )
    }

    private func isSelected(_ option: PendingQuestionOption, in question: PendingQuestionItem) -> Bool {
        selectedLabelsByQuestionID[question.id, default: []].contains(option.label)
    }

    private func toggleOption(_ option: PendingQuestionOption, for question: PendingQuestionItem) {
        var current = selectedLabelsByQuestionID[question.id, default: []]
        if question.multiple {
            if current.contains(option.label) {
                current.remove(option.label)
            } else {
                current.insert(option.label)
            }
        } else {
            if current.contains(option.label) {
                current.removeAll()
            } else {
                current = [option.label]
            }
        }
        selectedLabelsByQuestionID[question.id] = current
    }

    private func composeAnswers() -> [[String]] {
        request.questions.map { question in
            var answer: [String] = question.options.compactMap { option in
                selectedLabelsByQuestionID[question.id, default: []].contains(option.label) ? option.label : nil
            }

            if question.custom {
                let custom = (customAnswerByQuestionID[question.id] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !custom.isEmpty {
                    answer.append(custom)
                }
            }

            return answer
        }
    }
}
