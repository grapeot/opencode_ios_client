import XCTest

final class PreviewMigrationUITests: XCTestCase {
    private let sentinel = "W06_FILE_SENTINEL"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testVisibleColumnReplacesStaleInline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FILE_SEARCH_FIXTURE"]
        app.launchEnvironment = [
            "FILE_SEARCH_FIXTURE_MODE": "results",
            "UITEST_FILE_SEARCH_OPEN_PREVIEW": "1",
            "UITEST_STALE_INLINE": "other.txt",
            "UITEST_PREVIEW_MIGRATION_HARNESS": "1"
        ]
        app.launch()
        guard waitForRoot(app) == .regular else {
            throw XCTSkip("需要 iPad regular，才能先看到中栏当前预览。")
        }
        XCTAssertTrue(app.navigationBars["notes.txt"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.navigationBars["other.txt"].exists)
        toggleLayout(app)
        XCTAssertTrue(marked(app, "compact-workspace-layout").waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["notes.txt"].waitForExistence(timeout: 8), "当前中栏 notes.txt 应盖过隐藏的 other.txt")
        XCTAssertFalse(app.navigationBars["other.txt"].exists)
        capture(app, name: "visible-column-over-stale-inline")
    }

    @MainActor
    func testFilesPushSurvivesFocusAndAutomatic() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FILE_SEARCH_FIXTURE"]
        app.launchEnvironment = [
            "FILE_SEARCH_FIXTURE_MODE": "results",
            "UITEST_LAYOUT_PREFERENCE": "focus",
            "UITEST_PREVIEW_MIGRATION_HARNESS": "1"
        ]
        app.launch()

        guard waitForRoot(app) == .compact else {
            throw XCTSkip("focus 启动应是 compact。regular 设备若仍是三栏，说明偏好没生效。")
        }
        openFilesAndPushResult(app)
        capture(app, name: "files-push-compact")

        toggleLayout(app)
        XCTAssertTrue(marked(app, "ipad-workspace-layout").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[sentinel].waitForExistence(timeout: 8), "compact Files 推入切到三栏后，中栏应仍显示同一文件")
        XCTAssertGreaterThanOrEqual(count(app, "file-content-screen"), 1)
        capture(app, name: "files-push-regular")

        toggleLayout(app)
        XCTAssertTrue(marked(app, "compact-workspace-layout").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[sentinel].waitForExistence(timeout: 8), "三栏切回单内容后，同一文件预览不应丢失")
        let inline = marked(app, "chat-inline-file-preview")
        let pushed = app.navigationBars["notes.txt"]
        XCTAssertTrue(inline.waitForExistence(timeout: 4) || pushed.waitForExistence(timeout: 4), "应回到聊天内联或 Files 推入，而不是空白")
        capture(app, name: "files-push-compact-restored")
    }

    @MainActor
    func testFileBrowserKeepsComposerUsableWhileReading() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FILE_SEARCH_FIXTURE", "-AppleLanguages", "(en)"]
        app.launchEnvironment = ["FILE_SEARCH_FIXTURE_MODE": "results", "UITEST_LAYOUT_PREFERENCE": "focus"]
        app.launch()

        let row = marked(app, "file-search-result-notes.txt")
        let folder = app.buttons["chat-toolbar-files"]
        if !row.waitForExistence(timeout: 3) || !row.isHittable {
            if folder.exists && folder.isHittable {
                folder.tap()
            } else {
                let filesTab = app.tabBars.buttons["Files"]
                XCTAssertTrue(filesTab.waitForExistence(timeout: 6))
                filesTab.tap()
            }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let preview = marked(app, "chat-inline-file-preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[sentinel].waitForExistence(timeout: 8))

        let input = marked(app, "chat-input")
        XCTAssertTrue(input.isHittable)
        input.tap()
        input.typeText("Read this file with me")
        XCTAssertTrue(preview.exists)
        capture(app, name: "file-and-active-composer")
        app.buttons["chat-send"].tap()
        let probe = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "file-search-probe", "sent:true")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        XCTAssertTrue(preview.exists)
        XCTAssertTrue(app.staticTexts[sentinel].exists)
    }

    @MainActor
    func testSidebarFileAndDraftSurviveRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FILE_SEARCH_FIXTURE", "-AppleLanguages", "(en)"]
        app.launchEnvironment = ["FILE_SEARCH_FIXTURE_MODE": "results"]
        app.launch()
        guard marked(app, "sidebar-workspace-layout").waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires a middle-width portrait window")
        }
        app.buttons["chat-toolbar-files"].tap()
        let result = marked(app, "file-search-result-notes.txt")
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(marked(app, "chat-inline-file-preview").waitForExistence(timeout: 8))
        let input = marked(app, "chat-input")
        XCTAssertTrue(input.isHittable)
        input.tap()
        input.typeText("Read this file with me")
        capture(app, name: "sidebar-file-before-rotation")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(marked(app, "ipad-workspace-layout").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[sentinel].waitForExistence(timeout: 8))
        XCTAssertFalse(marked(app, "chat-inline-file-preview").exists)
        XCTAssertEqual(input.value as? String, "Read this file with me")
        capture(app, name: "wide-file-after-rotation")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(marked(app, "chat-inline-file-preview").waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "Read this file with me")
        XCTAssertTrue(app.staticTexts[sentinel].exists)
    }

    @MainActor
    private func openFilesAndPushResult(_ app: XCUIApplication) {
        let result = marked(app, "file-search-result-notes.txt")
        if !result.waitForExistence(timeout: 2) {
            let files = app.tabBars.buttons["Files"]
            if files.waitForExistence(timeout: 2) {
                files.tap()
            } else if app.buttons["Files"].waitForExistence(timeout: 2) {
                app.buttons["Files"].tap()
            }
        }
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(result.isHittable)
        result.tap()
        XCTAssertTrue(app.staticTexts[sentinel].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["notes.txt"].waitForExistence(timeout: 4))
    }

    @MainActor
    private func toggleLayout(_ app: XCUIApplication) {
        let toggle = marked(app, "preview-migration-toggle-layout")
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
    }

    @MainActor
    private func waitForRoot(_ app: XCUIApplication) -> RootLayout {
        let regular = marked(app, "ipad-workspace-layout")
        let compact = marked(app, "compact-workspace-layout")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if regular.exists { return .regular }
            if compact.exists { return .compact }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return .missing
    }

    private enum RootLayout { case regular, compact, missing }

    @MainActor
    private func marked(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func count(_ app: XCUIApplication, _ identifier: String) -> Int {
        app.descendants(matching: .any).matching(identifier: identifier).count
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
