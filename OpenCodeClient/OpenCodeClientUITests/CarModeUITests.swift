import XCTest
import UIKit

final class CarModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
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
    func testExperimentalCarModeToggleControlsTab() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Car Mode settings are iPhone-only")
        }
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CAR_DISABLED_FIXTURE"]
        app.launch()

        XCTAssertEqual(app.tabBars.buttons.count, 3)
        app.tabBars.buttons.element(boundBy: 2).tap()
        let toggle = app.switches["settings-car-mode-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Experimental Features"].exists)
        XCTAssertTrue(app.staticTexts["AI Usage Dashboard"].exists)

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 3).waitForExistence(timeout: 4))
        XCTAssertEqual(app.tabBars.buttons.count, 4)
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
        app.buttons["ipad-settings-button"].tap()
        XCTAssertFalse(app.switches["settings-car-mode-toggle"].exists)
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
