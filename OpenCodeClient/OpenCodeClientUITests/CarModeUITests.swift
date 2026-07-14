import XCTest

final class CarModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCarModeFixtureShowsDrivingSurface() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CAR_MODE_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.otherElements["car-mode-root"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["car-last-response"].exists)
        XCTAssertTrue(app.buttons["car-primary-action"].exists)
        XCTAssertTrue(app.buttons["car-new-session"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "car-mode-fixture"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testStructuredCarSessionRemainsVisibleInChat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CAR_HISTORY_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Is the garage door closed?"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["The garage door is closed."].exists)
        XCTAssertTrue(app.staticTexts["structured-assistant-speech"].exists)
    }
}
