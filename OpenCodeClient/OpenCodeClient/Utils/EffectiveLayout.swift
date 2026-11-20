import Foundation
import SwiftUI

enum LayoutPreference: String, CaseIterable, Identifiable {
    case automatic
    case focus

    var id: String { rawValue }

    static func resolved(from raw: String?) -> LayoutPreference {
        guard let raw, let value = LayoutPreference(rawValue: raw) else { return .automatic }
        return value
    }
}

enum WindowWidthClass: Equatable {
    case regular
    case compact
    case unspecified

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        switch horizontalSizeClass {
        case .regular:
            self = .regular
        case .compact:
            self = .compact
        default:
            self = .unspecified
        }
    }
}

enum EffectiveLayout: Equatable {
    case compact
    case regular
}

/// Sidebar mode shares compact preview routing, including its live composer.
enum WorkspacePresentation: Equatable {
    case compact, sidebar, wide

    var previewLayout: EffectiveLayout { self == .wide ? .regular : .compact }

    static func resolve(preference: LayoutPreference, width: CGFloat,
                        widthClass: WindowWidthClass, shortWindow: Bool) -> Self {
        guard preference == .automatic else { return .compact }
        if width >= 820 { return .wide }
        if width >= 555, !shortWindow { return .sidebar }
        if width <= 0, widthClass == .regular { return .wide }
        return .compact
    }
}

enum EffectiveLayoutResolver {
    static func resolve(preference: LayoutPreference, width: WindowWidthClass) -> EffectiveLayout {
        switch preference {
        case .focus:
            return .compact
        case .automatic:
            return width == .regular ? .regular : .compact
        }
    }
}

private struct EffectiveLayoutKey: EnvironmentKey {
    static let defaultValue = EffectiveLayout.compact
}

extension EnvironmentValues {
    var effectiveLayout: EffectiveLayout {
        get { self[EffectiveLayoutKey.self] }
        set { self[EffectiveLayoutKey.self] = newValue }
    }
}

struct LayoutPreviewSlots: Equatable {
    var inlinePath: String?
    var inlineWorkspace: String?
    var columnPath: String?
    var columnWorkspace: String?

    static let empty = LayoutPreviewSlots()
}

enum LayoutPreviewMigration {
    /// The slot the user can see in `from` is the source. A value already in the
    /// destination is a hidden preview and must not stay on screen.
    static func migrate(
        from: EffectiveLayout,
        to: EffectiveLayout,
        slots: LayoutPreviewSlots
    ) -> LayoutPreviewSlots {
        guard from != to else { return slots }
        switch from {
        case .regular:
            guard let column = slots.columnPath, !column.isEmpty else { return .empty }
            return LayoutPreviewSlots(
                inlinePath: column,
                inlineWorkspace: slots.columnWorkspace,
                columnPath: nil,
                columnWorkspace: nil
            )
        case .compact:
            guard let inline = slots.inlinePath, !inline.isEmpty else { return .empty }
            return LayoutPreviewSlots(
                inlinePath: nil,
                inlineWorkspace: nil,
                columnPath: inline,
                columnWorkspace: slots.inlineWorkspace
            )
        }
    }
}

struct PreviewLayoutInput: Equatable {
    var slots: LayoutPreviewSlots
    var columnSequence: UInt64 = 0
    var inlineSequence: UInt64 = 0
    var filesPath: [String]
    var filesWorkspace: String?
    var filesHostMatches: Bool
    var filesSequence: UInt64 = 0
    var pendingPath: String?
    var pendingWorkspace: String?
    var pendingHostMatches: Bool
    var pendingSequence: UInt64 = 0
}

struct PreviewLayoutOutput: Equatable {
    var slots: LayoutPreviewSlots
    var filesPath: [String]
    var pendingPath: String?
    var pendingWorkspace: String?
    var winnerSequence: UInt64 = 0
}

enum ExternalFileOpenRouting {
    static func shouldAdopt(sequence: UInt64, path: String?) -> Bool {
        sequence != 0 && path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

enum PreviewLayoutTransition {
    static func apply(
        from: EffectiveLayout,
        to: EffectiveLayout,
        input: PreviewLayoutInput
    ) -> PreviewLayoutOutput {
        let filesPath = input.filesHostMatches ? input.filesPath : []
        let pending = input.pendingHostMatches ? input.pendingPath : nil
        let pendingWorkspace = input.pendingHostMatches ? input.pendingWorkspace : nil
        let shown = shownPreview(from: from, input: input, filesPath: filesPath)
        let winner = laterExternalOpen(
            shown: shown,
            filesPath: filesPath,
            filesWorkspace: input.filesWorkspace,
            filesSequence: input.filesHostMatches ? input.filesSequence : 0,
            pendingPath: pending,
            pendingWorkspace: pendingWorkspace,
            pendingSequence: input.pendingHostMatches ? input.pendingSequence : 0
        )
        return PreviewLayoutOutput(
            slots: place(winner.path, workspace: winner.workspace, in: to),
            filesPath: to == .regular ? [] : filesPath,
            pendingPath: nil,
            pendingWorkspace: nil,
            winnerSequence: winner.sequence
        )
    }

    private static func shownPreview(
        from: EffectiveLayout,
        input: PreviewLayoutInput,
        filesPath: [String]
    ) -> (path: String?, workspace: String?, sequence: UInt64) {
        switch from {
        case .regular:
            guard let column = input.slots.columnPath, !column.isEmpty else {
                return (nil, nil, 0)
            }
            return (column, input.slots.columnWorkspace, input.columnSequence)
        case .compact:
            if let inline = input.slots.inlinePath, !inline.isEmpty {
                return (inline, input.slots.inlineWorkspace, input.inlineSequence)
            }
            guard let pushed = filesPath.last, !pushed.isEmpty else {
                return (nil, nil, 0)
            }
            return (pushed, input.filesWorkspace, input.filesSequence)
        }
    }

    private static func laterExternalOpen(
        shown: (path: String?, workspace: String?, sequence: UInt64),
        filesPath: [String],
        filesWorkspace: String?,
        filesSequence: UInt64,
        pendingPath: String?,
        pendingWorkspace: String?,
        pendingSequence: UInt64
    ) -> (path: String?, workspace: String?, sequence: UInt64) {
        var path = shown.path
        var workspace = shown.workspace
        var sequence = shown.path == nil ? 0 : shown.sequence
        if let pending = pendingPath, !pending.isEmpty, pendingSequence > sequence {
            path = pending
            workspace = pendingWorkspace
            sequence = pendingSequence
        }
        if let pushed = filesPath.last, !pushed.isEmpty, filesSequence > sequence {
            path = pushed
            workspace = filesWorkspace
            sequence = filesSequence
        }
        return (path, workspace, sequence)
    }

    private static func place(_ path: String?, workspace: String?, in layout: EffectiveLayout) -> LayoutPreviewSlots {
        guard let path, !path.isEmpty else { return .empty }
        switch layout {
        case .compact:
            return LayoutPreviewSlots(inlinePath: path, inlineWorkspace: workspace, columnPath: nil, columnWorkspace: nil)
        case .regular:
            return LayoutPreviewSlots(inlinePath: nil, inlineWorkspace: nil, columnPath: path, columnWorkspace: workspace)
        }
    }
}

enum ChatViewportReset: Equatable {
    case sessionChange
    case layoutChange
}

enum ChatViewportPolicy {
    static func forcesBottom(on reset: ChatViewportReset) -> Bool {
        switch reset {
        case .sessionChange:
            return true
        case .layoutChange:
            return false
        }
    }
}

enum ComposerHitTarget {
    static let minimum: CGFloat = 44
}

struct ComposerWriteOrigin: Equatable, Sendable {
    var sessionID: String?
    var host: HostRequestSnapshot
}

struct DeferredPasteWrite: Equatable {
    var addition: String
    var origin: ComposerWriteOrigin
}

struct DeferredSpeechWrite: Equatable {
    var prefix: String
    var transcript: String
    var origin: ComposerWriteOrigin
}

enum ComposerPasteHandoff {
    static func captureThenLoad(
        begin: () -> ([String]) -> Void,
        load: () async -> [String]
    ) async {
        let deliver = begin()
        let strings = await load()
        deliver(strings)
    }
}

enum ComposerRevisionEdit {
    static func applying(current: String, revision: UInt64, edited: String) -> (text: String, revision: UInt64) {
        guard edited != current else { return (current, revision) }
        return (edited, revision &+ 1)
    }
}

enum ComposerOwnedWrite {
    static func sameVisibleComposer(
        origin: ComposerWriteOrigin,
        currentSessionID: String?,
        currentHostID: UUID
    ) -> Bool {
        origin.host.hostProfileID == currentHostID && origin.sessionID == currentSessionID
    }

    @discardableResult
    static func pasteIntoSourceDraft(
        addition: String,
        origin: ComposerWriteOrigin,
        state: AppState
    ) -> String {
        let latest = state.draftText(for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        let merged = ComposerDraftMerge.appending(draft: latest, addition: addition)
        state.setDraftText(merged, for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        return merged
    }

    @discardableResult
    static func speechIntoSourceDraft(
        prefix: String,
        transcript: String,
        origin: ComposerWriteOrigin,
        state: AppState
    ) -> String {
        let latest = state.draftText(for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        let merged = ComposerDraftMerge.mergingSpeech(
            prefix: prefix,
            transcript: transcript,
            latestDraft: latest
        )
        state.setDraftText(merged, for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        return merged
    }
}

enum ComposerActionSide: String, CaseIterable {
    case left
    case right

    static func resolved(from value: String?) -> Self {
        Self(rawValue: value ?? "") ?? .right
    }
}

enum ComposerFocusPolicy {
    static func isTextEditable(voiceFirst: Bool, isEditing: Bool) -> Bool {
        _ = (voiceFirst, isEditing)
        return true
    }

    static func requestsFirstResponder(voiceFirst: Bool, isEditing: Bool) -> Bool {
        voiceFirst && isEditing
    }

    static func suppressesSoftwareKeyboard(voiceFirst: Bool, isEditing: Bool) -> Bool {
        voiceFirst && !isEditing
    }

    static func shouldAssignComposerText(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }
}

enum ComposerPastePlacement: Equatable {
    case append
    case insert(NSRange)
    case deferUntilMarkedTextEnds
}

enum ComposerPastePlanner {
    static func placement(
        hasCaretFocus: Bool,
        hasMarkedText: Bool,
        selectionUTF16: NSRange?,
        speechOwnedUTF16End: Int?
    ) -> ComposerPastePlacement {
        if hasMarkedText { return .deferUntilMarkedTextEnds }
        guard hasCaretFocus, let selectionUTF16, selectionUTF16.location != NSNotFound else { return .append }
        if let speechEnd = speechOwnedUTF16End, selectionUTF16.location < speechEnd {
            return .append
        }
        return .insert(selectionUTF16)
    }
}

enum ComposerDraftMerge {
    static func joinedPaste(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func appending(draft: String, addition: String) -> String {
        guard !addition.isEmpty else { return draft }
        guard !draft.isEmpty else { return addition }
        return draft + "\n" + addition
    }

    static func inserting(draft: String, addition: String, selectionUTF16: NSRange) -> (text: String, cursorUTF16: Int) {
        guard !addition.isEmpty else {
            return (draft, selectionUTF16.location)
        }
        let ns = draft as NSString
        let length = ns.length
        let location = min(max(0, selectionUTF16.location), length)
        let rangeLength = min(max(0, selectionUTF16.length), length - location)
        let replaced = ns.replacingCharacters(in: NSRange(location: location, length: rangeLength), with: addition)
        return (replaced, location + (addition as NSString).length)
    }

    static func speechText(prefix: String, transcript: String, tail: String) -> String {
        appending(
            draft: ChatSpeechRouting.mergedInput(prefix: prefix, transcript: transcript),
            addition: tail
        )
    }

    /// Keep newline-appended user text from the source draft. Do not replace that draft with a cached tail.
    static func mergingSpeech(prefix: String, transcript: String, latestDraft: String) -> String {
        let speech = ChatSpeechRouting.mergedInput(prefix: prefix, transcript: transcript)
        let addition = userAppendedTail(in: latestDraft, afterPrefix: prefix)
        if addition.isEmpty {
            if latestDraft.isEmpty || prefix.isEmpty || latestDraft.hasPrefix(prefix) {
                return speech
            }
            return latestDraft
        }
        if speech == addition || speech.hasSuffix("\n" + addition) {
            return speech
        }
        return appending(draft: speech, addition: addition)
    }

    static func userAppendedTail(in draft: String, afterPrefix prefix: String) -> String {
        guard !draft.isEmpty else { return "" }
        let rest: Substring
        if prefix.isEmpty {
            rest = Substring(draft)
        } else if draft.hasPrefix(prefix) {
            rest = draft.dropFirst(prefix.count)
        } else {
            return ""
        }
        guard let newline = rest.firstIndex(of: "\n") else { return "" }
        return String(rest[rest.index(after: newline)...])
    }

    static func tail(afterSpeech speech: String, in rendered: String) -> String {
        guard !speech.isEmpty else { return rendered }
        if rendered == speech { return "" }
        let withBreak = speech + "\n"
        if rendered.hasPrefix(withBreak) {
            return String(rendered.dropFirst(withBreak.count))
        }
        if rendered.hasPrefix(speech) {
            let rest = rendered.dropFirst(speech.count)
            if rest.hasPrefix("\n") {
                return String(rest.dropFirst())
            }
            return String(rest)
        }
        return ""
    }
}

struct SpeechDraftProtector: Equatable {
    var anchor: String = ""
    var tail: String = ""
    var ownerSessionID: String?
    var tailsBySession: [String: String] = [:]

    mutating func begin(prefix: String, sessionID: String?) {
        anchor = prefix
        tail = ""
        ownerSessionID = sessionID
        if let sessionID {
            tailsBySession[sessionID] = ""
        }
    }

    mutating func ensureAnchor(_ prefix: String) {
        if anchor.isEmpty {
            anchor = prefix
        }
    }

    mutating func noteVisibleText(_ text: String) {
        guard !anchor.isEmpty else { return }
        if text == anchor || text.hasPrefix(anchor) {
            tail = ComposerDraftMerge.tail(afterSpeech: anchor, in: text)
            if let ownerSessionID {
                tailsBySession[ownerSessionID] = tail
            }
        }
    }

    func preservedTail(for sessionID: String?) -> String {
        guard let sessionID else { return tail }
        return tailsBySession[sessionID] ?? ""
    }

    mutating func render(prefix: String, transcript: String) -> String {
        let speech = ChatSpeechRouting.mergedInput(prefix: prefix, transcript: transcript)
        let rendered = ComposerDraftMerge.appending(draft: speech, addition: tail)
        anchor = speech
        return rendered
    }
}
