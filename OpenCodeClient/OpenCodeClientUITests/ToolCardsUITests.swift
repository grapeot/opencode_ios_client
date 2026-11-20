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
    func testWideToolCardsReflowWhenFilesIsVisible() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TOOL_CARDS_FIXTURE", "-AppleLanguages", "(en)"]
        app.launch()
        let descendants = app.descendants(matching: .any)
        guard descendants["ipad-workspace-layout"].waitForExistence(timeout: 6) else {
            throw XCTSkip("Requires the wide landscape workspace")
        }
        let layout = app.buttons["layout-preference-menu"]
        let pin = app.buttons["Keep Files Open"]
        let files = app.navigationBars.matching(identifier: "Files").firstMatch
        if !files.isHittable {
            layout.tap()
            pin.tap()
        }
        let read = descendants["toolcard.read.client.ts"]
        let edit = descendants["toolcard.write.types.ts"]
        let write = descendants["toolcard.write.README.md"]
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.37))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.65))
        for _ in 0..<3 where !read.isHittable { from.press(forDuration: 0.05, thenDragTo: to) }
        XCTAssertTrue(read.isHittable)
        XCTAssertTrue(edit.isHittable)
        XCTAssertTrue(write.isHittable)
        XCTAssertEqual(read.frame.minY, edit.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(write.frame.minY, edit.frame.minY + 10)
        XCTAssertEqual(write.frame.minX, read.frame.minX, accuracy: 2)
        attachWorkspaceScreens(named: "wide-tool-cards-with-files")

        app.buttons["chat-toolbar-model"].tap()
        XCTAssertTrue(app.navigationBars["Model & Agent"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["chat-toolbar-todo"].tap()
        XCTAssertTrue(app.navigationBars["Todo"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        layout.tap()
        pin.tap()
        XCTAssertTrue(read.isHittable)
        XCTAssertEqual(read.frame.minY, write.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(write.frame.minX, edit.frame.minX)
        attachWorkspaceScreens(named: "wide-tool-cards-without-files")
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
    private func attachWorkspaceScreens(named name: String) {
        let screens = XCUIScreen.screens
        if screens.count <= 1 {
            attachScreenshot(named: name)
        } else {
            // Duo exposes the cover and inner screens first; other entries may be disconnected.
            for (index, screen) in screens.prefix(2).enumerated() {
                attachScreenshot(named: "\(name)-display-\(index)", screenshot: screen.screenshot())
            }
        }
    }

    @MainActor
    private func attachScreenshot(named name: String, screenshot: XCUIScreenshot? = nil) {
        let attachment = XCTAttachment(screenshot: screenshot ?? XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
