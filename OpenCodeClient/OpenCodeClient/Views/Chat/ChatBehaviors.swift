import SwiftUI

/// Should the chat view auto-scroll to the bottom on new content?
/// Tracks how close the user already is to the bottom — once they've
/// scrolled up far enough, we stop chasing new messages so reading
/// older messages isn't interrupted.
enum ChatScrollBehavior {
    static let followThreshold: CGFloat = 80

    static func shouldAutoScroll(
        bottomMarkerMinY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat = followThreshold
    ) -> Bool {
        bottomMarkerMinY <= viewportHeight + threshold
    }

    /// How long after the view scrolls itself to the bottom a
    /// bottom-marker measurement may still be mid-settle (the snap is
    /// animated while idle and lands ~200ms out, the measurement is
    /// debounced 75ms).
    static let selfScrollSettleWindow: TimeInterval = 0.35

    /// May a fresh bottom-marker measurement overwrite the follow flag?
    /// A "not near bottom" reading taken while our own bottom snap is still
    /// settling is stale: before this gate it latched the flag off with no
    /// retry, so every later event (new tool call, new message) failed to
    /// auto-scroll until the user switched sessions and back. "Near bottom"
    /// readings always apply.
    static func shouldApplyBottomMeasurement(
        measuredNearBottom: Bool,
        lastSelfScrollAt: Date?,
        now: Date,
        settleWindow: TimeInterval = selfScrollSettleWindow
    ) -> Bool {
        if measuredNearBottom { return true }
        guard let last = lastSelfScrollAt else { return true }
        return now.timeIntervalSince(last) >= settleWindow
    }
}

extension ChatScrollBehavior {
    /// Fingerprint of the newest message row for the auto-scroll signature.
    /// `textLength` is the cumulative text across all of its parts: streaming
    /// deltas append to an existing part's text without adding a part, so
    /// `partCount` alone never changes during a long text answer and the
    /// follow chain never fires.
    struct LastMessageFingerprint: Equatable {
        let id: String
        let partCount: Int
        let textLength: Int
        let completed: Int?
    }

    /// Changes whenever the visible chat content can have grown or the turn
    /// state can have changed; the view observes it to drive auto-scroll.
    static func scrollSignature(
        pendingPermissions: Int,
        pendingQuestions: Int,
        messageCount: Int,
        lastMessage: LastMessageFingerprint?,
        sessionID: String,
        status: String,
        activity: String
    ) -> String {
        let last = lastMessage.map {
            "\($0.id)-\($0.partCount)-\($0.textLength)-\($0.completed ?? -1)"
        } ?? "none"
        return "\(pendingPermissions)-\(pendingQuestions)-\(messageCount)-\(last)-\(sessionID)-\(status)-\(activity)"
    }
}

/// Why a leading-edge swipe was accepted or rejected. Used by the preview
/// close logger so a no-op swipe is diagnosable from console output.
enum EdgeSwipeDecision: String, Equatable {
    case accept
    case startTooFarFromEdge
    case swipedWrongDirection
    case horizontalTooShort
    case verticalDriftTooLarge
}

/// Shared geometry for leading-edge horizontal swipes (session list open,
/// file preview close). Keep a single source of thresholds so the two
/// behaviors cannot drift.
enum EdgeSwipeGeometry {
    static let edgeThreshold: CGFloat = 32
    static let minimumHorizontalTranslation: CGFloat = 72
    static let maximumVerticalTranslation: CGFloat = 56

    static func decision(startLocation: CGPoint, translation: CGSize) -> EdgeSwipeDecision {
        if startLocation.x > edgeThreshold { return .startTooFarFromEdge }
        // iOS back-edge is rightward. A leftward flick from the edge is
        // the opposite of dismiss and must not close the preview.
        if translation.width < 0 { return .swipedWrongDirection }
        if translation.width < minimumHorizontalTranslation { return .horizontalTooShort }
        if abs(translation.height) > maximumVerticalTranslation { return .verticalDriftTooLarge }
        return .accept
    }

    static func shouldAcceptLeadingEdgeSwipe(startLocation: CGPoint, translation: CGSize) -> Bool {
        decision(startLocation: startLocation, translation: translation) == .accept
    }
}

/// Edge-swipe gesture for opening the session list. We only accept
/// horizontal swipes starting near the left edge — keeps the chat
/// pan / scroll gestures responsive in the rest of the view.
enum SessionListEdgeSwipeBehavior {
    static let edgeThreshold: CGFloat = EdgeSwipeGeometry.edgeThreshold
    static let minimumHorizontalTranslation: CGFloat = EdgeSwipeGeometry.minimumHorizontalTranslation
    static let maximumVerticalTranslation: CGFloat = EdgeSwipeGeometry.maximumVerticalTranslation

    static func shouldOpenSessionList(startLocation: CGPoint, translation: CGSize) -> Bool {
        EdgeSwipeGeometry.shouldAcceptLeadingEdgeSwipe(
            startLocation: startLocation,
            translation: translation
        )
    }
}

/// Edge-swipe gesture for dismissing the iPhone docked file preview.
/// Same geometry as opening the session list: start at the far-left
/// edge and translate rightward with limited vertical drift.
enum FilePreviewEdgeSwipeBehavior {
    static let edgeThreshold: CGFloat = EdgeSwipeGeometry.edgeThreshold
    static let minimumHorizontalTranslation: CGFloat = EdgeSwipeGeometry.minimumHorizontalTranslation
    static let maximumVerticalTranslation: CGFloat = EdgeSwipeGeometry.maximumVerticalTranslation

    static func shouldClosePreview(startLocation: CGPoint, translation: CGSize) -> Bool {
        EdgeSwipeGeometry.shouldAcceptLeadingEdgeSwipe(
            startLocation: startLocation,
            translation: translation
        )
    }
}
