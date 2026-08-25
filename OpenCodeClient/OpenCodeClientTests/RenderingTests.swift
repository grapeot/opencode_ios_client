//
//  RenderingTests.swift
//  OpenCodeClientTests
//

import Foundation
import SwiftUI
import Testing
@testable import OpenCodeClient

struct WorkspaceMarkdownImageProviderTests {

    @Test func imageBaseURLResolvesParentDirectoryAssetPath() {
        let baseURL = WorkspaceMarkdownImageProvider.imageBaseURL(
            markdownFilePath: "adhoc_jobs/health_quantification/docs/reports/health_synthesis_report_2026-04-09.md"
        )
        let imageURL = URL(string: "../assets/timeline_40d.png", relativeTo: baseURL)
        #expect(
            WorkspaceMarkdownImageProvider.workspaceRelativePath(from: imageURL)
                == "adhoc_jobs/health_quantification/docs/assets/timeline_40d.png"
        )
    }

    @Test func decodesBase64DataURL() {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XGZ0AAAAASUVORK5CYII="
        let url = URL(string: "data:image/png;base64,\(pngBase64)")
        let data = WorkspaceMarkdownImageProvider.decodeDataURL(url)
        #expect(data == Data(base64Encoded: pngBase64))
    }

    @Test func workspaceRelativePathStripsAbsoluteWorkspacePrefix() {
        let url = URL(string: "opencode-workspace://workspace/Users/test/workspace/docs/assets/chart.png")
        #expect(
            WorkspaceMarkdownImageProvider.workspaceRelativePath(
                from: url,
                workspaceDirectory: "/Users/test/workspace"
            ) == "docs/assets/chart.png"
        )
    }

    @Test func workspaceRelativePathReturnsNilForHTTPSURL() {
        let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/05/Yonghe_Temple_entrance.jpg")
        #expect(WorkspaceMarkdownImageProvider.workspaceRelativePath(from: url) == nil)
    }

    @Test func workspaceRelativePathReturnsNilForHTTPURL() {
        let url = URL(string: "http://example.com/image.png")
        #expect(WorkspaceMarkdownImageProvider.workspaceRelativePath(from: url) == nil)
    }

    @Test func decodeDataURLReturnsNilForHTTPSURL() {
        let url = URL(string: "https://example.com/image.png")
        #expect(WorkspaceMarkdownImageProvider.decodeDataURL(url) == nil)
    }
}

struct MarkdownPreviewViewTests {

    @Test func resolveImagesUsesMarkdownFileDirectoryForBareRelativePath() async {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XGZ0AAAAASUVORK5CYII="
        let markdown = "![chart](execution_model_comparison.jpg)"

        let resolved = await MarkdownImageResolver.resolveImages(
            in: markdown,
            markdownFilePath: "contexts/survey_sessions/glm51_highspeed_api.md",
            workspaceDirectory: "/Users/test/knowledge_working",
            fetchContent: { path in
                #expect(path == "contexts/survey_sessions/execution_model_comparison.jpg")
                return FileContent(type: "text", content: pngBase64)
            }
        )

        #expect(resolved.contains("data:image/jpeg;base64,\(pngBase64)"))
    }

    @Test func normalizeStandaloneImageBlocksSeparatesCaption() {
        let markdown = """
        ![雍和宫入口](https://example.com/yonghe.jpg)
        *图注文字*
        """

        let normalized = MarkdownPreviewView.normalizeStandaloneImageBlocks(markdown)

        #expect(normalized == """
        ![雍和宫入口](https://example.com/yonghe.jpg)

        *图注文字*
        """)
    }

    @Test func normalizeStandaloneImageBlocksLeavesExistingBlankLine() {
        let markdown = """
        ![chart](assets/chart.png)

        Caption
        """

        #expect(MarkdownPreviewView.normalizeStandaloneImageBlocks(markdown) == markdown)
    }

    @Test func normalizeStandaloneImageBlocksDoesNotChangeInlineImageText() {
        let markdown = "Before ![inline](assets/icon.png) after"

        #expect(MarkdownPreviewView.normalizeStandaloneImageBlocks(markdown) == markdown)
    }
}

@Suite(.serialized)
struct LocalizationTests {

    @Test func localizationKeyCoverage() {
        #expect(L10n.missingEnglishKeys.isEmpty)
        #expect(L10n.missingChineseKeys.isEmpty)
    }

    @Test func languagePreferenceOverridesSystemLanguage() {
        let key = L10n.languagePreferenceUserDefaultsKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        L10n.languagePreference = .zh
        #expect(L10n.t(.appChat) == "聊天")

        L10n.languagePreference = .en
        #expect(L10n.t(.appChat) == "Chat")
    }

    @Test func countHelpersFormatStableLocalizedIntegers() {
        let key = L10n.languagePreferenceUserDefaultsKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        L10n.languagePreference = .en
        #expect(L10n.toolCallsCount(2) == "2 tool calls")
        #expect(L10n.sessionsFiles(2) == "2 files")
        #expect(L10n.patchFilesChanged(2) == "2 files changed")

        L10n.languagePreference = .zh
        #expect(L10n.toolCallsCount(2) == "2 个工具调用")
        #expect(L10n.sessionsFiles(2) == "2 个文件")
        #expect(L10n.patchFilesChanged(2) == "2 个文件已变更")
    }
}

// MARK: - LayoutConstants Tests

struct LayoutConstantsTests {
    
    @Test func splitViewFractions() {
        #expect(LayoutConstants.SplitView.sidebarWidthFraction == CGFloat(1) / CGFloat(6))
        #expect(LayoutConstants.SplitView.previewWidthFraction == CGFloat(5) / CGFloat(12))
        #expect(LayoutConstants.SplitView.chatWidthFraction == CGFloat(5) / CGFloat(12))
    }
    
    @Test func splitViewFractionsSum() {
        let total = LayoutConstants.SplitView.sidebarWidthFraction 
                  + LayoutConstants.SplitView.previewWidthFraction 
                  + LayoutConstants.SplitView.chatWidthFraction
        #expect(total == 1.0)
    }
    
    @Test func splitViewBoundFractions() {
        #expect(LayoutConstants.SplitView.sidebarMinFraction < LayoutConstants.SplitView.sidebarWidthFraction)
        #expect(LayoutConstants.SplitView.sidebarMaxFraction > LayoutConstants.SplitView.sidebarWidthFraction)
        #expect(LayoutConstants.SplitView.paneMinFraction < LayoutConstants.SplitView.previewWidthFraction)
        #expect(LayoutConstants.SplitView.paneMaxFraction > LayoutConstants.SplitView.previewWidthFraction)
    }
    
    @Test func animationDurations() {
        #expect(LayoutConstants.Animation.shortDuration < LayoutConstants.Animation.defaultDuration)
        #expect(LayoutConstants.Animation.defaultDuration < LayoutConstants.Animation.longDuration)
    }
    
    @Test func spacingValues() {
        #expect(LayoutConstants.Spacing.compact < LayoutConstants.Spacing.standard)
        #expect(LayoutConstants.Spacing.standard < LayoutConstants.Spacing.comfortable)
        #expect(LayoutConstants.Spacing.comfortable < LayoutConstants.Spacing.spacious)
    }

    @Test func messageListSpacing() {
        #expect(LayoutConstants.MessageList.spacing == 20)
    }
}

struct MessageRenderingHeuristicTests {

    @Test func markdownHeuristicDetectsPlainText() {
        #expect(MessageRowView.hasMarkdownSyntax("this is a plain sentence") == false)
    }

    @Test func markdownHeuristicDetectsHeader() {
        #expect(MessageRowView.hasMarkdownSyntax("# Title") == true)
    }

    @Test func markdownHeuristicDetectsCodeFence() {
        #expect(MessageRowView.hasMarkdownSyntax("```swift\nprint(1)\n```") == true)
    }

    @Test func renderableTextRejectsWhitespaceOnlyParts() {
        #expect(MessageRowView.isRenderableText("\n\n\n\n\n\n") == false)
        #expect(MessageRowView.isRenderableText("   \n\t  ") == false)
        #expect(MessageRowView.isRenderableText("") == false)
        #expect(MessageRowView.isRenderableText(nil) == false)
    }

    @Test func renderableTextAcceptsContentWithSurroundingWhitespace() {
        #expect(MessageRowView.isRenderableText("\n\nhello\n\n\n") == true)
        #expect(MessageRowView.isRenderableText("real content") == true)
        #expect(MessageRowView.isRenderableText("  padded  ") == true)
    }

    @Test func assistantBlocksSkipsWhitespaceOnlyTextParts() throws {
        let parts: [Part] = try [
            """
            {"id":"p1","messageID":"m1","sessionID":"s1","type":"text","text":"\\n\\n\\n\\n\\n\\n"}
            """,
            """
            {"id":"p2","messageID":"m1","sessionID":"s1","type":"text","text":"\\n\\nreal content\\n\\n\\n"}
            """
        ].map { try JSONDecoder().decode(Part.self, from: Data($0.utf8)) }

        let blocks = MessageRowView.buildAssistantBlocks(parts: parts)
        #expect(blocks.count == 1)
        guard case .text(let part) = blocks[0] else {
            Issue.record("expected a single text block")
            return
        }
        #expect(part.id == "p2")
    }

    @Test func assistantBlocksMergesToolRunAcrossWhitespaceTextPart() throws {
        let parts: [Part] = try [
            """
            {"id":"t1","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash"}
            """,
            """
            {"id":"p1","messageID":"m1","sessionID":"s1","type":"text","text":"\\n\\n"}
            """,
            """
            {"id":"t2","messageID":"m1","sessionID":"s1","type":"tool","tool":"read"}
            """,
            """
            {"id":"p2","messageID":"m1","sessionID":"s1","type":"text","text":"done"}
            """
        ].map { try JSONDecoder().decode(Part.self, from: Data($0.utf8)) }

        let blocks = MessageRowView.buildAssistantBlocks(parts: parts)
        #expect(blocks.count == 2)
        guard case .cards(let cards) = blocks[0] else {
            Issue.record("expected a cards block")
            return
        }
        #expect(cards.map(\.id) == ["t1", "t2"])
        guard case .text(let part) = blocks[1] else {
            Issue.record("expected a text block")
            return
        }
        #expect(part.id == "p2")
    }

    @Test func copyableMessageTextJoinsTextPartsAcrossMarkdownBlocks() throws {
        let json = """
        {
          "info": {
            "id": "message-1",
            "sessionID": "session-1",
            "role": "assistant",
            "time": { "created": 1 }
          },
          "parts": [
            { "id": "part-1", "sessionID": "session-1", "messageID": "message-1", "type": "text", "text": "First paragraph" },
            { "id": "part-2", "sessionID": "session-1", "messageID": "message-1", "type": "text", "text": "- second\\n- third" }
          ]
        }
        """
        let message = try JSONDecoder().decode(MessageWithParts.self, from: Data(json.utf8))

        #expect(
            MessageRowView.copyableText(for: message)
                == "First paragraph\n\n- second\n- third"
        )
    }

    @Test func selectionTextPreservesMarkdownBlockBoundaries() {
        let markdown = """
        # Heading

        First **paragraph**.

        - second
        - third

        ```swift
        print("**literal**")
        ```
        """

        #expect(
            MessageRowView.selectionText(from: markdown)
                == "Heading\n\nFirst paragraph.\n\n- second\n- third\n\nprint(\"**literal**\")"
        )
    }

    @Test func largeMessageDetectionSkipsExpensiveMarkdownRendering() {
        let text = String(repeating: "- Wells Fargo agreement\n", count: 3_000)

        #expect(MessageRowView.isLargeMessage(text) == true)
        #expect(MessageRowView.largeMessagePreview(text).count == 12_000)
    }

    @Test func ringStatusConsolePasteSkipsExpensiveMarkdownRendering() {
        let text = String(repeating: "$ smart_home git:(master) npm run ring:status\n", count: 360)

        #expect(text.count > 12_000)
        #expect(MessageRowView.isLargeMessage(text) == true)
        #expect(MessageRowView.largeMessagePreview(text).count == 12_000)
    }
}

struct MessageThinkLeakNormalizationTests {

    @Test func normalizedTextCutsLeakedTailToLastStandaloneClose() {
        let input = "Let me start with the DB. First, check if the DB exists.\n"
            + MessageRowView.thinkCloseTag + "\n\n"
            + "Now let me check the actual data."
        #expect(MessageRowView.normalizedText(input) == "Now let me check the actual data.")
    }

    @Test func normalizedTextRemovesPureThinkingTail() {
        let input = "Still thinking about the schema...\n"
            + MessageRowView.thinkCloseTag + "\n\n"
        #expect(MessageRowView.normalizedText(input).isEmpty)
    }

    @Test func normalizedTextCutsTailEvenWhenTailQuotesATagPair() {
        // The leaked tail itself quotes a full open/close example pair; the
        // pair must not consume the real final close, or the leading tail text
        // would survive into the response body.
        let input = "Leaked thinking, quoting the markers: "
            + MessageRowView.thinkOpenTag + "\n"
            + "example thinking\n"
            + MessageRowView.thinkCloseTag + "\n\n"
            + MessageRowView.thinkCloseTag + "\n\n"
            + "Real response."
        #expect(MessageRowView.normalizedText(input) == "Real response.")
    }

    @Test func normalizedTextCutsDanglingOpenTagToTheEnd() {
        let input = "Some real answer.\n"
            + MessageRowView.thinkOpenTag + "\n"
            + "truncated thinking..."
        #expect(MessageRowView.normalizedText(input) == "Some real answer.")
    }

    @Test func normalizedTextLeavesInlineTagsUntouched() {
        let input = "The markers are `\(MessageRowView.thinkOpenTag)` and `\(MessageRowView.thinkCloseTag)` inline."
        #expect(MessageRowView.normalizedText(input) == input)
    }

    @Test func normalizedTextLeavesFencedTagsUntouched() {
        let input = "```swift\n"
            + MessageRowView.thinkOpenTag + "\n"
            + "code content\n"
            + MessageRowView.thinkCloseTag + "\n"
            + "```\n"
            + "Real response."
        #expect(MessageRowView.normalizedText(input) == input)
    }

    @Test func normalizedTextTildeFenceIgnoresPartialFenceLines() {
        // A line that merely starts with the fence char must not close the fence.
        let input = "~~~\n"
            + MessageRowView.thinkCloseTag + "\n"
            + MessageRowView.thinkCloseTag + " info\n"
            + "~~~\n"
            + "After."
        #expect(MessageRowView.normalizedText(input) == input)
    }

    @Test func copyableTextNormalizesAssistantAndKeepsUserVerbatim() throws {
        let json = """
        {
          "info": { "id": "message-1", "sessionID": "session-1", "role": "assistant", "time": { "created": 1 } },
          "parts": [
            { "id": "part-1", "sessionID": "session-1", "messageID": "message-1", "type": "text", "text": "\\n\\n\\n" },
            { "id": "part-2", "sessionID": "session-1", "messageID": "message-1", "type": "text", "text": "leaked tail\\n\\u003C/think\\u003E\\n\\n" },
            { "id": "part-3", "sessionID": "session-1", "messageID": "message-1", "type": "text", "text": "Real answer." }
          ]
        }
        """
        let assistant = try JSONDecoder().decode(MessageWithParts.self, from: Data(json.utf8))
        #expect(MessageRowView.copyableText(for: assistant) == "Real answer.")

        let userJson = """
        {
          "info": { "id": "message-2", "sessionID": "session-1", "role": "user", "time": { "created": 2 } },
          "parts": [
            { "id": "part-4", "sessionID": "session-1", "messageID": "message-2", "type": "text", "text": "Discuss `\\u003C/think\\u003E` please\\n\\n\\n" }
          ]
        }
        """
        let user = try JSONDecoder().decode(MessageWithParts.self, from: Data(userJson.utf8))
        #expect(MessageRowView.copyableText(for: user) == "Discuss `\u{3C}/think\u{3E}` please")
    }

    @Test func assistantBlocksSkipThinkingTailPartsAndKeepMerging() throws {
        let parts: [Part] = try [
            """
            {"id":"t1","messageID":"m1","sessionID":"s1","type":"tool","tool":"bash"}
            """,
            """
            {"id":"p1","messageID":"m1","sessionID":"s1","type":"text","text":"leaked tail\\n\\u003C/think\\u003E\\n\\n"}
            """,
            """
            {"id":"t2","messageID":"m1","sessionID":"s1","type":"tool","tool":"read"}
            """,
            """
            {"id":"p2","messageID":"m1","sessionID":"s1","type":"text","text":"done"}
            """
        ].map { try JSONDecoder().decode(Part.self, from: Data($0.utf8)) }

        let blocks = MessageRowView.buildAssistantBlocks(parts: parts)
        #expect(blocks.count == 2)
        guard case .cards(let cards) = blocks[0] else {
            Issue.record("expected a cards block")
            return
        }
        #expect(cards.map(\.id) == ["t1", "t2"])
        guard case .text(let part) = blocks[1] else {
            Issue.record("expected a text block")
            return
        }
        #expect(part.id == "p2")
    }
}

struct ChatScrollBehaviorTests {

    @Test func shouldAutoScrollWhenBottomMarkerIsVisible() {
        #expect(
            ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: 640,
                viewportHeight: 600,
                threshold: 80
            ) == true
        )
    }

    @Test func shouldAutoScrollWhenBottomMarkerIsNearViewportBottom() {
        #expect(
            ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: 675,
                viewportHeight: 600,
                threshold: 80
            ) == true
        )
    }

    @Test func shouldNotAutoScrollWhenUserHasScrolledAwayFromBottom() {
        #expect(
            ChatScrollBehavior.shouldAutoScroll(
                bottomMarkerMinY: 760,
                viewportHeight: 600,
                threshold: 80
            ) == false
        )
    }
}

struct SessionListEdgeSwipeBehaviorTests {

    @Test func opensForLeftEdgeSwipeWithStrongHorizontalTravel() {
        #expect(
            SessionListEdgeSwipeBehavior.shouldOpenSessionList(
                startLocation: CGPoint(x: 12, y: 180),
                translation: CGSize(width: 120, height: 18)
            ) == true
        )
    }

    @Test func ignoresSwipeThatStartsAwayFromLeftEdge() {
        #expect(
            SessionListEdgeSwipeBehavior.shouldOpenSessionList(
                startLocation: CGPoint(x: 60, y: 180),
                translation: CGSize(width: 120, height: 12)
            ) == false
        )
    }

    @Test func ignoresMostlyVerticalDrag() {
        #expect(
            SessionListEdgeSwipeBehavior.shouldOpenSessionList(
                startLocation: CGPoint(x: 8, y: 180),
                translation: CGSize(width: 110, height: 90)
            ) == false
        )
    }
}

// MARK: - Design Tokens Tests

@MainActor
struct DesignTokensTests {

    @Test func spacingScaleIsConsistent() {
        #expect(DesignSpacing.xs == 4)
        #expect(DesignSpacing.sm == 8)
        #expect(DesignSpacing.md == 12)
        #expect(DesignSpacing.lg == 16)
        #expect(DesignSpacing.xl == 20)
        #expect(DesignSpacing.xxl == 24)
        #expect(DesignSpacing.messageVertical == 20)
        #expect(DesignSpacing.cardPadding == 12)
        #expect(DesignSpacing.cardGap == 16)
    }

    @Test func spacingIncreasesMonotonically() {
        let values = [DesignSpacing.xs, DesignSpacing.sm, DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xl, DesignSpacing.xxl]
        for i in 0..<(values.count - 1) {
            #expect(values[i] < values[i + 1])
        }
    }

    @Test func cornerRadiiArePositive() {
        #expect(DesignCorners.small > 0)
        #expect(DesignCorners.medium > DesignCorners.small)
        #expect(DesignCorners.large > DesignCorners.medium)
    }

    @Test func brandPrimaryIsElectricBlueTone() {
        let brand = DesignColors.Brand.primary
        let uiColor = UIColor(brand)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.2 && r < 0.3)
        #expect(g > 0.3 && g < 0.6)
        #expect(b > 0.8)
    }

    @Test func brandGoldIsWarmTone() {
        let gold = DesignColors.Brand.gold
        let uiColor = UIColor(gold)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.7)
        #expect(g > 0.5 && g < 0.8)
        #expect(b < 0.3)
    }

    @Test func opacityValuesAreInValidRange() {
        #expect(DesignColors.Opacity.surfaceFill > 0 && DesignColors.Opacity.surfaceFill < 0.2)
        #expect(DesignColors.Opacity.surfaceFillDark > 0 && DesignColors.Opacity.surfaceFillDark < 0.2)
        #expect(DesignColors.Opacity.borderStroke > 0 && DesignColors.Opacity.borderStroke < 0.3)
        #expect(DesignColors.Opacity.userMessageFill > 0 && DesignColors.Opacity.userMessageFill < 0.2)
        #expect(DesignColors.Opacity.selectionFill > 0 && DesignColors.Opacity.selectionFill < 0.2)
    }

    @Test func darkModeOpacityHigherThanLight() {
        #expect(DesignColors.Opacity.surfaceFillDark > DesignColors.Opacity.surfaceFill)
        #expect(DesignColors.Opacity.borderStrokeDark > DesignColors.Opacity.borderStroke)
        #expect(DesignColors.Opacity.userMessageFillDark > DesignColors.Opacity.userMessageFill)
    }

    @Test func animationPresetSlotsArePopulated() {
        let all: [String: Animation] = [
            "quick": DesignAnimation.quick,
            "standard": DesignAnimation.standard,
            "spring": DesignAnimation.spring,
            "gentleSpring": DesignAnimation.gentleSpring,
            "snappy": DesignAnimation.snappy,
            "breathing": DesignAnimation.breathing,
        ]
        #expect(all.count == 6)
    }

    @Test func semanticColorsAreDistinct() {
        let error = UIColor(DesignColors.Semantic.error)
        let success = UIColor(DesignColors.Semantic.success)
        let warning = UIColor(DesignColors.Semantic.warning)
        let info = UIColor(DesignColors.Semantic.info)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        error.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        success.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #expect(r1 != r2 || g1 != g2 || b1 != b2)
        warning.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #expect(r1 != r2 || g1 != g2 || b1 != b2)
        info.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #expect(r1 != r2 || g1 != g2 || b1 != b2)
    }
}
