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
        // Let the settings screen settle at the top before scrolling.
        XCTAssertTrue(app.buttons["settings-current-host"].waitForExistence(timeout: 5))
        let toggle = app.switches["settings-car-mode-toggle"]
        // The toggle sits ~42% of the scrollable settings content below the
        // top. Slow press-then-drag steps (minimal fling inertia) scroll it
        // into view; stop as soon as it materializes — overshooting the 58pt
        // cell un-materializes it again.
        var scrolled = 0
        var found = toggle.waitForExistence(timeout: 1)
        while !found && scrolled < 8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(
                    forDuration: 0.1,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                )
            found = toggle.waitForExistence(timeout: 1.5)
            scrolled += 1
        }
        XCTAssertTrue(found && toggle.exists, "settings-car-mode-toggle 应滚动进视口")
        XCTAssertTrue(app.staticTexts["Experimental Features"].exists)
        XCTAssertTrue(app.staticTexts["AI Usage Dashboard"].exists)

        toggle.tap()
        // Enabling car mode adds the 4th tab; the TabView re-layout scrolls the
        // settings list back toward the top, so the switch cell un-materializes
        // right after the tap. The 4th tab itself is gated on carModeEnabled,
        // so it is the authoritative assertion of the toggle state.
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

    @MainActor
    func testHealthCapabilityShowsLocalPermissionSheet() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Client capability fixture is iPhone-only")
        }
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_CLIENT_CAPABILITY_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.buttons["capability-allow-once"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["capability-allow-always"].exists)
        XCTAssertTrue(app.buttons["capability-cancel"].exists)
        XCTAssertTrue(app.staticTexts["Sync last night's sleep data before analysis"].exists)
        let allowOnce = app.buttons["capability-allow-once"].frame
        let allowAlways = app.buttons["capability-allow-always"].frame
        let cancel = app.buttons["capability-cancel"].frame
        XCTAssertEqual(allowOnce.midY, allowAlways.midY, accuracy: 4)
        XCTAssertEqual(allowAlways.midY, cancel.midY, accuracy: 4)
        XCTAssertEqual(allowOnce.width, allowAlways.width, accuracy: 4)
        XCTAssertEqual(allowAlways.width, cancel.width, accuracy: 4)
        XCTAssertLessThan(allowOnce.minX, allowAlways.minX)
        XCTAssertLessThan(allowAlways.minX, cancel.minX)

        app.buttons["capability-cancel"].tap()
        XCTAssertFalse(app.buttons["capability-allow-once"].waitForExistence(timeout: 1))
    }
}
