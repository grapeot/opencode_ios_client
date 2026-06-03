//
//  ToolCardsUITests.swift
//  OpenCodeClientUITests
//
//  UX test for the "tool card render redo": launches with a deterministic injected
//  assistant turn (UITEST_TOOL_CARDS_FIXTURE) and asserts the new rendering:
//  assistant fixture text, file-operation cards (2-column grid), and the merged
//  "N tool calls" disclosure row (expandable). Captures a screenshot for
//  visual QA. Anchored on accessibility identifiers per AGENTS.md (no TextField queries).
//

import XCTest

final class ToolCardsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testToolCardsFixtureRendersFileCardsAndMergedToolCalls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOOL_CARDS_FIXTURE"]
        app.launch()

        // Assistant fixture content.
        let assistantText = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Here are the changes I made'")
        ).firstMatch
        XCTAssertTrue(assistantText.waitForExistence(timeout: 12), "fixture assistant text 应可见")

        // Read/write file cards must be distinguishable in the accessibility tree.
        let readCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'toolcard.read.'")
        let writeCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'toolcard.write.'")
        let readCards = app.descendants(matching: .any).matching(readCardPredicate)
        let writeCards = app.descendants(matching: .any).matching(writeCardPredicate)

        XCTAssertTrue(readCards.firstMatch.waitForExistence(timeout: 8), "至少一个 toolcard.read.* 读文件卡应渲染")
        XCTAssertTrue(writeCards.firstMatch.waitForExistence(timeout: 8), "至少一个 toolcard.write.* 写文件卡应渲染")

        // Sanity: expect multiple file cards from the fixture (read/edit/write + patch).
        XCTAssertGreaterThanOrEqual(readCards.count + writeCards.count, 3, "应渲染出多个文件卡（fixture 注入了 4 个）")

        // The merged "N tool calls" disclosure row.
        let toolCalls = app.descendants(matching: .any)["toolcard.toolcalls"]
        XCTAssertTrue(toolCalls.waitForExistence(timeout: 8), "toolcard.toolcalls 合并行应存在")

        // Capture the collapsed state before expanding.
        attachScreenshot(named: "oc_toolcards_collapsed")

        // Expand the disclosure group and assert it reveals merged tool content.
        // "list" tool output contains "client.ts" — a string only visible once expanded.
        let expandedMarkerBefore = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'client.ts'")
        ).count

        toolCalls.tap()

        let expandedMarker = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'npm test'")
        ).firstMatch
        let revealed = expandedMarker.waitForExistence(timeout: 6)
            || app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'client.ts'")).count > expandedMarkerBefore
        XCTAssertTrue(revealed, "展开 toolcard.toolcalls 后应出现合并工具的内容（如 'npm test' / 'client.ts'）")

        // Capture the expanded state — primary visual QA artifact.
        attachScreenshot(named: "oc_toolcards")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
