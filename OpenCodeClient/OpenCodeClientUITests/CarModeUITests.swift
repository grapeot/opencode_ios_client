import XCTest
import UIKit

final class CarModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCarModeFixtureShowsDrivingSurface() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Car Mode is iPhone-only")
        }
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
    func testCarModeIsHiddenOnIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad-only coverage")
        }
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CAR_MODE_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.otherElements["ipad-workspace-layout"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["car-mode-root"].exists)
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
