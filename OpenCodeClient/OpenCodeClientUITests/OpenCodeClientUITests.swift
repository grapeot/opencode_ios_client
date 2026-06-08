//
//  OpenCodeClientUITests.swift
//  OpenCodeClientUITests
//
//  Created by Yan Wang on 2/12/26.
//

import XCTest

final class OpenCodeClientUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    /// 2.3 ChatTabView baseline: 验证 Chat 页加载后输入框可见（refactor 后用此测试回归）
    @MainActor
    func testChatTabShowsInputField() throws {
        let app = XCUIApplication()
        app.launch()
        let askField = app.textViews["chat-input"]
        XCTAssertTrue(askField.waitForExistence(timeout: 8), "Chat 输入框应可见")
    }

    @MainActor
    func testChatComposerLongInputRemainsScrollable() throws {
        let app = XCUIApplication()
        app.launch()

        let composer = app.textViews["chat-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8), "Chat 输入框应可见")

        composer.tap()
        composer.typeText((1...18).map { "Line \($0)" }.joined(separator: "\n"))
        composer.swipeUp()

        let screenshot = composer.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "chat-composer-long-input"
        attachment.lifetime = .keepAlways
        add(attachment)

        let composerValue = composer.value as? String ?? ""
        XCTAssertTrue(composerValue.contains("Line 18"), "输入框应保留完整长文本内容")
    }

    @MainActor
    func testSessionListFixtureShowsArchiveSections() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_SESSION_TREE_FIXTURE")
        app.launch()

        app.buttons["chat-toolbar-session-list"].tap()

        XCTAssertTrue(app.staticTexts["Root Session"].waitForExistence(timeout: 8), "Root session 应可见")
        XCTAssertTrue(app.staticTexts["Child Session"].waitForExistence(timeout: 8), "Child session 应可见，避免回归到 root-only 列表")
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 8), "Archived section header 应可见")

        app.staticTexts["Archived"].tap()

        XCTAssertTrue(app.staticTexts["Archived Session"].waitForExistence(timeout: 8), "Archived session 应可见")
        XCTAssertTrue(app.staticTexts["Archived Child"].waitForExistence(timeout: 8), "Archived child 应可见")

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "session-archive-fixture"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCaptureSessionArchiveFixtureScreenshot() throws {
        guard let path = tier4ScreenshotPath(), !path.isEmpty else {
            throw XCTSkip("Set TIER4_SCREENSHOT_PATH to write a deterministic archive UI screenshot")
        }

        let app = XCUIApplication()
        app.launchArguments.append("UITEST_SESSION_TREE_FIXTURE")
        app.launch()

        if app.buttons["chat-toolbar-session-list"].waitForExistence(timeout: 8) {
            app.buttons["chat-toolbar-session-list"].tap()
        }

        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 8), "Archived section header 应可见")
        app.staticTexts["Archived"].tap()
        XCTAssertTrue(app.staticTexts["Archived Session"].waitForExistence(timeout: 8), "Archived session 应可见")
        XCTAssertTrue(app.staticTexts["Archived Child"].waitForExistence(timeout: 8), "Archived child 应可见")

        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func tier4ScreenshotPath() -> String? {
        if let path = ProcessInfo.processInfo.environment["TIER4_SCREENSHOT_PATH"], !path.isEmpty {
            return path
        }

        let url = URL(fileURLWithPath: "/tmp/opencode-ios-tier4-config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["screenshot_path"] as? String
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
