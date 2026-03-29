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
    func testSessionListFixtureShowsChildSession() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_SESSION_TREE_FIXTURE")
        app.launch()

        app.buttons["chat-toolbar-session-list"].tap()

        XCTAssertTrue(app.staticTexts["Root Session"].waitForExistence(timeout: 8), "Root session 应可见")
        XCTAssertTrue(app.staticTexts["Child Session"].waitForExistence(timeout: 8), "Child session 应可见，避免回归到 root-only 列表")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
