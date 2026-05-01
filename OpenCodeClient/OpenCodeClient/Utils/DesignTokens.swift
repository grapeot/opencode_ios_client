//
//  DesignTokens.swift
//  OpenCodeClient
//
//  Centralized design system: colors, typography, spacing, corners, animations.
//  All visual values flow from here — no magic numbers in View files.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color System

enum DesignColors {

    // MARK: Brand

    enum Brand {
        /// Primary brand blue — close to system accent, used for all interactive elements
        static let primary = Color(red: 0.0, green: 0.478, blue: 1.0)
        /// Gold accent — highlights, running indicators
        static let gold = Color(red: 0.85, green: 0.65, blue: 0.13)
    }

    // MARK: Semantic

    enum Semantic {
        static let error = Color.red
        static let success = Color(red: 0.20, green: 0.65, blue: 0.35)
        static let warning = Color.orange
        static let info = Color(red: 0.25, green: 0.47, blue: 0.85)
    }

    // MARK: Neutral (warm-tinted gray scale, less blue than system grays)

    enum Neutral {
        /// Primary text
        static let text = Color.primary
        /// Secondary text, timestamps, labels
        static let textSecondary = Color.secondary
        /// Tertiary text, disabled labels
        #if canImport(UIKit)
        static let textTertiary = Color(UIColor.tertiaryLabel)
        #else
        static let textTertiary = Color.gray.opacity(0.4)
        #endif

        /// Subtle card / surface background — light mode
        static let surfaceLight = Color(red: 0.96, green: 0.96, blue: 0.97)
        /// Subtle card / surface background — dark mode
        static let surfaceDark = Color(red: 0.14, green: 0.14, blue: 0.16)
        /// Composer input background — light mode
        static let composerLight = Color(red: 0.94, green: 0.94, blue: 0.95)
        /// Composer input background — dark mode
        static let composerDark = Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    // MARK: Opacity Rules

    /// Unified opacity system. Use these instead of ad-hoc .opacity() values.
    enum Opacity {
        /// Card / info surface fill
        static let surfaceFill: Double = 0.06
        /// Card / info surface fill in dark mode
        static let surfaceFillDark: Double = 0.10
        /// Card / info border stroke
        static let borderStroke: Double = 0.12
        /// Card / info border stroke in dark mode
        static let borderStrokeDark: Double = 0.15
        /// User message background
        static let userMessageFill: Double = 0.10
        /// User message background in dark mode
        static let userMessageFillDark: Double = 0.14
        /// User message border
        static let userMessageBorder: Double = 0.18
        /// Selected row / active highlight
        static let selectionFill: Double = 0.08
        /// Context usage ring track
        static let ringTrack: Double = 0.20
        /// Recording action button fill. Keeps the active state visibly red even when solid fills are softened by platform materials.
        static let recordingActionFill: Double = 0.16
        /// Recording action button border. Stronger than the default border because it carries active-state color.
        static let recordingActionBorder: Double = 0.36
    }

    /// Returns the appropriate surface fill opacity for the current color scheme.
    @MainActor
    static func surfaceFill(for scheme: ColorScheme) -> Double {
        scheme == .dark ? Opacity.surfaceFillDark : Opacity.surfaceFill
    }

    /// Returns the appropriate border stroke opacity for the current color scheme.
    @MainActor
    static func borderStroke(for scheme: ColorScheme) -> Double {
        scheme == .dark ? Opacity.borderStrokeDark : Opacity.borderStroke
    }

    /// Returns the appropriate user message fill opacity for the current color scheme.
    @MainActor
    static func userMessageFill(for scheme: ColorScheme) -> Double {
        scheme == .dark ? Opacity.userMessageFillDark : Opacity.userMessageFill
    }
}

// MARK: - Typography Scale

enum DesignTypography {

    /// Display — session titles, empty state headlines
    static let display: Font = .title3.weight(.bold)

    /// Headline — section headers, card titles
    static let headline: Font = .headline

    /// Body — chat message text (AI replies)
    static let body: Font = .body

    /// Body prominent — user messages (slightly larger to differentiate)
    static let bodyProminent: Font = .callout

    /// Meta — timestamps, status labels, tool names
    static let meta: Font = .caption

    /// Micro — tool input/output, code paths, detailed info
    static let micro: Font = .caption2

    /// Micro monospaced — code, file paths
    static let microMono: Font = .system(.caption2, design: .monospaced)
}

// MARK: - Spacing Scale

enum DesignSpacing {

    /// Extra small — tight internal padding (4pt)
    static let xs: CGFloat = 4
    /// Small — compact gaps (8pt)
    static let sm: CGFloat = 8
    /// Medium — standard gaps (12pt)
    static let md: CGFloat = 12
    /// Large — comfortable gaps (16pt)
    static let lg: CGFloat = 16
    /// Extra large — section separation (20pt)
    static let xl: CGFloat = 20
    /// Double extra large — major section breaks (24pt)
    static let xxl: CGFloat = 24

    /// Chat message vertical spacing
    static let messageVertical: CGFloat = 20
    /// Card internal padding
    static let cardPadding: CGFloat = 12
    /// Card to context gap
    static let cardGap: CGFloat = 16
}

// MARK: - Control Sizes

enum DesignControls {

    #if os(visionOS)
    /// Larger chat composer action buttons for gaze interaction on Apple Vision Pro.
    static let composerActionButtonSize: CGFloat = 48
    static let composerActionButtonSpacing: CGFloat = DesignSpacing.md
    static let composerActionIconFont: Font = .title3
    static let composerContainerHorizontalPadding: CGFloat = 32
    static let composerContainerVerticalPadding: CGFloat = 20
    static let composerTextMinHeight: CGFloat = 48
    static let composerTextMaxHeight: CGFloat = 160
    static let toolOpenFileIconFont: Font = .title3
    static let toolOpenFileButtonSize: CGFloat = 44
    #else
    /// Compact chat composer action buttons for iPhone and iPad.
    static let composerActionButtonSize: CGFloat = 32
    static let composerActionButtonSpacing: CGFloat = DesignSpacing.sm
    static let composerActionIconFont: Font = .callout
    static let composerContainerHorizontalPadding: CGFloat = 16
    static let composerContainerVerticalPadding: CGFloat = 10
    static let composerTextMinHeight: CGFloat = 32
    static let composerTextMaxHeight: CGFloat = 100
    static let toolOpenFileIconFont: Font = DesignTypography.micro
    static let toolOpenFileButtonSize: CGFloat = 24
    #endif
}

// MARK: - Corner Radius

enum DesignCorners {

    /// Small radius — tags, inline elements (6pt)
    static let small: CGFloat = 6
    /// Medium radius — cards, buttons (12pt)
    static let medium: CGFloat = 12
    /// Large radius — message bubbles, sheets (16pt)
    static let large: CGFloat = 16
    /// Capsule — pill-shaped elements (system)
    static let capsule: CGFloat = .infinity
}

// MARK: - Animation Presets

enum DesignAnimation {

    /// Quick fade (0.15s) — status changes, minor updates
    static let quick = Animation.easeOut(duration: 0.15)

    /// Standard transition (0.25s) — content appearance
    static let standard = Animation.easeOut(duration: 0.25)

    /// Smooth spring — card expand/collapse, sheet interactions
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.80)

    /// Gentle spring — message appearance
    static let gentleSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Snappy spring — button presses, micro-interactions
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.7)

    /// Breathing animation for empty state logo
    static let breathing = Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)
}

// MARK: - Shadow Presets

enum DesignShadow {

    /// Subtle elevation for action cards
    static let subtle = Color.black.opacity(0.04)

    /// Medium elevation for modals / sheets
    static let medium = Color.black.opacity(0.08)

    /// Strong elevation for floating elements
    static let strong = Color.black.opacity(0.12)
}
