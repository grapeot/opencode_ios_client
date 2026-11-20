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
    var isEditable: Bool = true
    var requestsFirstResponder: Bool = false
    var suppressesSoftwareKeyboard: Bool = false
    var focusResetEpoch: Int = 0
    var preferredCursorUTF16: Int? = nil
    let placeholder: String
    let autoScrollToBottomOnTextChange: Bool
    let onSubmit: () -> Void
    var onEndEditing: () -> Void = {}
    var onCaretFocusChange: (Bool) -> Void = { _ in }
    var onSelectionUTF16: (NSRange) -> Void = { _ in }
    var onCaretProbe: (String) -> Void = { _ in }

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
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.returnKeyType = .default
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.setSoftwareKeyboardSuppressed(suppressesSoftwareKeyboard)
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
        context.coordinator.onEndEditing = onEndEditing
        context.coordinator.onCaretFocusChange = onCaretFocusChange
        context.coordinator.onSelectionUTF16 = onSelectionUTF16
        context.coordinator.onCaretProbe = onCaretProbe
        context.coordinator.requestsFirstResponder = requestsFirstResponder
        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
        }
        if context.coordinator.wasEditable, !isEditable, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        context.coordinator.wasEditable = isEditable
        uiView.isSelectable = true
        uiView.setSoftwareKeyboardSuppressed(suppressesSoftwareKeyboard)
        context.coordinator.applyFocusReset(epoch: focusResetEpoch, to: uiView)
        if uiView.text != text {
            uiView.text = text
            if let cursor = preferredCursorUTF16, isEditable {
                let length = (text as NSString).length
                uiView.selectedRange = NSRange(location: min(max(0, cursor), length), length: 0)
            }
            if autoScrollToBottomOnTextChange {
                context.coordinator.scrollToBottom(uiView)
            }
        }
        uiView.accessibilityLabel = placeholder
        uiView.onShiftReturn = {
            context.coordinator.insertNewline(into: uiView)
        }
        context.coordinator.updateMarkedTextState(for: uiView)
        context.coordinator.publishProbe(for: uiView)
        if requestsFirstResponder {
            context.coordinator.wasRequestingFocus = true
            if !uiView.isFirstResponder, !context.coordinator.focusScheduled {
                context.coordinator.focusScheduled = true
                DispatchQueue.main.async {
                    context.coordinator.focusScheduled = false
                    guard context.coordinator.requestsFirstResponder, !uiView.isFirstResponder else { return }
                    uiView.becomeFirstResponder()
                }
            }
        } else if context.coordinator.wasRequestingFocus {
            context.coordinator.wasRequestingFocus = false
            context.coordinator.focusScheduled = false
            if uiView.isFirstResponder {
                // Resigning synchronously here can re-enter SwiftUI's focus
                // graph while updateUIView is applying the send state.
                let coordinator = context.coordinator
                DispatchQueue.main.async { [weak uiView, weak coordinator] in
                    guard let uiView, let coordinator, uiView.window != nil,
                          !coordinator.requestsFirstResponder, uiView.isFirstResponder else { return }
                    uiView.resignFirstResponder()
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var hasMarkedText: Bool
        private let onSubmit: () -> Void
        private var isInsertingShiftNewline = false
        var onEndEditing: () -> Void = {}
        var onCaretFocusChange: (Bool) -> Void = { _ in }
        var onSelectionUTF16: (NSRange) -> Void = { _ in }
        var onCaretProbe: (String) -> Void = { _ in }
        var focusScheduled = false
        var requestsFirstResponder = false
        var wasRequestingFocus = false
        var wasEditable = true
        var seenFocusResetEpoch = 0

        func applyFocusReset(epoch: Int, to textView: UITextView) {
            guard epoch != seenFocusResetEpoch else { return }
            seenFocusResetEpoch = epoch
            focusScheduled = false
            if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }

        init(text: Binding<String>, hasMarkedText: Binding<Bool>, onSubmit: @escaping () -> Void) {
            _text = text
            _hasMarkedText = hasMarkedText
            self.onSubmit = onSubmit
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            onCaretFocusChange(true)
            onSelectionUTF16(textView.selectedRange)
            publishProbe(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            onCaretFocusChange(false)
            onEndEditing()
            publishProbe(for: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            updateMarkedTextState(for: textView)
            onSelectionUTF16(textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateMarkedTextState(for: textView)
            onSelectionUTF16(textView.selectedRange)
            publishProbe(for: textView)
        }

        func publishProbe(for textView: UITextView) {
            let range = textView.selectedRange
            let position = textView.selectedTextRange?.start ?? textView.beginningOfDocument
            let caret = textView.caretRect(for: position)
            let keyboard = (textView as? IMEAwareTextView)?.softwareKeyboardSuppressed == true ? "suppressed" : "system"
            let value = "first=\(textView.isFirstResponder ? 1 : 0);editable=\(textView.isEditable ? 1 : 0);keyboard=\(keyboard);range=\(range.location),\(range.length);caret=\(Int(caret.width.rounded()))x\(Int(caret.height.rounded()))"
            onCaretProbe(value)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText: String
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

        func scrollToBottom(_ textView: UITextView) {
            let end = NSRange(location: (textView.text as NSString).length, length: 0)
            textView.selectedRange = end
            textView.layoutIfNeeded()
            textView.scrollRangeToVisible(end)
            let minY = -textView.adjustedContentInset.top
            let maxY = max(minY, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
            textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: maxY), animated: false)
        }
    }
}

final class ZeroHeightInputView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 0)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: 0)
    }
}

class IMEAwareTextView: UITextView {
    var onShiftReturn: (() -> Void)?
    private(set) var softwareKeyboardSuppressed = false
    private let suppressedInput = ZeroHeightInputView(frame: .zero)
    #if os(iOS)
    private var savedLeading: [UIBarButtonItemGroup] = []
    private var savedTrailing: [UIBarButtonItemGroup] = []
    private var didSaveAssistant = false
    #endif

    func setSoftwareKeyboardSuppressed(_ suppressed: Bool) {
        let inputMatches = suppressed ? inputView === suppressedInput : inputView == nil
        guard softwareKeyboardSuppressed != suppressed || !inputMatches else { return }
        softwareKeyboardSuppressed = suppressed
        if suppressed {
            captureAssistantBarIfNeeded()
            if inputView !== suppressedInput {
                inputView = suppressedInput
            }
            clearAssistantBar()
        } else {
            inputView = nil
            restoreAssistantBarIfSaved()
        }
        if isFirstResponder {
            reloadInputViews()
        }
    }

    #if os(iOS)
    private func captureAssistantBarIfNeeded() {
        if !didSaveAssistant {
            let leading = inputAssistantItem.leadingBarButtonGroups
            let trailing = inputAssistantItem.trailingBarButtonGroups
            if !leading.isEmpty || !trailing.isEmpty {
                savedLeading = leading
                savedTrailing = trailing
                didSaveAssistant = true
            }
        }
    }

    private func clearAssistantBar() {
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }

    private func restoreAssistantBarIfSaved() {
        if didSaveAssistant, !savedLeading.isEmpty || !savedTrailing.isEmpty {
            inputAssistantItem.leadingBarButtonGroups = savedLeading
            inputAssistantItem.trailingBarButtonGroups = savedTrailing
        }
    }
    #else
    private func captureAssistantBarIfNeeded() {}
    private func clearAssistantBar() {}
    private func restoreAssistantBarIfSaved() {}
    #endif

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
