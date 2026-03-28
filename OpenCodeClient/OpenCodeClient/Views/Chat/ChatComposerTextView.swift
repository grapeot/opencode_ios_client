import SwiftUI

#if canImport(UIKit)
import UIKit

enum ChatComposerKeyAction: Equatable {
    case system
    case insertNewline
    case submit

    static func action(for replacementText: String, hasMarkedText: Bool, isShiftReturn: Bool) -> ChatComposerKeyAction {
        guard replacementText == "\n" else { return .system }
        guard !hasMarkedText else { return .system }
        return .insertNewline
    }
}

enum ChatComposerSendGate {
    static func canSend(text: String, isSending: Bool, hasMarkedText: Bool) -> Bool {
        guard !isSending, !hasMarkedText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ChatComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var hasMarkedText: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, hasMarkedText: $hasMarkedText, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> IMEAwareTextView {
        let textView = IMEAwareTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.maximumNumberOfLines = 8
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.returnKeyType = .default
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.accessibilityIdentifier = "chat-input"
        textView.accessibilityLabel = placeholder
        textView.onShiftReturn = {
            context.coordinator.insertNewline(into: textView)
        }
        textView.text = text
        context.coordinator.updateMarkedTextState(for: textView)
        return textView
    }

    func updateUIView(_ uiView: IMEAwareTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.accessibilityLabel = placeholder
        uiView.onShiftReturn = {
            context.coordinator.insertNewline(into: uiView)
        }
        context.coordinator.updateMarkedTextState(for: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var hasMarkedText: Bool
        private let onSubmit: () -> Void
        private var isInsertingShiftNewline = false

        init(text: Binding<String>, hasMarkedText: Binding<Bool>, onSubmit: @escaping () -> Void) {
            _text = text
            _hasMarkedText = hasMarkedText
            self.onSubmit = onSubmit
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            updateMarkedTextState(for: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateMarkedTextState(for: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacementText: String
        ) -> Bool {
            let action = ChatComposerKeyAction.action(
                for: replacementText,
                hasMarkedText: textView.markedTextRange != nil,
                isShiftReturn: isInsertingShiftNewline
            )

            switch action {
            case .system:
                return true
            case .insertNewline:
                isInsertingShiftNewline = false
                return true
            case .submit:
                onSubmit()
                return false
            }
        }

        func insertNewline(into textView: UITextView) {
            isInsertingShiftNewline = true
            textView.insertText("\n")
        }

        func updateMarkedTextState(for textView: UITextView) {
            hasMarkedText = textView.markedTextRange != nil
        }
    }
}

final class IMEAwareTextView: UITextView {
    var onShiftReturn: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\r", modifierFlags: [.shift], action: #selector(handleShiftReturn))
        ]
    }

    @objc private func handleShiftReturn() {
        onShiftReturn?()
    }
}
#endif
