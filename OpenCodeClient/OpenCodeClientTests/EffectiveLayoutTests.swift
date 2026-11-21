import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OpenCodeClient

struct EffectiveLayoutTests {
    @Test func measuredWorkspaceSeparatesSidebarFromFilesColumn() {
        let outer = WorkspacePresentation.resolve(preference: .automatic, width: 445, widthClass: .compact, shortWindow: false)
        let tall = WorkspacePresentation.resolve(preference: .automatic, width: 626, widthClass: .compact, shortWindow: false)
        let wide = WorkspacePresentation.resolve(preference: .automatic, width: 875, widthClass: .regular, shortWindow: false)
        #expect(outer == .compact)
        #expect(tall == .sidebar)
        #expect(tall.previewLayout == .compact)
        #expect(wide == .wide)
        #expect(WorkspacePresentation.resolve(preference: .focus, width: 875, widthClass: .regular, shortWindow: false) == .compact)
    }
    @Test func automaticFollowsRegularWidth() {
        #expect(EffectiveLayoutResolver.resolve(preference: .automatic, width: .regular) == .regular)
    }

    @Test func automaticCompactAndUnspecifiedStayCompact() {
        #expect(EffectiveLayoutResolver.resolve(preference: .automatic, width: .compact) == .compact)
        #expect(EffectiveLayoutResolver.resolve(preference: .automatic, width: .unspecified) == .compact)
    }

    @Test func focusIgnoresRegularWidth() {
        #expect(EffectiveLayoutResolver.resolve(preference: .focus, width: .regular) == .compact)
        #expect(EffectiveLayoutResolver.resolve(preference: .focus, width: .compact) == .compact)
    }

    @Test func missingOrUnknownLayoutPreferenceStaysAutomatic() {
        #expect(LayoutPreference.resolved(from: nil) == .automatic)
        #expect(LayoutPreference.resolved(from: "") == .automatic)
        #expect(LayoutPreference.resolved(from: "phone") == .automatic)
        #expect(LayoutPreference.resolved(from: "focus") == .focus)
    }

    @Test func previewMigratesColumnToInlineWhenEnteringFocus() {
        let migrated = LayoutPreviewMigration.migrate(
            from: .regular,
            to: .compact,
            slots: LayoutPreviewSlots(inlinePath: nil, inlineWorkspace: nil, columnPath: "notes.md", columnWorkspace: "/work")
        )
        #expect(migrated.inlinePath == "notes.md")
        #expect(migrated.inlineWorkspace == "/work")
        #expect(migrated.columnPath == nil)
    }

    @Test func previewMigratesInlineToColumnWhenLeavingFocus() {
        let migrated = LayoutPreviewMigration.migrate(
            from: .compact,
            to: .regular,
            slots: LayoutPreviewSlots(inlinePath: "notes.md", inlineWorkspace: "/work", columnPath: nil, columnWorkspace: nil)
        )
        #expect(migrated.columnPath == "notes.md")
        #expect(migrated.columnWorkspace == "/work")
        #expect(migrated.inlinePath == nil)
    }

    @Test func filesPushBecomesColumnThenInline() {
        let compactToRegular = PreviewLayoutTransition.apply(
            from: .compact,
            to: .regular,
            input: PreviewLayoutInput(
                slots: .empty,
                filesPath: ["notes.txt"],
                filesWorkspace: "/tmp/w06-files",
                filesHostMatches: true,
                pendingPath: nil,
                pendingWorkspace: nil,
                pendingHostMatches: true
            )
        )
        #expect(compactToRegular.slots.columnPath == "notes.txt")
        #expect(compactToRegular.slots.columnWorkspace == "/tmp/w06-files")
        #expect(compactToRegular.filesPath.isEmpty)

        let back = PreviewLayoutTransition.apply(
            from: .regular,
            to: .compact,
            input: PreviewLayoutInput(
                slots: compactToRegular.slots,
                filesPath: compactToRegular.filesPath,
                filesWorkspace: "/tmp/w06-files",
                filesHostMatches: true,
                pendingPath: nil,
                pendingWorkspace: nil,
                pendingHostMatches: true
            )
        )
        #expect(back.slots.inlinePath == "notes.txt")
        #expect(back.slots.inlineWorkspace == "/tmp/w06-files")
        #expect(back.slots.columnPath == nil)
    }

    @Test func foreignHostFilesPushIsNotRestored() {
        let migrated = PreviewLayoutTransition.apply(
            from: .compact,
            to: .regular,
            input: PreviewLayoutInput(
                slots: .empty,
                filesPath: ["secret.txt"],
                filesWorkspace: "/other",
                filesHostMatches: false,
                pendingPath: "pending.md",
                pendingWorkspace: "/other",
                pendingHostMatches: false
            )
        )
        #expect(migrated.slots == .empty)
        #expect(migrated.filesPath.isEmpty)
        #expect(migrated.pendingPath == nil)
    }

    @Test func visibleColumnReplacesHiddenInline() {
        let slots = LayoutPreviewSlots(
            inlinePath: "old.md",
            inlineWorkspace: "/old",
            columnPath: "current.md",
            columnWorkspace: "/current"
        )
        let migrated = LayoutPreviewMigration.migrate(from: .regular, to: .compact, slots: slots)
        #expect(migrated.inlinePath == "current.md")
        #expect(migrated.inlineWorkspace == "/current")
        #expect(migrated.columnPath == nil)
    }

    @Test func visibleInlineReplacesHiddenColumn() {
        let slots = LayoutPreviewSlots(
            inlinePath: "current.md",
            inlineWorkspace: "/current",
            columnPath: "old.md",
            columnWorkspace: "/old"
        )
        let migrated = LayoutPreviewMigration.migrate(from: .compact, to: .regular, slots: slots)
        #expect(migrated.columnPath == "current.md")
        #expect(migrated.columnWorkspace == "/current")
        #expect(migrated.inlinePath == nil)
    }

    @Test func newerPendingOpenReplacesVisibleSlot() {
        let migrated = PreviewLayoutTransition.apply(
            from: .regular,
            to: .compact,
            input: PreviewLayoutInput(
                slots: LayoutPreviewSlots(inlinePath: "old.md", inlineWorkspace: "/old", columnPath: "seen.md", columnWorkspace: "/seen"),
                columnSequence: 2,
                inlineSequence: 1,
                filesPath: [],
                filesWorkspace: nil,
                filesHostMatches: true,
                pendingPath: "link.md",
                pendingWorkspace: "/link",
                pendingHostMatches: true,
                pendingSequence: 3
            )
        )
        #expect(migrated.slots.inlinePath == "link.md")
        #expect(migrated.slots.columnPath == nil)
        #expect(migrated.pendingPath == nil)
    }

    @Test func olderPendingOpenDoesNotReplaceVisibleSlot() {
        let migrated = PreviewLayoutTransition.apply(
            from: .regular,
            to: .compact,
            input: PreviewLayoutInput(
                slots: LayoutPreviewSlots(inlinePath: "old.md", inlineWorkspace: "/old", columnPath: "seen.md", columnWorkspace: "/seen"),
                columnSequence: 5,
                inlineSequence: 1,
                filesPath: [],
                filesWorkspace: nil,
                filesHostMatches: true,
                pendingPath: "link.md",
                pendingWorkspace: "/link",
                pendingHostMatches: true,
                pendingSequence: 3
            )
        )
        #expect(migrated.slots.inlinePath == "seen.md")
        #expect(migrated.slots.inlineWorkspace == "/seen")
        #expect(migrated.slots.columnPath == nil)
    }

    @MainActor
    @Test func emptyFilesPathDoesNotArmShrinkSuppression() {
        let state = makePreviewState()
        state.filesNavigationPath = []
        state.clearFilesNavigationPathIgnoringNextShrink()
        #expect(state.ignoreNextFilesPathShrink == false)

        state.filesNavigationPath = ["notes.txt"]
        state.clearFilesNavigationPathIgnoringNextShrink()
        #expect(state.ignoreNextFilesPathShrink == true)
        #expect(state.filesNavigationPath.isEmpty)
    }

    @MainActor
    @Test func hostSwitchClearsUnstampedPendingBeforeLayoutApply() {
        let state = makePreviewState()
        let oldHost = state.currentHostProfileID
        state.previewHostID = oldHost
        let owner = ExternalFileOpenOwner(host: state.captureHostRequestSnapshot(), sessionID: nil)
        state.stageExternalFileOpen(path: "notes.md", workspaceDirectory: "/old", owner: owner)
        let newHost = UUID()
        state.currentHostProfileID = newHost
        state.discardPreviewIfHostChanged(from: oldHost, to: newHost)
        state.applyPreviewLayout(from: .compact, to: .regular)
        #expect(state.fileToOpenInFilesTab == nil)
        #expect(state.previewFilePath == nil)
        #expect(state.inlinePreviewPath == nil)
    }

    @MainActor
    @Test func latePreviousHostOpenCallbackAfterCleanupDoesNotCreatePreview() {
        let state = makePreviewState()
        let hostA = state.captureHostRequestSnapshot()
        state.currentSessionID = "session-a"
        state.previewHostID = hostA.hostProfileID
        state.previewSessionID = "session-a"
        let openFromHostA = capturedOpen(state, owner: ExternalFileOpenOwner(host: hostA, sessionID: "session-a"))
        let hostB = UUID()
        state.currentHostProfileID = hostB
        state.currentSessionID = "session-b"
        state.discardPreviewIfHostChanged(from: hostA.hostProfileID, to: hostB)
        let sequenceBeforeDelivery = state.previewEventSequence
        openFromHostA("secret.md", "/a")
        state.adoptPendingFileOpen(layout: .regular)
        state.applyPreviewLayout(from: .compact, to: .regular)
        #expect(state.previewEventSequence == sequenceBeforeDelivery)
        #expect(state.pendingEventSequence == 0)
        #expect(state.fileToOpenInFilesTab == nil)
        #expect(state.pendingFileOpenOwner == nil)
        #expect(state.previewFilePath == nil)
        #expect(state.inlinePreviewPath == nil)
        #expect(state.previewHostID == nil)
        #expect(state.previewSessionID == nil)
    }

    @MainActor
    @Test func currentHostOpenCallbackAdoptsSourceSession() {
        let state = makePreviewState()
        state.currentSessionID = "session-a"
        let owner = ExternalFileOpenOwner(host: state.captureHostRequestSnapshot(), sessionID: "session-a")
        let open = capturedOpen(state, owner: owner)
        open("notes.md", "/work")
        #expect(state.fileToOpenInFilesTab == "notes.md")
        #expect(state.pendingFileOpenOwner == owner)
        #expect(ExternalFileOpenRouting.shouldAdopt(sequence: state.pendingEventSequence, path: state.fileToOpenInFilesTab))
        state.adoptPendingFileOpen(layout: .regular)
        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewFileWorkspaceDirectory == "/work")
        #expect(state.previewHostID == owner.host.hostProfileID)
        #expect(state.previewSessionID == "session-a")
        #expect(state.fileToOpenInFilesTab == nil)
    }

    @MainActor
    @Test func filesOpenCallbackStaysUnboundToCurrentSession() {
        let state = makePreviewState()
        state.currentSessionID = "session-a"
        let owner = ExternalFileOpenOwner(host: state.captureHostRequestSnapshot(), sessionID: nil)
        capturedOpen(state, owner: owner)("notes.md", "/files")
        state.adoptPendingFileOpen(layout: .compact)
        #expect(state.inlinePreviewPath == "notes.md")
        #expect(state.inlinePreviewWorkspaceDirectory == "/files")
        #expect(state.previewSessionID == nil)
        #expect(state.previewHostID == owner.host.hostProfileID)
    }

    @MainActor
    @Test func sessionBoundOpenRejectsAfterSessionSwitch() {
        let state = makePreviewState()
        state.currentSessionID = "session-a"
        let owner = ExternalFileOpenOwner(host: state.captureHostRequestSnapshot(), sessionID: "session-a")
        let open = capturedOpen(state, owner: owner)
        state.currentSessionID = "session-b"
        let sequence = state.previewEventSequence
        open("notes.md", "/a")
        state.adoptPendingFileOpen(layout: .regular)
        #expect(state.previewEventSequence == sequence)
        #expect(state.fileToOpenInFilesTab == nil)
        #expect(state.previewFilePath == nil)
        #expect(state.previewSessionID == nil)
    }

    @MainActor
    @Test func layoutApplyDropsPendingOwnedByPreviousHost() {
        let state = makePreviewState()
        state.currentSessionID = "session-a"
        let owner = ExternalFileOpenOwner(host: state.captureHostRequestSnapshot(), sessionID: "session-a")
        state.stageExternalFileOpen(path: "notes.md", workspaceDirectory: "/a", owner: owner)
        #expect(state.pendingEventSequence > 0)
        state.currentHostProfileID = UUID()
        state.applyPreviewLayout(from: .compact, to: .regular)
        #expect(state.previewFilePath == nil)
        #expect(state.inlinePreviewPath == nil)
        #expect(state.fileToOpenInFilesTab == nil)
        #expect(state.pendingFileOpenOwner == nil)
    }

    @MainActor
    @Test func samePathDifferentWorkspacePendingIsNotDroppedByPathIdentity() {
        let state = makePreviewState()
        let owner = ExternalFileOpenOwner(host: state.captureHostRequestSnapshot(), sessionID: nil)
        state.stageExternalFileOpen(path: "notes.md", workspaceDirectory: "/a", owner: owner)
        let first = state.pendingEventSequence
        state.adoptPendingFileOpen(layout: .compact)
        #expect(state.inlinePreviewWorkspaceDirectory == "/a")
        state.stageExternalFileOpen(path: "notes.md", workspaceDirectory: "/b", owner: owner)
        #expect(state.fileToOpenInFilesTab == "notes.md")
        #expect(state.pendingEventSequence != first)
        #expect(ExternalFileOpenRouting.shouldAdopt(sequence: state.pendingEventSequence, path: "notes.md"))
        #expect(!ExternalFileOpenRouting.shouldAdopt(sequence: 0, path: "notes.md"))
        state.adoptPendingFileOpen(layout: .compact)
        #expect(state.inlinePreviewPath == "notes.md")
        #expect(state.inlinePreviewWorkspaceDirectory == "/b")
    }

    @Test func layoutChangeDoesNotForceBottomScroll() {
        #expect(ChatViewportPolicy.forcesBottom(on: .layoutChange) == false)
        #expect(ChatViewportPolicy.forcesBottom(on: .sessionChange) == true)
    }

    @Test func pasteAppendsWithExplicitNewlineAndKeepsOrder() {
        #expect(ComposerDraftMerge.appending(draft: "", addition: "pasted") == "pasted")
        #expect(ComposerDraftMerge.appending(draft: "draft", addition: "pasted") == "draft\npasted")
        #expect(ComposerDraftMerge.joinedPaste(["a", "", "b"]) == "a\nb")
    }

    @Test func editPasteRespectsSelectionOutsideSpeechSpan() {
        let placement = ComposerPastePlanner.placement(
            hasCaretFocus: true,
            hasMarkedText: false,
            selectionUTF16: NSRange(location: 5, length: 0),
            speechOwnedUTF16End: 5
        )
        #expect(placement == .insert(NSRange(location: 5, length: 0)))
        let inserted = ComposerDraftMerge.inserting(draft: "hello", addition: "X", selectionUTF16: NSRange(location: 5, length: 0))
        #expect(inserted.text == "helloX")
        #expect(inserted.cursorUTF16 == 6)
    }

    @Test func pasteInsideLiveTranscriptAppendsInsteadOfReplacingSpan() {
        let placement = ComposerPastePlanner.placement(
            hasCaretFocus: true,
            hasMarkedText: false,
            selectionUTF16: NSRange(location: 2, length: 0),
            speechOwnedUTF16End: 8
        )
        #expect(placement == .append)
    }

    @Test func markedTextDefersPaste() {
        #expect(
            ComposerPastePlanner.placement(
                hasCaretFocus: true,
                hasMarkedText: true,
                selectionUTF16: NSRange(location: 1, length: 0),
                speechOwnedUTF16End: nil
            ) == .deferUntilMarkedTextEnds
        )
    }

    @Test func nonEditingPasteAppends() {
        #expect(
            ComposerPastePlanner.placement(
                hasCaretFocus: false,
                hasMarkedText: false,
                selectionUTF16: NSRange(location: 1, length: 0),
                speechOwnedUTF16End: nil
            ) == .append
        )
    }

    @Test func transcriptUpdateKeepsPasteTail() {
        var protector = SpeechDraftProtector()
        protector.begin(prefix: "draft", sessionID: "s1")
        let first = protector.render(prefix: "draft", transcript: "hello")
        #expect(first == "draft hello")
        protector.noteVisibleText(ComposerDraftMerge.appending(draft: first, addition: "pasted"))
        let second = protector.render(prefix: "draft", transcript: "hello there")
        #expect(second == "draft hello there\npasted")
        #expect(protector.preservedTail(for: "s1") == "pasted")
    }

    @Test func markedTextBlocksComposerBindingAssignment() {
        #expect(ComposerFocusPolicy.shouldAssignComposerText(hasMarkedText: true) == false)
        #expect(ComposerFocusPolicy.shouldAssignComposerText(hasMarkedText: false) == true)
    }

    @Test func voiceFirstStaysEditableWithoutAutoFocusUntilExplicitKeyboard() {
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: false, isEditing: false))
        #expect(!ComposerFocusPolicy.suppressesSoftwareKeyboard(voiceFirst: false, isEditing: false))
        #expect(!ComposerFocusPolicy.requestsFirstResponder(voiceFirst: false, isEditing: false))
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: true, isEditing: false))
        #expect(ComposerFocusPolicy.suppressesSoftwareKeyboard(voiceFirst: true, isEditing: false))
        #expect(!ComposerFocusPolicy.requestsFirstResponder(voiceFirst: true, isEditing: false))
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: true, isEditing: true))
        #expect(!ComposerFocusPolicy.suppressesSoftwareKeyboard(voiceFirst: true, isEditing: true))
        #expect(ComposerFocusPolicy.requestsFirstResponder(voiceFirst: true, isEditing: true))
    }

    @Test func focusedCaretPasteInsertsWithoutSoftwareKeyboard() {
        let placement = ComposerPastePlanner.placement(
            hasCaretFocus: true,
            hasMarkedText: false,
            selectionUTF16: NSRange(location: 2, length: 0),
            speechOwnedUTF16End: nil
        )
        #expect(placement == .insert(NSRange(location: 2, length: 0)))
        let inserted = ComposerDraftMerge.inserting(
            draft: "hello",
            addition: "X",
            selectionUTF16: NSRange(location: 2, length: 0)
        )
        #expect(inserted.text == "heXllo")
    }

    @MainActor
    @Test func textViewSeparatesCaretFocusFromSoftwareKeyboard() {
        let previousKey = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let textView = ReloadCountingTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        textView.text = "hello"
        textView.isEditable = true
        textView.isSelectable = true
        textView.setSoftwareKeyboardSuppressed(true)
        textView.selectedRange = NSRange(location: 2, length: 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        window.addSubview(textView)
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
            window.resignKey()
            previousKey?.makeKey()
        }
        window.makeKeyAndVisible()
        textView.layoutIfNeeded()
        #expect(textView.becomeFirstResponder())
        let reloadsAfterFocus = textView.reloadCount
        textView.setSoftwareKeyboardSuppressed(true)
        #expect(textView.reloadCount == reloadsAfterFocus)
        #expect(textView.isFirstResponder)
        #expect(textView.isEditable)
        #expect(textView.softwareKeyboardSuppressed)
        #expect(textView.inputView is ZeroHeightInputView)
        #expect(textView.inputView?.intrinsicContentSize.height == 0)
        let caret = textView.caretRect(for: textView.selectedTextRange!.start)
        #expect(caret.height > 0)
        textView.setSoftwareKeyboardSuppressed(false)
        #expect(textView.reloadCount == reloadsAfterFocus + 1)
        #expect(textView.inputView == nil)
        #expect(textView.isFirstResponder)
    }

    @MainActor
    @Test func tapFocusResignsAfterSessionUpdateWithoutReenteringUpdate() async {
        let previousKey = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let textView = IMEAwareTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        textView.text = "hello"
        textView.isEditable = true
        textView.setSoftwareKeyboardSuppressed(true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        window.addSubview(textView)
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
            window.resignKey()
            previousKey?.makeKey()
        }
        window.makeKeyAndVisible()
        #expect(textView.becomeFirstResponder())
        #expect(textView.isFirstResponder)
        let coordinator = ChatComposerTextView.Coordinator(
            text: .constant("hello"),
            hasMarkedText: .constant(false),
            onSubmit: {}
        )
        textView.delegate = coordinator
        coordinator.scheduleInputUpdate(for: textView, editable: true, requestsFocus: false, suppressKeyboard: true, resetEpoch: 1)
        // Another representable update in the same turn must not swallow the reset.
        coordinator.scheduleInputUpdate(for: textView, editable: true, requestsFocus: false, suppressKeyboard: true, resetEpoch: 1)
        #expect(textView.isFirstResponder)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(!textView.isFirstResponder)
        #expect(textView.becomeFirstResponder())
        coordinator.scheduleInputUpdate(for: textView, editable: true, requestsFocus: false, suppressKeyboard: true, resetEpoch: 1)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(textView.isFirstResponder)

        // A later explicit open should keep a tap-focused caret and show the keyboard.
        coordinator.scheduleInputUpdate(for: textView, editable: true, requestsFocus: false, suppressKeyboard: true, resetEpoch: 2)
        coordinator.scheduleInputUpdate(for: textView, editable: true, requestsFocus: true, suppressKeyboard: false, resetEpoch: 2)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(textView.isFirstResponder)
        #expect(!textView.softwareKeyboardSuppressed)

        coordinator.scheduleInputUpdate(for: textView, editable: true, requestsFocus: false, suppressKeyboard: true, resetEpoch: 3)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(!textView.isFirstResponder)
        #expect(textView.softwareKeyboardSuppressed)
    }

    @MainActor
    @Test func pasteCallbackInsertsAtMiddleSelection() async {
        let coordinator = ComposerPasteButton.Coordinator()
        var selection = NSRange(location: 1, length: 0)
        var merged = ""
        coordinator.beginPaste = {
            let captured = selection
            return { parts in
                let addition = ComposerDraftMerge.joinedPaste(parts)
                merged = ComposerDraftMerge.inserting(
                    draft: "ab",
                    addition: addition,
                    selectionUTF16: captured
                ).text
            }
        }
        let provider = NSItemProvider(object: "FOCUS_VOICE_PASTE_SENTINEL" as NSString)
        coordinator.paste(itemProviders: [provider])
        for _ in 0..<50 where merged.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(merged == "aFOCUS_VOICE_PASTE_SENTINELb")
        #expect(selection.location == 1)
    }

    @Test func pasteHitTargetStaysAtLeastFortyFour() {
        #expect(ComposerHitTarget.minimum >= 44)
    }

    @MainActor
    @Test func layoutAndVoiceFirstDefaultsStayCompatibleAndRoundTrip() {
        let defaults = UserDefaults(suiteName: "opencode.tests.layout.\(UUID().uuidString)")!
        let state = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
        #expect(state.layoutPreference == .automatic)
        #expect(state.voiceFirstInput == false)

        state.layoutPreference = .focus
        state.voiceFirstInput = true
        let restored = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
        #expect(restored.layoutPreference == .focus)
        #expect(restored.voiceFirstInput == true)

        defaults.set("nope", forKey: AppState.layoutPreferenceKey)
        let unknown = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
        #expect(unknown.layoutPreference == .automatic)
    }

    @Test func previewWorkspacePinKeepsServerDefaultDistinctFromLiveSession() {
        #expect(PreviewWorkspacePin.freeze(explicit: "/given", sessionDirectory: "/live") == "/given")
        #expect(PreviewWorkspacePin.freeze(explicit: "", sessionDirectory: "/live") == "")
        #expect(PreviewWorkspacePin.freeze(explicit: nil, sessionDirectory: "/live") == "/live")
        #expect(PreviewWorkspacePin.freeze(explicit: nil, sessionDirectory: nil) == "")
        #expect(PreviewWorkspacePin.freeze(explicit: nil, sessionDirectory: "") == "")
        #expect(PreviewWorkspacePin.previewDirectory(stored: nil) == "")
        #expect(PreviewWorkspacePin.previewDirectory(stored: "") == "")
        #expect(PreviewWorkspacePin.previewDirectory(stored: "/given") == "/given")
    }

    @MainActor
    @Test func regularChatColumnKeepsPinnedFileAcrossSessionSwitch() async throws {
        let api = MockAPIClient()
        let state = makePreviewState(apiClient: api)
        state.sessions = [
            previewSession(id: "session-a", directory: "/proj/old"),
            previewSession(id: "session-b", directory: "/proj/new"),
        ]
        state.currentSessionID = "session-a"
        let host = state.currentHostProfileID
        state.presentChatFilePreview(path: "notes.md", workspaceDirectory: nil, layout: .regular)
        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewFileWorkspaceDirectory == "/proj/old")
        #expect(state.previewSessionID == "session-a")
        #expect(state.inlinePreviewPath == nil)

        let pinnedKey = FileContentLoadKey.current(
            state: state,
            path: "notes.md",
            workspaceDirectory: state.previewFileWorkspaceDirectory,
            revision: 0
        )
        _ = try await state.loadFileContent(path: "notes.md", workspaceDirectory: state.previewFileWorkspaceDirectory)
        state.currentSessionID = "session-b"
        state.discardChatPreviewIfSessionChanged(from: "session-a", to: "session-b")
        let keyAfterSwitch = FileContentLoadKey.current(
            state: state,
            path: state.previewFilePath ?? "",
            workspaceDirectory: state.previewFileWorkspaceDirectory,
            revision: 0
        )
        _ = try await state.loadFileContent(path: "notes.md", workspaceDirectory: state.previewFileWorkspaceDirectory)

        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewFileWorkspaceDirectory == "/proj/old")
        #expect(state.previewSessionID == nil)
        #expect(state.previewHostID == host)
        #expect(state.inlinePreviewPath == nil)
        #expect(keyAfterSwitch == pinnedKey)
        let requests = await api.fileContentRequests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.path == "notes.md" && $0.directory == "/proj/old" })

        state.closeFilePreview()
        #expect(state.previewFilePath == nil)
        #expect(state.previewFileWorkspaceDirectory == nil)
    }

    @MainActor
    @Test func regularFilesColumnStaysAfterSessionSwitch() async throws {
        let api = MockAPIClient()
        let state = makePreviewState(apiClient: api)
        state.sessions = [
            previewSession(id: "session-a", directory: "/proj/old"),
            previewSession(id: "session-b", directory: "/proj/new"),
        ]
        state.currentSessionID = "session-a"
        state.selectedProjectWorktree = "/files/old"
        state.presentFilesColumnPreview(path: "readme.md", workspaceDirectory: state.effectiveProjectDirectory ?? "")
        state.currentSessionID = "session-b"
        state.selectedProjectWorktree = "/files/new"
        state.discardChatPreviewIfSessionChanged(from: "session-a", to: "session-b")
        _ = try await state.loadFileContent(path: "readme.md", workspaceDirectory: state.previewFileWorkspaceDirectory)

        #expect(state.previewFilePath == "readme.md")
        #expect(state.previewFileWorkspaceDirectory == "/files/old")
        #expect(state.previewSessionID == nil)
        #expect(await api.fileContentRequests.map(\.directory) == ["/files/old"])
    }

    @MainActor
    @Test func compactInlinePreviewClosesOnSessionSwitch() {
        let state = makePreviewState()
        state.sessions = [
            previewSession(id: "session-a", directory: "/proj/old"),
            previewSession(id: "session-b", directory: "/proj/new"),
        ]
        state.currentSessionID = "session-a"
        state.presentChatFilePreview(path: "notes.md", workspaceDirectory: nil, layout: .compact)
        #expect(state.inlinePreviewPath == "notes.md")
        #expect(state.inlinePreviewWorkspaceDirectory == "/proj/old")
        #expect(state.previewSessionID == "session-a")
        state.currentSessionID = "session-b"
        state.discardChatPreviewIfSessionChanged(from: "session-a", to: "session-b")
        #expect(state.inlinePreviewPath == nil)
        #expect(state.inlinePreviewWorkspaceDirectory == nil)
        #expect(state.previewFilePath == nil)
        #expect(state.previewSessionID == nil)
    }

    @MainActor
    @Test func pinnedColumnDoesNotAcceptLatePendingOpenFromPreviousSession() {
        let state = makePreviewState()
        state.sessions = [previewSession(id: "session-a", directory: "/proj/old")]
        state.currentSessionID = "session-a"
        let owner = ExternalFileOpenOwner(host: state.captureHostRequestSnapshot(), sessionID: "session-a")
        state.presentChatFilePreview(path: "visible.md", workspaceDirectory: "/proj/old", layout: .regular)
        state.currentSessionID = "session-b"
        state.discardChatPreviewIfSessionChanged(from: "session-a", to: "session-b")
        let sequence = state.previewEventSequence
        state.stageExternalFileOpen(path: "late.md", workspaceDirectory: "/proj/late", owner: owner)
        state.adoptPendingFileOpen(layout: .regular)
        #expect(state.previewEventSequence == sequence)
        #expect(state.fileToOpenInFilesTab == nil)
        #expect(state.pendingFileOpenOwner == nil)
        #expect(state.previewFilePath == "visible.md")
        #expect(state.previewFileWorkspaceDirectory == "/proj/old")
    }

    @MainActor
    @Test func hostSwitchClearsPinnedColumnPreview() {
        let state = makePreviewState()
        state.sessions = [previewSession(id: "session-a", directory: "/proj/old")]
        state.currentSessionID = "session-a"
        state.presentChatFilePreview(path: "notes.md", workspaceDirectory: "/proj/old", layout: .regular)
        let oldHost = state.currentHostProfileID
        let newHost = UUID()
        state.currentHostProfileID = newHost
        state.discardPreviewIfHostChanged(from: oldHost, to: newHost)
        #expect(state.previewFilePath == nil)
        #expect(state.previewFileWorkspaceDirectory == nil)
        #expect(state.inlinePreviewPath == nil)
        #expect(state.previewSessionID == nil)
        #expect(state.previewHostID == nil)
    }

    @MainActor
    @Test func pinnedServerDefaultDoesNotReloadFromLaterSessionDirectory() async throws {
        let api = MockAPIClient()
        let state = makePreviewState(apiClient: api)
        state.presentChatFilePreview(path: "notes.md", workspaceDirectory: nil, layout: .regular)
        #expect(state.previewFileWorkspaceDirectory == "")
        state.sessions = [previewSession(id: "session-b", directory: "/proj/new")]
        state.currentSessionID = "session-b"
        _ = try await state.loadFileContent(path: "notes.md", workspaceDirectory: state.previewFileWorkspaceDirectory)
        _ = try await state.loadFileContent(path: "notes.md", workspaceDirectory: nil)
        _ = try await state.loadFileContent(path: "/tmp/proj/notes.md", workspaceDirectory: "")
        let requests = await api.fileContentRequests
        #expect(requests.map(\.directory) == ["", "/proj/new", "/tmp/proj"])
        #expect(requests.map(\.path) == ["notes.md", "notes.md", "notes.md"])
        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewFileWorkspaceDirectory == "")
    }

    @MainActor
    @Test func deletingCurrentSessionClearsChatBoundPreviewOnly() async throws {
        let state = makePreviewState()
        state.sessions = [
            previewSession(id: "session-a", directory: "/proj/a"),
            previewSession(id: "session-b", directory: "/proj/b"),
            previewSession(id: "session-c", directory: "/proj/c"),
        ]
        state.currentSessionID = "session-a"
        state.presentChatFilePreview(path: "notes.md", workspaceDirectory: nil, layout: .regular)
        state.inlinePreviewPath = "also.md"
        state.inlinePreviewWorkspaceDirectory = "/proj/a"
        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewSessionID == "session-a")

        try await state.deleteSession(sessionID: "session-b")
        #expect(state.currentSessionID == "session-a")
        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewFileWorkspaceDirectory == "/proj/a")
        #expect(state.inlinePreviewPath == "also.md")
        #expect(state.inlinePreviewWorkspaceDirectory == "/proj/a")
        #expect(state.previewSessionID == "session-a")

        try await state.deleteSession(sessionID: "session-a")
        #expect(state.currentSessionID == "session-c")
        #expect(state.previewFilePath == nil)
        #expect(state.previewFileWorkspaceDirectory == nil)
        #expect(state.inlinePreviewPath == nil)
        #expect(state.inlinePreviewWorkspaceDirectory == nil)
        #expect(state.previewSessionID == nil)

        let files = makePreviewState()
        files.sessions = [
            previewSession(id: "session-a", directory: "/proj/a"),
            previewSession(id: "session-c", directory: "/proj/c"),
        ]
        files.currentSessionID = "session-a"
        files.presentFilesColumnPreview(path: "readme.md", workspaceDirectory: "/files")
        #expect(files.previewSessionID == nil)
        try await files.deleteSession(sessionID: "session-a")
        #expect(files.previewFilePath == "readme.md")
        #expect(files.previewFileWorkspaceDirectory == "/files")
        #expect(files.inlinePreviewPath == nil)
        #expect(files.previewSessionID == nil)
    }

    @MainActor
    @Test func unboundWorkspaceFileStaysUnboundWhileMovingBetweenLayouts() {
        let state = makePreviewState()
        state.sessions = [
            previewSession(id: "session-a", directory: "/proj/a"),
            previewSession(id: "session-b", directory: "/proj/b"),
            previewSession(id: "session-c", directory: "/proj/c"),
        ]
        state.currentSessionID = "session-a"
        state.presentChatFilePreview(path: "notes.md", workspaceDirectory: nil, layout: .regular)

        state.currentSessionID = "session-b"
        state.discardChatPreviewIfSessionChanged(from: "session-a", to: "session-b")
        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewFileWorkspaceDirectory == "/proj/a")
        #expect(state.previewSessionID == nil)

        state.applyPreviewLayout(from: .regular, to: .regular)
        #expect(state.previewFilePath == "notes.md")
        #expect(state.previewSessionID == nil)

        state.applyPreviewLayout(from: .regular, to: .compact)
        #expect(state.inlinePreviewPath == "notes.md")
        #expect(state.inlinePreviewWorkspaceDirectory == "/proj/a")
        #expect(state.previewFilePath == nil)
        #expect(state.previewSessionID == nil)

        state.currentSessionID = "session-c"
        state.discardChatPreviewIfSessionChanged(from: "session-b", to: "session-c")
        #expect(state.inlinePreviewPath == "notes.md")
        #expect(state.inlinePreviewWorkspaceDirectory == "/proj/a")
        #expect(state.previewFilePath == nil)
        #expect(state.previewSessionID == nil)

        let unbound = makePreviewState()
        unbound.presentChatFilePreview(path: "notes.md", workspaceDirectory: "/proj/a", layout: .regular)
        #expect(unbound.previewSessionID == nil)
        unbound.applyPreviewLayout(from: .regular, to: .compact)
        #expect(unbound.inlinePreviewPath == "notes.md")
        #expect(unbound.previewSessionID == nil)
    }

    @MainActor
    @Test func dockedBrowserFileStaysOpenAcrossSessionSwitch() {
        let state = makePreviewState()
        state.currentSessionID = "session-a"
        state.presentChatFilePreview(path: "notes.txt", workspaceDirectory: "/workspace", layout: .compact, bindToSession: false)
        state.currentSessionID = "session-b"
        state.discardChatPreviewIfSessionChanged(from: "session-a", to: "session-b")
        #expect(state.inlinePreviewPath == "notes.txt")
        #expect(state.inlinePreviewWorkspaceDirectory == "/workspace")
        #expect(state.previewSessionID == nil)
    }
}

@MainActor
private func capturedOpen(
    _ state: AppState,
    owner: ExternalFileOpenOwner
) -> (String, String?) -> Void {
    { path, workspace in
        state.stageExternalFileOpen(path: path, workspaceDirectory: workspace, owner: owner)
    }
}

@MainActor
private func makePreviewState(apiClient: MockAPIClient = MockAPIClient()) -> AppState {
    let defaults = UserDefaults(suiteName: "opencode.tests.preview.\(UUID().uuidString)")!
    return AppState(
        apiClient: apiClient,
        sseClient: MockSSEClient(),
        sshTunnelManager: SSHTunnelManager(defaults: defaults),
        userDefaults: defaults,
        hostCredentialAccess: .noExternal
    )
}

private func previewSession(id: String, directory: String) -> Session {
    Session(
        id: id,
        slug: id,
        projectID: "p1",
        directory: directory,
        parentID: nil,
        title: id,
        version: "1",
        time: .init(created: 0, updated: 1, archived: nil),
        share: nil,
        summary: nil
    )
}

struct ComposerOwnershipTests {
    @Test func pasteHandoffCapturesOriginBeforeProviderLoad() async {
        let source = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: UUID(), generation: 1))
        let destination = ComposerWriteOrigin(sessionID: "b", host: HostRequestSnapshot(hostProfileID: UUID(), generation: 2))
        var current = source
        var delivered: ComposerWriteOrigin?
        await ComposerPasteHandoff.captureThenLoad {
            let captured = current
            return { strings in
                #expect(strings == ["pasted"])
                delivered = captured
            }
        } load: {
            current = destination
            return ["pasted"]
        }
        #expect(delivered == source)
    }

    @MainActor
    @Test func pasteControlDecodesStringProvider() async {
        let provider = NSItemProvider(object: "FOCUS_VOICE_PASTE_SENTINEL" as NSString)
        let strings = await ComposerPastePayload.strings(from: [provider])
        #expect(strings == ["FOCUS_VOICE_PASTE_SENTINEL"])
    }

    @MainActor
    @Test func pasteControlCapturesOriginWhenPasteBegins() async {
        let coordinator = ComposerPasteButton.Coordinator()
        var generation = 0
        var delivered: (Int, [String])?
        coordinator.beginPaste = {
            generation += 1
            let captured = generation
            return { parts in
                delivered = (captured, parts)
            }
        }
        let provider = NSItemProvider(object: "FOCUS_VOICE_PASTE_SENTINEL" as NSString)
        coordinator.paste(itemProviders: [provider])
        #expect(generation == 1)
        coordinator.beginPaste = {
            generation += 1
            return { _ in
                delivered = (99, [])
            }
        }
        for _ in 0..<50 where delivered == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(delivered?.0 == 1)
        #expect(delivered?.1 == ["FOCUS_VOICE_PASTE_SENTINEL"])
    }

    @MainActor
    @Test func delayedPasteAfterSessionOrHostSwitchStaysOnSourceDraft() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let hostB = UUID()
        let source = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.setDraftText("keep-a", for: "a", hostProfileID: hostA)
        state.currentHostProfileID = hostB
        state.currentSessionID = "b"
        ComposerOwnedWrite.pasteIntoSourceDraft(addition: "pasted", origin: source, state: state)
        #expect(state.draftText(for: "a", hostProfileID: hostA) == "keep-a\npasted")
        #expect(state.draftText(for: "b", hostProfileID: hostB) == "")
        #expect(state.draftText(for: "a", hostProfileID: hostB) == "")
    }

    @MainActor
    @Test func deferredSpeechAfterSessionOrHostSwitchDoesNotEnterCurrentDraft() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let hostB = UUID()
        let origin = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.setDraftText("hello", for: "a", hostProfileID: hostA)
        state.currentHostProfileID = hostB
        state.currentSessionID = "b"
        state.setDraftText("destination", for: "b", hostProfileID: hostB)
        let merged = ComposerOwnedWrite.speechIntoSourceDraft(
            prefix: "hello",
            transcript: "there",
            origin: origin,
            state: state
        )
        #expect(merged == "hello there")
        #expect(state.draftText(for: "a", hostProfileID: hostA) == "hello there")
        #expect(state.draftText(for: "b", hostProfileID: hostB) == "destination")
        #expect(ComposerOwnedWrite.sameVisibleComposer(
            origin: origin,
            currentSessionID: state.currentSessionID,
            currentHostID: state.currentHostProfileID
        ) == false)
    }

    @MainActor
    @Test func noncurrentSpeechKeepsPasteAppendedAfterSwitch() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let origin = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.setDraftText("hello partial\npasted", for: "a", hostProfileID: hostA)
        let merged = ComposerOwnedWrite.speechIntoSourceDraft(
            prefix: "hello",
            transcript: "final",
            origin: origin,
            state: state
        )
        #expect(merged == "hello final\npasted")
        #expect(state.draftText(for: "a", hostProfileID: hostA) == "hello final\npasted")
    }

    @MainActor
    @Test func nilSessionPasteStaysOnOriginHost() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let hostB = UUID()
        let origin = ComposerWriteOrigin(sessionID: nil, host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.currentHostProfileID = hostB
        ComposerOwnedWrite.pasteIntoSourceDraft(addition: "orphan", origin: origin, state: state)
        #expect(state.draftText(for: nil, hostProfileID: hostA) == "orphan")
        #expect(state.draftText(for: nil, hostProfileID: hostB) == "")
        #expect(state.draftText(for: nil) == "")
    }

    @Test func pasteDuringSendFailureIsKeptWhenRevisionAdvances() {
        let edited = ComposerRevisionEdit.applying(current: "sent", revision: 3, edited: "sent\npasted")
        let host = HostRequestSnapshot(hostProfileID: UUID(), generation: 1)
        let restored = ChatComposerRestore.textAndAttachments(
            sourceSessionID: "a",
            currentSessionID: "a",
            capturedRevision: 3,
            currentRevision: edited.revision,
            capturedHost: host,
            currentHost: host,
            capturedSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currentSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sentText: "sent",
            sentAttachments: [],
            currentText: edited.text,
            currentAttachments: []
        )
        #expect(edited.revision == 4)
        #expect(restored.text == "sent\npasted")
        let clearedThenPasted = ChatComposerRestore.textAndAttachments(
            sourceSessionID: "a",
            currentSessionID: "a",
            capturedRevision: 3,
            currentRevision: 4,
            capturedHost: host,
            currentHost: host,
            capturedSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currentSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sentText: "sent",
            sentAttachments: [],
            currentText: "pasted",
            currentAttachments: []
        )
        #expect(clearedThenPasted.text == "sent\npasted")
    }

    @MainActor
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "opencode.tests.ownership.\(UUID().uuidString)")!
        return AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
    }
}

private final class ReloadCountingTextView: IMEAwareTextView {
    var reloadCount = 0

    override func reloadInputViews() {
        reloadCount += 1
        super.reloadInputViews()
    }
}
