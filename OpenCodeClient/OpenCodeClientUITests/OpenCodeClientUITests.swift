//
//  OpenCodeClientUITests.swift
//  OpenCodeClientUITests
//
//  Created by Yan Wang on 2/12/26.
//

import XCTest

final class OpenCodeClientUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    /// 2.3 ChatTabView baseline: 验证 Chat 页加载后输入框可见（refactor 后用此测试回归）
    @MainActor
    func testChatTabShowsInputField() throws {
        let app = XCUIApplication()
        app.launch()
        let askField = app.textViews["chat-input"]
        XCTAssertTrue(askField.waitForExistence(timeout: 8), "Chat 输入框应可见")
    }

    @MainActor
    func testChatComposerLongInputRemainsScrollable() throws {
        let app = XCUIApplication()
        app.launch()

        let composer = app.textViews["chat-input"]
        XCTAssertTrue(composer.waitForExistence(timeout: 8), "Chat 输入框应可见")

        composer.tap()
        composer.typeText((1...18).map { "Line \($0)" }.joined(separator: "\n"))
        composer.swipeUp()

        let screenshot = composer.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "chat-composer-long-input"
        attachment.lifetime = .keepAlways
        add(attachment)

        let composerValue = composer.value as? String ?? ""
        XCTAssertTrue(composerValue.contains("Line 18"), "输入框应保留完整长文本内容")
    }

    @MainActor
    func testSessionListFixtureShowsArchiveSections() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_SESSION_TREE_FIXTURE")
        app.launch()

        app.buttons["chat-toolbar-session-list"].tap()

        XCTAssertTrue(app.staticTexts["Root Session"].waitForExistence(timeout: 8), "Root session 应可见")
        XCTAssertTrue(app.staticTexts["Child Session"].waitForExistence(timeout: 8), "Child session 应可见，避免回归到 root-only 列表")
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 8), "Archived section header 应可见")

        app.staticTexts["Archived"].tap()

        XCTAssertTrue(app.staticTexts["Archived Session"].waitForExistence(timeout: 8), "Archived session 应可见")
        XCTAssertTrue(app.staticTexts["Archived Child"].waitForExistence(timeout: 8), "Archived child 应可见")

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "session-archive-fixture"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAssistantSessionDeepLinkFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DEEP_LINK_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Deep Link Source"].waitForExistence(timeout: 8))
        let link = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Open target session"))
            .firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 8), "Assistant Markdown session link should be accessible")
        link.tap()

        XCTAssertTrue(app.navigationBars["Deep Link Target"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textViews["chat-input"].exists)
    }

    @MainActor
    func testColdPendingSessionDeepLinkFixture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DEEP_LINK_FIXTURE"]
        app.launchEnvironment["UITEST_INITIAL_DEEP_LINK"] = "opencode://session/ses_deep_link_target"
        app.launch()

        XCTAssertTrue(app.navigationBars["Deep Link Target"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textViews["chat-input"].exists)
    }

    @MainActor
    func testCaptureSessionArchiveFixtureScreenshot() throws {
        guard let path = tier4ScreenshotPath(), !path.isEmpty else {
            throw XCTSkip("Set TIER4_SCREENSHOT_PATH to write a deterministic archive UI screenshot")
        }

        let app = XCUIApplication()
        app.launchArguments.append("UITEST_SESSION_TREE_FIXTURE")
        app.launch()

        if app.buttons["chat-toolbar-session-list"].waitForExistence(timeout: 8) {
            app.buttons["chat-toolbar-session-list"].tap()
        }

        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 8), "Archived section header 应可见")
        app.staticTexts["Archived"].tap()
        XCTAssertTrue(app.staticTexts["Archived Session"].waitForExistence(timeout: 8), "Archived session 应可见")
        XCTAssertTrue(app.staticTexts["Archived Child"].waitForExistence(timeout: 8), "Archived child 应可见")

        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: URL(fileURLWithPath: path))
    }

    @MainActor
    func testHostProfilesListFixture() throws {
        let app = launchHostProfilesFixture()

        try openSettingsInHostProfilesFixture(app)
        app.buttons["settings-current-host"].tap()

        XCTAssertTrue(app.navigationBars["Hosts"].waitForExistence(timeout: 8), "Hosts 页面应打开")
        XCTAssertTrue(app.staticTexts["Local OpenCode"].waitForExistence(timeout: 8), "默认 Direct host 应可见")
        XCTAssertTrue(app.staticTexts["SSH Lab"].exists, "SSH tunnel host 应可见")
        XCTAssertTrue(app.staticTexts["Add Host"].exists, "Add Host 入口应可见")
        XCTAssertTrue(app.staticTexts["Copy This Device Public Key"].exists, "设备公钥复制入口应可见")
    }

    @MainActor
    func testHostProfileDetailShowsSSHTunnelFields() throws {
        let app = launchHostProfilesFixture()

        try openSettingsInHostProfilesFixture(app)
        app.buttons["settings-current-host"].tap()
        XCTAssertTrue(app.navigationBars["Hosts"].waitForExistence(timeout: 8), "Hosts 页面应打开")
        app.staticTexts["SSH Lab"].tap()

        XCTAssertTrue(app.navigationBars["SSH Lab"].waitForExistence(timeout: 8), "SSH Host 详情应打开")
        XCTAssertTrue(app.buttons["host-detail-use-this-host"].exists, "非当前 host 应显示显式切换按钮")
        XCTAssertTrue(app.buttons["host-detail-copy-config"].exists, "详情应支持复制 Host Config JSON")
    }

    @MainActor
    func testCaptureHostProfilesFixtureScreenshots() throws {
        let dir = ProcessInfo.processInfo.environment["HOST_PROFILES_SCREENSHOT_DIR"] ?? "/tmp/opencode-host-profiles-screenshots"

        let app = launchHostProfilesFixture(extraArguments: ["UITEST_HOST_IMPORT_JSON_PREFILL"])
        try openSettingsInHostProfilesFixture(app)
        try writeScreenshot(named: "host_profiles_settings_current_host", directory: dir)

        app.buttons["settings-current-host"].tap()
        XCTAssertTrue(app.navigationBars["Hosts"].waitForExistence(timeout: 8))
        try writeScreenshot(named: "host_profiles_list", directory: dir)

        app.staticTexts["SSH Lab"].tap()
        XCTAssertTrue(app.navigationBars["SSH Lab"].waitForExistence(timeout: 8))
        try writeScreenshot(named: "host_profiles_detail_ssh", directory: dir)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Hosts"].waitForExistence(timeout: 8))

        app.staticTexts["Add Host"].tap()
        XCTAssertTrue(app.navigationBars["Add Host"].waitForExistence(timeout: 8))
        try writeScreenshot(named: "host_profiles_add_import_prefill", directory: dir)

        app.buttons["host-import-config"].tap()
        XCTAssertFalse(app.textFields["host-server-url"].exists, "SSH mode should hide editable direct URL field")
        try writeScreenshot(named: "host_profiles_add_ssh_after_import", directory: dir)
    }

    @MainActor
    func testAddDirectHostProfileFlow() throws {
        let app = launchHostProfilesFixture()
        try openSettingsInHostProfilesFixture(app)
        app.buttons["settings-current-host"].tap()
        XCTAssertTrue(app.staticTexts["Add Host"].waitForExistence(timeout: 8))
        app.staticTexts["Add Host"].tap()

        XCTAssertTrue(app.navigationBars["Add Host"].waitForExistence(timeout: 8))
        app.textFields["host-name"].tap()
        app.textFields["host-name"].typeText("Tailscale Mac")
        app.textFields["host-server-url"].tap()
        app.textFields["host-server-url"].typeText("https://tailnet.example.invalid:4096")
        app.buttons["host-save"].tap()

        XCTAssertTrue(app.navigationBars["Hosts"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Tailscale Mac"].waitForExistence(timeout: 8), "新 Direct host 应保存并显示")
        XCTAssertTrue(app.staticTexts["https://tailnet.example.invalid:4096"].exists)
    }

    @MainActor
    func testImportSSHTunnelHostProfileFlow() throws {
        let app = launchHostProfilesFixture(extraArguments: ["UITEST_HOST_IMPORT_JSON_PREFILL"])
        try openSettingsInHostProfilesFixture(app)
        app.buttons["settings-current-host"].tap()
        XCTAssertTrue(app.staticTexts["Add Host"].waitForExistence(timeout: 8))
        app.staticTexts["Add Host"].tap()

        let importEditor = app.textViews["host-import-json"]
        XCTAssertTrue(importEditor.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["host-import-config"].waitForExistence(timeout: 8), "Import Host Config button should exist")
        XCTAssertTrue(app.buttons["host-import-config"].isEnabled, "Import Host Config button should be enabled after JSON paste")
        app.buttons["host-import-config"].tap()

        XCTAssertFalse(app.textFields["host-server-url"].exists, "SSH mode should hide editable direct URL field")
        app.buttons["host-save"].tap()

        XCTAssertTrue(app.navigationBars["Hosts"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Imported SSH"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["gateway.example.invalid:8006 -> :19001"].exists)
    }

    @MainActor
    func testF3TranscribingComposerFixtureScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_F3_TRANSCRIBING_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.buttons["agent-interrupt-menu"].waitForExistence(timeout: 8), "agent 中断菜单应可见但降级为 quiet status")
        XCTAssertTrue(app.otherElements["speech-waveform"].waitForExistence(timeout: 8), "语音 waveform rail 应可见")
        XCTAssertTrue(app.buttons["speech-stop-waiting"].waitForExistence(timeout: 8), "转写等待停止按钮应可见")
        XCTAssertTrue(app.buttons["chat-send"].waitForExistence(timeout: 8), "send 按钮应保留固定槽位")

        try captureF3Screenshot(named: "f3_transcribing_agent_running")
    }

    @MainActor
    func testF3RetryComposerFixtureScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_F3_RETRY_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.buttons["agent-interrupt-menu"].waitForExistence(timeout: 8), "agent 中断菜单应可见但降级为 quiet status")
        XCTAssertTrue(app.otherElements["speech-waveform"].waitForExistence(timeout: 8), "语音 waveform rail 应可见")
        XCTAssertTrue(app.buttons["speech-retry-segment"].waitForExistence(timeout: 8), "重试这段按钮应可见")
        XCTAssertTrue(app.buttons["speech-discard-audio"].waitForExistence(timeout: 8), "丢弃音频按钮应可见")
        XCTAssertTrue(app.buttons["chat-send"].waitForExistence(timeout: 8), "send 按钮应保留固定槽位")

        try captureF3Screenshot(named: "f3_retry_preserved_audio")
    }

    private func tier4ScreenshotPath() -> String? {
        if let path = ProcessInfo.processInfo.environment["TIER4_SCREENSHOT_PATH"], !path.isEmpty {
            return path
        }

        let url = URL(fileURLWithPath: "/tmp/opencode-ios-tier4-config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["screenshot_path"] as? String
    }

    private func writeScreenshot(named name: String, directory dir: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func launchHostProfilesFixture(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_HOST_PROFILES_FIXTURE"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func openSettingsInHostProfilesFixture(_ app: XCUIApplication) throws {
        if app.buttons["settings-current-host"].waitForExistence(timeout: 3) {
            return
        }
        if app.tabBars.buttons["Settings"].exists {
            app.tabBars.buttons["Settings"].tap()
        } else if app.buttons["Settings"].exists {
            app.buttons["Settings"].tap()
        }
        XCTAssertTrue(app.buttons["settings-current-host"].waitForExistence(timeout: 8), "Settings 应显示 Current Host")
    }

    @MainActor
    private func captureF3Screenshot(named name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let dir = ProcessInfo.processInfo.environment["F3_SCREENSHOT_DIR"], !dir.isEmpty else {
            return
        }

        let directory = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
