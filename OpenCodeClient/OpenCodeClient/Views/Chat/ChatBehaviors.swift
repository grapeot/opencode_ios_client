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
}

/// Shared geometry for leading-edge horizontal swipes (session list open,
/// file preview close). Keep a single source of thresholds so the two
/// behaviors cannot drift.
enum EdgeSwipeGeometry {
    static let edgeThreshold: CGFloat = 32
    static let minimumHorizontalTranslation: CGFloat = 72
    static let maximumVerticalTranslation: CGFloat = 56

    static func shouldAcceptLeadingEdgeSwipe(startLocation: CGPoint, translation: CGSize) -> Bool {
        guard startLocation.x <= edgeThreshold else { return false }
        guard translation.width >= minimumHorizontalTranslation else { return false }
        return abs(translation.height) <= maximumVerticalTranslation
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
