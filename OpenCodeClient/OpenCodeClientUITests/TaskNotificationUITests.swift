//
//  TaskNotificationUITests.swift
//  OpenCodeClientUITests
//

import XCTest

final class TaskNotificationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTaskNotificationCardExpandsAndOpensSubagentSession() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_TASK_NOTIFICATION_FIXTURE"]
        app.launch()

        let card = app.descendants(matching: .any)["task-notification-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 12), "task-notification-card 应渲染")

        let marker = NSPredicate(format: "label CONTAINS 'failing tests remain'")
        let markerBefore = app.staticTexts.containing(marker).count
        let openButton = app.descendants(matching: .any)["task-notification-open-session"]
        XCTAssertFalse(openButton.exists, "折叠态不应露出跳转按钮")

        card.tap()

        let revealed = app.staticTexts.containing(marker).firstMatch.waitForExistence(timeout: 6)
            || app.staticTexts.containing(marker).count > markerBefore
        XCTAssertTrue(revealed, "展开后应显示结果 markdown")
        if !openButton.waitForExistence(timeout: 2) {
            for _ in 0..<4 where !openButton.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(openButton.waitForExistence(timeout: 4), "展开后应出现跳转按钮")

        openButton.tap()

        let childTitle = app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS '(@general subagent)'")
        ).firstMatch
        XCTAssertTrue(childTitle.waitForExistence(timeout: 8), "跳转后应切到子代理会话")
    }
}
