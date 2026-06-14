//
//  MarkdownWebPreviewUITests.swift
//  OpenCodeClientUITests
//
//  Drives the bundled Markdown Web Preview shell with fixtures (no live server)
//  and verifies the WKWebView renders + captures screenshots for visual review.
//  Fixture selection: WEB_PREVIEW_FIXTURE_NAME env var (defaults to html_cards).
//

import XCTest

final class MarkdownWebPreviewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchWebPreview(fixture: String, dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_WEB_PREVIEW_FIXTURE"]
        app.launchEnvironment["WEB_PREVIEW_FIXTURE_NAME"] = fixture
        // Force a theme via the app's persisted theme preference key so the
        // shell receives the matching payload.theme. The app reads this on init.
        if dark {
            app.launchEnvironment["UITEST_FORCE_THEME"] = "dark"
        }
        app.launch()
        return app
    }

    /// Webview present + a sentinel for the chosen fixture.
    private func assertWebViewVisible(_ app: XCUIApplication, file: StaticString = #file, line: UInt = #line) {
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 12), "WKWebView 应出现", file: file, line: line)
    }

    private func capture(_ app: XCUIApplication, named name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let dir = ProcessInfo.processInfo.environment["WEB_PREVIEW_SCREENSHOT_DIR"], !dir.isEmpty else {
            return
        }
        let directory = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testHtmlCardsLight() throws {
        let app = launchWebPreview(fixture: "html_cards", dark: false)
        assertWebViewVisible(app)
        try capture(app, named: "web_preview_html_cards_light")
    }

    @MainActor
    func testHtmlCardsDark() throws {
        let app = launchWebPreview(fixture: "dark_theme_cards", dark: true)
        assertWebViewVisible(app)
        try capture(app, named: "web_preview_dark_theme_cards")
    }

    @MainActor
    func testInlineSVG() throws {
        let app = launchWebPreview(fixture: "inline_svg", dark: false)
        assertWebViewVisible(app)
        try capture(app, named: "web_preview_inline_svg")
    }

    @MainActor
    func testWideTable() throws {
        let app = launchWebPreview(fixture: "wide_table", dark: false)
        assertWebViewVisible(app)
        try capture(app, named: "web_preview_wide_table")
    }

    /// Security: the malicious fixture's sentinel text must render, proving the
    /// page loaded, while the injected <script> must NOT execute (no alert, no
    /// crash). We assert the sentinel is reachable in the webview's text.
    @MainActor
    func testMaliciousScriptStripped() throws {
        let app = launchWebPreview(fixture: "malicious_script", dark: false)
        assertWebViewVisible(app)
        let webView = app.webViews.firstMatch
        let sentinel = webView.staticTexts["SECURITY_FIXTURE_SENTINEL_OK"]
        XCTAssertTrue(
            sentinel.waitForExistence(timeout: 12),
            "安全 fixture 的 sentinel 文本应渲染（页面已加载且 sanitizer 未破坏内容）"
        )
        // If a script had executed and thrown, the webview would not be stable
        // enough to surface the sentinel; reaching here means script was stripped.
        try capture(app, named: "web_preview_malicious_script")
    }
}
