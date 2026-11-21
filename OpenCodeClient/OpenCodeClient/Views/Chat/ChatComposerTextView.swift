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
        textView.onShiftReturn = { [weak coordinator = context.coordinator, weak textView] in
            guard let textView else { return }
            coordinator?.insertNewline(into: textView)
        }
        textView.onKeyWindowAvailable = { [weak coordinator = context.coordinator, weak textView] in
            guard let textView else { return }
            coordinator?.enqueueInputUpdate(for: textView)
        }
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: IMEAwareTextView, context: Context) {
        context.coordinator.onEndEditing = onEndEditing
        context.coordinator.onCaretFocusChange = onCaretFocusChange
        context.coordinator.onSelectionUTF16 = onSelectionUTF16
        context.coordinator.onCaretProbe = onCaretProbe
        context.coordinator.scheduleInputUpdate(
            for: uiView, editable: isEditable, requestsFocus: requestsFirstResponder,
            suppressKeyboard: suppressesSoftwareKeyboard, resetEpoch: focusResetEpoch
        )
        if uiView.text != text {
            context.coordinator.applyingProgrammaticText(to: uiView) {
                uiView.text = text
                if let cursor = preferredCursorUTF16, isEditable {
                    let length = (text as NSString).length
                    uiView.selectedRange = NSRange(location: min(max(0, cursor), length), length: 0)
                }
                if autoScrollToBottomOnTextChange {
                    context.coordinator.scrollToBottom(uiView)
                }
            }
        }
        uiView.accessibilityLabel = placeholder
        context.coordinator.scheduleInputFeedback(for: uiView)
    }

    static func dismantleUIView(_ uiView: IMEAwareTextView, coordinator: Coordinator) {
        uiView.delegate = nil
        uiView.onShiftReturn = nil
        uiView.onKeyWindowAvailable = nil
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
        private var inputUpdateScheduled = false
        private var requestedFocus = false
        private var pendingFocusDismissal = false
        private var observedResetEpoch = 0
        private var pendingReset = false
        private var desiredInput = (editable: true, suppressKeyboard: false)
        private var isApplyingProgrammaticText = false
        private var inputFeedbackScheduled = false
        private var selectionFeedbackPending = false

        func scheduleInputUpdate(
            for textView: IMEAwareTextView, editable: Bool, requestsFocus: Bool,
            suppressKeyboard: Bool, resetEpoch: Int
        ) {
            if resetEpoch != observedResetEpoch {
                observedResetEpoch = resetEpoch
                pendingReset = true
            } else if requestsFocus && !requestedFocus {
                // A new explicit open supersedes a reset from an earlier update.
                pendingReset = false
            }
            pendingFocusDismissal = !requestsFocus && (pendingFocusDismissal || requestedFocus)
            requestedFocus = requestsFocus
            desiredInput = (editable, suppressKeyboard)
            enqueueInputUpdate(for: textView)
        }

        func enqueueInputUpdate(for textView: IMEAwareTextView) {
            guard !inputUpdateScheduled else { return }
            guard pendingReset || pendingFocusDismissal ||
                    textView.isEditable != desiredInput.editable || textView.softwareKeyboardSuppressed != desiredInput.suppressKeyboard ||
                    (requestedFocus && desiredInput.editable && !textView.isFirstResponder && textView.window?.isKeyWindow == true) else { return }
            inputUpdateScheduled = true
            // Responder changes and keyboard reloads can query SwiftUI's focus graph.
            // Apply the latest input state only after updateUIView has returned.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.inputUpdateScheduled = false
                guard let textView, textView.delegate === self else { return }
                self.applyInputUpdate(to: textView)
            }
        }

        private func applyInputUpdate(to textView: IMEAwareTextView) {
            let input = desiredInput
            let resetsFocus = pendingReset
            let dismissesFocus = pendingFocusDismissal
            let requestsFocus = requestedFocus
            pendingReset = false
            pendingFocusDismissal = false
            let resignsFocus = textView.isFirstResponder && (resetsFocus || dismissesFocus || !input.editable)
            if resignsFocus { textView.resignFirstResponder() }
            if textView.isEditable != input.editable { textView.isEditable = input.editable }
            if !textView.isSelectable { textView.isSelectable = true }
            textView.setSoftwareKeyboardSuppressed(input.suppressKeyboard)
            if input.editable, requestsFocus, !resetsFocus, !resignsFocus,
               !textView.isFirstResponder, textView.window?.isKeyWindow == true {
                textView.becomeFirstResponder()
            }
            publishProbe(for: textView)
        }

        func applyingProgrammaticText(to textView: IMEAwareTextView, _ update: () -> Void) {
            isApplyingProgrammaticText = true
            defer { isApplyingProgrammaticText = false }
            update()
            selectionFeedbackPending = true
            scheduleInputFeedback(for: textView)
        }

        func scheduleInputFeedback(for textView: IMEAwareTextView) {
            guard !inputFeedbackScheduled else { return }
            inputFeedbackScheduled = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.inputFeedbackScheduled = false
                guard let textView, textView.delegate === self else { return }
                self.updateMarkedTextState(for: textView)
                if self.selectionFeedbackPending {
                    self.selectionFeedbackPending = false
                    self.onSelectionUTF16(textView.selectedRange)
                }
                self.publishProbe(for: textView)
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
            guard !isApplyingProgrammaticText else { return }
            text = textView.text
            updateMarkedTextState(for: textView)
            onSelectionUTF16(textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticText else { return }
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
            let marked = textView.markedTextRange != nil
            if hasMarkedText != marked { hasMarkedText = marked }
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
    var onKeyWindowAvailable: (() -> Void)?
    private(set) var softwareKeyboardSuppressed = false
    private let suppressedInput = ZeroHeightInputView(frame: .zero)

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIWindow.didBecomeKeyNotification, object: nil)
        if let window {
            center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: UIWindow.didBecomeKeyNotification, object: window)
            if window.isKeyWindow { onKeyWindowAvailable?() }
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) { onKeyWindowAvailable?() }
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
