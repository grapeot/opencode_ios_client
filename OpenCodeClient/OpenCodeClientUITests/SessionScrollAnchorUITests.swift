//
//  SessionScrollAnchorUITests.swift
//  OpenCodeClientUITests
//
//  Regression tests for per-session scroll anchoring. The chat ScrollView
//  carries a fresh identity per session (.id(sessionID)) plus
//  defaultScrollAnchor(.bottom), so a long session must start at its bottom
//  and switching away to another session and back must land at the bottom
//  again. Previously the shared ScrollView kept its old contentOffset across
//  session switches and dropped the view in the middle of the conversation.
//
//  Runs fully offline via UITEST_SESSION_SCROLL_FIXTURE (see
//  SessionScrollFixture.swift in the app target).
//

import XCTest

final class SessionScrollAnchorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Layout assertions assume portrait.
        XCUIDevice.shared.orientation = .portrait
    }

    /// First render of a session whose loaded window is far taller than the
    /// viewport must start at the bottom (defaultScrollAnchor(.bottom)).
    @MainActor
    func testLongSessionFirstRenderStartsAtBottom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_SCROLL_FIXTURE"]
        app.launch()

        let last = bottomAnchorMessage(in: app)
        XCTAssertTrue(last.waitForExistence(timeout: 12), "Last user message of the long session should be in the tree")
        settle(seconds: 1.0)

        XCTAssertTrue(isOnScreen(last), "Bottom-anchored first render should show the last message without scrolling")
        XCTAssertFalse(isOnScreen(topAnchorMessage(in: app)), "First message should be above the viewport at the bottom anchor")
        attachScreenshot(named: "oc_scroll_anchor_initial")
    }

    /// Switching to another session and back must land at the bottom of the
    /// long session again, not at the previously retained scroll offset.
    @MainActor
    func testSessionRoundTripLandsAtBottom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_SCROLL_FIXTURE"]
        app.launch()

        XCTAssertTrue(
            bottomAnchorMessage(in: app).waitForExistence(timeout: 12),
            "Fixture long session should be visible at launch"
        )

        // Switch to the short session, then back to the long one.
        selectSessionRow(app, id: "scroll-short-session")
        XCTAssertTrue(
            app.staticTexts["Short answer"].waitForExistence(timeout: 8),
            "Short session content should render after the switch"
        )
        selectSessionRow(app, id: "scroll-long-session")

        let last = bottomAnchorMessage(in: app)
        XCTAssertTrue(last.waitForExistence(timeout: 8), "Long session content should render after the round trip")
        // Give the post-load auto-scroll (50ms task + layout) time to settle.
        settle(seconds: 1.5)

        XCTAssertTrue(isOnScreen(last), "After switching away and back, the view should be at the bottom of the long session")
        XCTAssertFalse(isOnScreen(topAnchorMessage(in: app)), "After the round trip the view should be at the bottom, not the top")
        attachScreenshot(named: "oc_scroll_anchor_roundtrip")
    }

    @MainActor
    func testBulkArchiveCountsCollapsedChildAndKeepsListOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_SCROLL_FIXTURE", "UITEST_BULK_ARCHIVE", "-AppleLanguages", "(en)"]
        app.launch()

        let select = app.buttons["session-archive-select"]
        if UIDevice.current.userInterfaceIdiom == .phone {
            let open = app.buttons["chat-toolbar-session-list"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            open.tap()
        }
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()

        let archive = app.buttons["session-archive-submit"]
        XCTAssertFalse(archive.isEnabled)
        let parent = app.descendants(matching: .any)["session-row-scroll-long-session"].firstMatch
        XCTAssertTrue(parent.exists)
        XCTAssertFalse(app.descendants(matching: .any)["session-row-scroll-hidden-child"].exists)
        parent.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        XCTAssertEqual(archive.label, "Archive 2")
        let other = app.descendants(matching: .any)["session-row-scroll-short-session"].firstMatch
        other.tap()
        XCTAssertEqual(archive.label, "Archive 3")
        attachScreenshot(named: "bulk_archive_selection")
        archive.tap()

        let result = app.staticTexts["session-archive-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "Archived: 3")
        attachScreenshot(named: "bulk_archive_toast")
        XCTAssertTrue(select.exists)
        XCTAssertFalse(parent.exists)
        app.buttons["Archived"].tap()
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        XCTAssertTrue(other.exists)
        app.buttons["session-toggle-scroll-long-session"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["session-row-scroll-hidden-child"].waitForExistence(timeout: 5))
        XCTAssertTrue(result.waitForNonExistence(timeout: 6), "Success toast should dismiss itself")
        attachScreenshot(named: "bulk_archive_result")
    }

    // MARK: - Helpers

    private func bottomAnchorMessage(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'Long message 039'")
        ).firstMatch
    }

    private func topAnchorMessage(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'Long message 001'")
        ).firstMatch
    }

    private func selectSessionRow(_ app: XCUIApplication, id: String) {
        let openButton = app.buttons["chat-toolbar-session-list"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8), "Session list button should exist")
        openButton.tap()

        let row = app.descendants(matching: .any)["session-row-\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Session row \(id) should exist in the sheet")
        row.tap()
        // Let the stub-backed reload and the sheet dismissal settle.
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func settle(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// XCUITest `exists` only means "in the hierarchy"; the frame check is what
    /// distinguishes visible from scrolled-away rows (off-screen rows above the
    /// viewport report a negative minY).
    private func isOnScreen(_ element: XCUIElement) -> Bool {
        guard element.exists, element.frame.width > 0, element.frame.height > 0 else { return false }
        let frame = element.frame
        let screen = UIScreen.main.bounds
        return frame.minY >= -8 && frame.minY < screen.height - 8
    }

    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
