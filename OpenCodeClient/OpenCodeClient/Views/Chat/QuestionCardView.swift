//
//  QuestionCardView.swift
//  OpenCodeClient
//

import SwiftUI

struct QuestionCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let request: QuestionRequest
    let onReply: @MainActor ([[String]]) async -> Bool
    let onReject: () -> Void

    @State private var currentTab: Int
    @State private var answers: [[String]]
    @State private var customTexts: [String]
    @State private var customActive: [Bool]
    @State private var isCustomEditing: Bool = false
    @State private var isSending: Bool = false

    private let accent = DesignColors.Semantic.info

    init(
        request: QuestionRequest,
        onReply: @escaping @MainActor ([[String]]) async -> Bool,
        onReject: @escaping () -> Void
    ) {
        self.request = request
        self.onReply = onReply
        self.onReject = onReject

        let count = request.questions.count
        _currentTab = State(initialValue: 0)
        _answers = State(initialValue: Array(repeating: [], count: count))
        _customTexts = State(initialValue: Array(repeating: "", count: count))
        _customActive = State(initialValue: Array(repeating: false, count: count))
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 12) {
                header
                progressDots

                Text(question.question)
                    .font(DesignTypography.headline.weight(.semibold))

                Text(question.allowMultiple ? L10n.t(.questionMultiHint) : L10n.t(.questionSingleHint))
                    .font(DesignTypography.meta)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(question.options) { option in
                        optionRow(option)
                    }

                    if question.allowCustom {
                        customInputSection
                    }
                }

                actionButtons
            }
            .padding(DesignSpacing.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-card-\(request.id)")
        .background(accent.opacity(DesignColors.surfaceFill(for: colorScheme)))
        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble.fill")
                .foregroundStyle(accent)
                .font(.title3)

            Text(L10n.t(.questionTitle))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)

            Spacer(minLength: 8)

            Text(L10n.t(.questionOf, Int32(currentTab + 1), Int32(request.questions.count)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<request.questions.count, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 8, height: 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        goToTab(index)
                    }
            }
        }
    }

    private var customInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                activateCustom()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isCustomActive ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isCustomActive ? accent : .secondary)

                    Text(L10n.t(.questionTypeOwnAnswer))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isCustomActive ? accent : .primary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isCustomActive ? Color.blue.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.t(.questionTypeOwnAnswer))
            .accessibilityIdentifier("question-custom-toggle-\(request.id)")
            .accessibilityAddTraits(.isButton)

            if isCustomActive {
                TextField(L10n.t(.questionCustomPlaceholder), text: $customTexts[currentTab])
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("question-custom-field-\(request.id)")
                    .submitLabel(.done)
                    .onTapGesture {
                        isCustomEditing = true
                    }
                    .onSubmit {
                        commitCustom()
                    }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    onReject()
                } label: {
                    Text(L10n.t(.questionDismiss))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                if currentTab > 0 {
                    Button {
                        back()
                    } label: {
                        Text(L10n.t(.questionBack))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                Button {
                    next()
                } label: {
                    Text(currentTab >= request.questions.count - 1 ? L10n.t(.questionSubmit) : L10n.t(.questionNext))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canProceed || isSending)
                .accessibilityIdentifier("question-submit-\(request.id)")
            }
        }
    }

    private var question: QuestionInfo {
        guard request.questions.indices.contains(currentTab) else {
            return QuestionInfo(question: "", header: "", options: [], multiple: false, custom: false)
        }
        return request.questions[currentTab]
    }

    private var isCustomActive: Bool {
        customActive.indices.contains(currentTab) ? customActive[currentTab] : false
    }

    private var canProceed: Bool {
        if hasAnswer(at: currentTab) {
            return true
        }
        return isCustomActive && trimmedCustomText(at: currentTab).isEmpty == false
    }

    private func isSelected(_ option: QuestionOption) -> Bool {
        answers.indices.contains(currentTab) && answers[currentTab].contains(option.label)
    }

    @ViewBuilder
    private func optionRow(_ option: QuestionOption) -> some View {
        let selected = isSelected(option)
        let multiple = question.allowMultiple

        Button {
            selectOption(option)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? (multiple ? "checkmark.square.fill" : "largecircle.fill.circle") : (multiple ? "square" : "circle"))
                    .foregroundStyle(selected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline.weight(.medium))
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.label)
        .accessibilityIdentifier("question-option-\(request.id)-\(option.label)")
        .accessibilityValue(selected ? "selected" : "unselected")
        .accessibilityAddTraits(.isButton)
    }

    private func selectOption(_ option: QuestionOption) {
        if question.allowMultiple {
            toggleMulti(option.label)
        } else {
            selectSingle(option.label)
        }
    }

    private func selectSingle(_ label: String) {
        guard answers.indices.contains(currentTab), customActive.indices.contains(currentTab) else { return }
        answers[currentTab] = [label]
        customActive[currentTab] = false
        isCustomEditing = false
    }

    private func toggleMulti(_ label: String) {
        guard answers.indices.contains(currentTab) else { return }

        if answers[currentTab].contains(label) {
            answers[currentTab].removeAll { $0 == label }
        } else {
            answers[currentTab].append(label)
        }
    }

    private func activateCustom() {
        guard customActive.indices.contains(currentTab), customTexts.indices.contains(currentTab) else { return }

        customActive[currentTab] = true
        isCustomEditing = true

        if !question.allowMultiple {
            answers[currentTab] = []
        }
    }

    private func commitCustom() {
        guard customTexts.indices.contains(currentTab), answers.indices.contains(currentTab) else { return }

        let text = trimmedCustomText(at: currentTab)
        isCustomEditing = false

        if question.allowMultiple {
            let optionLabels = Set(question.options.map(\.label))
            answers[currentTab].removeAll { !optionLabels.contains($0) }
            customTexts[currentTab] = text
            if !text.isEmpty {
                if !answers[currentTab].contains(text) {
                    answers[currentTab].append(text)
                }
                customActive[currentTab] = true
            } else {
                customActive[currentTab] = false
            }
        } else {
            customTexts[currentTab] = text
            customActive[currentTab] = !text.isEmpty
            answers[currentTab] = text.isEmpty ? [] : [text]
        }
    }

    private func next() {
        commitCustomIfNeeded()
        if currentTab >= request.questions.count - 1 {
            submit()
        } else {
            currentTab += 1
            isCustomEditing = false
        }
    }

    private func back() {
        commitCustomIfNeeded()
        guard currentTab > 0 else { return }
        currentTab -= 1
        isCustomEditing = false
    }

    private func submit() {
        guard !isSending else { return }
        isSending = true
        let snapshot = answers
        Task {
            let ok = await onReply(snapshot)
            if !ok {
                isSending = false
            }
        }
    }

    private func goToTab(_ index: Int) {
        guard request.questions.indices.contains(index) else { return }
        commitCustomIfNeeded()
        currentTab = index
        isCustomEditing = false
    }

    private func commitCustomIfNeeded() {
        guard isCustomActive || isCustomEditing else { return }
        commitCustom()
    }

    private func hasAnswer(at index: Int) -> Bool {
        guard answers.indices.contains(index) else { return false }
        if !answers[index].isEmpty {
            return true
        }
        guard customActive.indices.contains(index), customTexts.indices.contains(index) else { return false }
        return customActive[index] && !trimmedCustomText(at: index).isEmpty
    }

    private func trimmedCustomText(at index: Int) -> String {
        guard customTexts.indices.contains(index) else { return "" }
        return customTexts[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dotColor(for index: Int) -> Color {
        if index == currentTab {
            return .blue
        }
        return hasAnswer(at: index) ? .blue.opacity(0.5) : .gray.opacity(0.3)
    }
}
