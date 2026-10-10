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
        // A previous suite (Tier4Driver) may leave the simulator in landscape;
        // the layout assertions below assume the portrait 2-up grid.
        XCUIDevice.shared.orientation = .portrait
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

        let readCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'toolcard.read.'")
        let writeCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'toolcard.write.'")
        let readCards = app.descendants(matching: .any).matching(readCardPredicate)
        let writeCards = app.descendants(matching: .any).matching(writeCardPredicate)

        // The chat scroll view auto-scrolls to the bottom on launch, so the
        // file-card grid (top of the assistant turn) is un-materialized while
        // the merged disclosure row (bottom) is visible. Lazy cells only
        // materialize inside the viewport — assert each region while it is
        // on screen.

        // The merged "N tool calls" disclosure row.
        let toolCalls = app.descendants(matching: .any)["toolcard.toolcalls"]
        XCTAssertTrue(toolCalls.waitForExistence(timeout: 8), "toolcard.toolcalls 合并行应存在")

        // Capture the collapsed state before expanding.
        attachScreenshot(named: "oc_toolcards_collapsed")

        // Scroll up (swipe down) until the file-card grid enters the viewport.
        var scrolled = 0
        while !(readCards.firstMatch.exists || writeCards.firstMatch.exists) && scrolled < 5 {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 1.0)
            scrolled += 1
        }
        XCTAssertTrue(readCards.firstMatch.waitForExistence(timeout: 4), "至少一个 toolcard.read.* 读文件卡应渲染")
        XCTAssertTrue(writeCards.firstMatch.waitForExistence(timeout: 4), "至少一个 toolcard.write.* 写文件卡应渲染")

        // Scroll back down to the merged row and expand it.
        while !toolCalls.firstMatch.exists && scrolled > 0 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.0)
            scrolled -= 1
        }
        toolCalls.firstMatch.tap()

        let revealed = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'npm test'")
        ).firstMatch
        XCTAssertTrue(revealed.waitForExistence(timeout: 6), "展开 toolcard.toolcalls 后应出现合并工具的内容（如 'npm test'）")

        // Capture the expanded state — primary visual QA artifact.
        attachScreenshot(named: "oc_toolcards")
    }

    @MainActor
    func testExpandedToolDetailsShowErrorBodies() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOOL_CARDS_FIXTURE"]
        app.launch()

        let toolCalls = app.descendants(matching: .any)["toolcard.toolcalls"]
        XCTAssertTrue(toolCalls.waitForExistence(timeout: 8))
        if !toolCalls.isHittable {
            app.swipeUp()
        }
        toolCalls.tap()

        tapUniqueToolDetail("toolcard.detail.ap-todo-error", in: app)
        let todoError = app.descendants(matching: .any)["toolcard.error.ap-todo-error"]
        XCTAssertTrue(todoError.waitForExistence(timeout: 6))
        XCTAssertTrue(todoError.label.contains("W02_TODOWRITE_ERROR"))

        tapUniqueToolDetail("toolcard.detail.ap-image-error", in: app)
        let imageError = app.descendants(matching: .any)["toolcard.error.ap-image-error"]
        XCTAssertTrue(imageError.waitForExistence(timeout: 6))
        XCTAssertTrue(imageError.label.contains("W02_IMAGE_READ_ERROR"))

        tapUniqueToolDetail("toolcard.detail.ap-todo-success", in: app)
        XCTAssertFalse(app.staticTexts["W02_TODO_SUCCESS_OUTPUT"].waitForExistence(timeout: 1))
    }

    @MainActor
    private func tapUniqueToolDetail(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier == %@", identifier)).count, 1)
        if !button.isHittable {
            app.swipeUp()
        }
        button.tap()
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
