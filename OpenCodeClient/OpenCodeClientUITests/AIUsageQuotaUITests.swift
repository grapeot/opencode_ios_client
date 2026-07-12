import XCTest

final class AIUsageQuotaUITests: XCTestCase {
    @MainActor
    func testQuotaBadgeAndDetailFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_QUOTA_FIXTURE"]
        app.launch()

        let badge = app.buttons["chat-toolbar-quota"]
        XCTAssertTrue(badge.waitForExistence(timeout: 8))
        XCTAssertTrue(badge.label.contains("71% @ 5h"))
        saveScreenshot(app, name: "quota-toolbar")

        badge.tap()
        XCTAssertTrue(app.staticTexts["Usage & Limits"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["OpenAI / Codex"].waitForExistence(timeout: 8))
        saveScreenshot(app, name: "quota-detail")
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
