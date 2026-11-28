import XCTest

final class AIUsageQuotaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testQuotaEntryAndDetailFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_QUOTA_FIXTURE"]
        app.launch()

        let quota = app.buttons["chat-toolbar-quota"]
        let more = app.buttons["chat-toolbar-more"]
        if more.waitForExistence(timeout: 3) {
            XCTAssertFalse(quota.exists)
            more.tap()
            XCTAssertTrue(quota.waitForExistence(timeout: 8))
            saveScreenshot(app, name: "quota-more-menu")
        } else {
            XCTAssertTrue(quota.waitForExistence(timeout: 8))
            XCTAssertTrue(quota.label.contains("71% / 13h"))
            saveScreenshot(app, name: "quota-toolbar")
        }
        quota.tap()
        XCTAssertTrue(app.staticTexts["Usage & Limits"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["OpenAI / Codex"].waitForExistence(timeout: 8))
        let detail = app.descendants(matching: .any)["quota-detail"]
        XCTAssertTrue(detail.exists)
        let generatedAt = app.descendants(matching: .any)["quota-generated-at"]
        for _ in 0..<3 where !generatedAt.exists {
            detail.swipeUp()
        }
        XCTAssertTrue(generatedAt.waitForExistence(timeout: 8))
        XCTAssertTrue(generatedAt.label.contains("2026-07-12T09:40:00"))
        saveScreenshot(app, name: "quota-detail")
        app.buttons["quota-detail-close"].tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 8))
    }

    @MainActor
    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["QUOTA_SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url, options: .atomic)
    }
}
