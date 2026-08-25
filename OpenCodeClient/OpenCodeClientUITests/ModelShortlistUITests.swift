import XCTest

final class ModelShortlistUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testSettingsShortlistAddFromCatalogAndPickerShowsOnlyShortlist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MODEL_SHORTLIST_FIXTURE"]
        app.launch()

        openSettings(in: app)
        let modelsRow = app.descendants(matching: .any)["settings-model-shortlist"]
        XCTAssertTrue(modelsRow.waitForExistence(timeout: 8))
        modelsRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["model-shortlist-row-zai-coding-plan-glm-5.3"].waitForExistence(timeout: 6))
        app.buttons["model-shortlist-add"].tap()

        let flash = app.descendants(matching: .any)["model-catalog-row-google-gemini-3.5-flash"]
        let lite = app.descendants(matching: .any)["model-catalog-row-google-gemini-3.5-flash-lite"]
        XCTAssertTrue(flash.waitForExistence(timeout: 6))
        XCTAssertTrue(lite.exists)
        XCTAssertFalse(app.descendants(matching: .any)["model-catalog-row-zai-coding-plan-glm-5.3"].exists)

        flash.tap()
        app.buttons["model-catalog-add-selected"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["model-shortlist-row-google-gemini-3.5-flash"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["model-shortlist-row-zai-coding-plan-glm-5.3"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        openChat(in: app)
        let chip = app.buttons["chat-toolbar-model"]
        XCTAssertTrue(chip.waitForExistence(timeout: 6))
        chip.tap()

        XCTAssertTrue(app.buttons["model-picker-row-zai-coding-plan-glm-5.3"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["model-picker-row-google-gemini-3.5-flash"].exists)
        XCTAssertFalse(app.buttons["model-picker-row-google-gemini-3.5-flash-lite"].exists)
    }

    @MainActor
    func testEmptyPickerJumpsToSettingsModels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MODEL_SHORTLIST_EMPTY_FIXTURE"]
        app.launch()

        let chip = app.buttons["chat-toolbar-model"]
        XCTAssertTrue(chip.waitForExistence(timeout: 8))
        chip.tap()

        let empty = app.descendants(matching: .any)["configure-empty-shortlist"]
        XCTAssertTrue(empty.waitForExistence(timeout: 6), "empty shortlist should show the Settings jump row")
        empty.tap()
        XCTAssertTrue(empty.waitForNonExistence(timeout: 4), "model sheet should dismiss after jump")

        let modelsRow = app.descendants(matching: .any)["settings-model-shortlist"]
        XCTAssertTrue(modelsRow.waitForExistence(timeout: 8), "Settings → Models row should be visible after jump")
    }

    private func openSettings(in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        tabBar.buttons.element(boundBy: tabBar.buttons.count - 1).tap()
    }

    private func openChat(in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 6))
        tabBar.buttons.element(boundBy: 0).tap()
    }
}
