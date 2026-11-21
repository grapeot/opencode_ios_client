import XCTest
import UIKit

final class FocusVoiceInputUITests: XCTestCase {
    private let pasteSentinel = "FOCUS_VOICE_PASTE_SENTINEL"
    private let previewSentinel = "W06_FILE_SENTINEL"
    private let rotationDraft = "vfrot9"
    private var launchedApp: XCUIApplication?
    private var didAttachFailureDiagnostics = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        didAttachFailureDiagnostics = false
        launchedApp = nil
        XCUIDevice.shared.orientation = .portrait
    }

    override func record(_ issue: XCTIssue) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                attachFailureDiagnosticsIfNeeded()
            }
        }
        super.record(issue)
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testResumeWithCaretButNoSoftwareKeyboard() {
        exerciseResume(focus: "caret")
    }

    @MainActor
    func testResumeWithSoftwareKeyboard() {
        exerciseResume(focus: "keyboard")
    }

    @MainActor
    func testResumeWithoutInputFocus() {
        exerciseResume(focus: "none")
    }

    @MainActor
    func testCaretOnlyStaysResponsiveWithoutBackgrounding() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE"]
        app.launchEnvironment["UITEST_COMPOSER_SPEECH_CONFIGURED"] = "1"
        app.launchEnvironment["UITEST_COMPOSER_VOICE_FIRST"] = "1"
        app.launch()
        let input = app.descendants(matching: .any)["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        input.tap()
        let probe = waitForCaretProbe(app, contains: "first=1")
        XCTAssertTrue(probe.contains("first=1"), probe)
        XCTAssertTrue(probe.contains("keyboard=suppressed"))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        capture(app, name: "caret-only")
        app.buttons["chat-keyboard"].tap()
        input.typeText("focuscheck9")
        XCTAssertTrue((input.value as? String)?.contains("focuscheck9") == true)
    }

    @MainActor
    private func exerciseResume(focus: String) {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE"]
        app.launchEnvironment["UITEST_COMPOSER_SPEECH_CONFIGURED"] = "1"
        app.launchEnvironment["UITEST_COMPOSER_VOICE_FIRST"] = "1"
        app.launch()
        let input = app.descendants(matching: .any)["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        if focus == "caret" {
            input.tap()
            let probe = waitForCaretProbe(app, contains: "first=1")
            XCTAssertTrue(probe.contains("first=1") && probe.contains("keyboard=suppressed"), probe)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
        } else if focus == "keyboard" {
            app.buttons["chat-keyboard"].tap()
            assertSoftwareKeyboardVisible(app)
            let probe = waitForCaretProbe(app, contains: "first=1")
            XCTAssertTrue(probe.contains("first=1") && probe.contains("keyboard=system"), probe)
        } else {
            let probe = waitForCaretProbe(app, contains: "first=0")
            XCTAssertTrue(probe.contains("first=0") && probe.contains("keyboard=suppressed"), probe)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
        }
        capture(app, name: "resume-\(focus)-before")
        print("RESUME_QA \(focus) opening Settings")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while app.state == .runningForeground && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(app.state == .runningBackground || app.state == .runningBackgroundSuspended, "expected same app to background: \(app.state.rawValue)")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertTrue(app.state == .runningBackground || app.state == .runningBackgroundSuspended, "app exited in background: \(app.state.rawValue)")
        print("RESUME_QA \(focus) activating")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        if focus != "keyboard" { XCTAssertFalse(app.keyboards.firstMatch.exists) }
        capture(app, name: "resume-\(focus)-before-interaction")
        if !app.buttons["chat-keyboard-done"].exists { app.buttons["chat-keyboard"].tap() }
        XCTAssertTrue(app.buttons["chat-keyboard-done"].waitForExistence(timeout: 5))
        input.typeText("resumecheck9")
        XCTAssertTrue((input.value as? String)?.contains("resumecheck9") == true)
        capture(app, name: "resume-\(focus)-after")
        print("RESUME_QA \(focus) typed successfully")
    }

    @MainActor
    func testVoiceFirstDraftTapDoesNotPresentKeyboard() {
        let app = launchSessionTree()
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8), "chat-input 应在离线 session tree fixture 中可见")
        XCTAssertFalse(marked(app, "chat-keyboard").exists)
        XCTAssertFalse(marked(app, "chat-paste").exists)
        XCTAssertFalse(marked(app, "chat-voice-first-actions").exists)

        enableVoiceFirst(app)
        XCTAssertTrue(marked(app, "chat-voice-first-actions").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat-keyboard"].exists)
        capture(app, name: "paste-button-resting")
        XCTAssertFalse(app.buttons["chat-keyboard-done"].exists)
        XCTAssertTrue(input.isHittable, "草稿区应可点，否则点按不弹键盘没有被测到")

        input.tap()
        assertSoftwareKeyboardHidden(app)
        let probe = waitForCaretProbe(app, contains: "first=1")
        XCTAssertTrue(probe.contains("keyboard=suppressed"), "点按应聚焦但不弹软键盘，probe=\(probe)")
        XCTAssertTrue(probe.contains("editable=1"), probe)
        XCTAssertFalse(probe.contains("caret=0x0"), "聚焦后应有 caret，probe=\(probe)")
        XCTAssertTrue(app.buttons["chat-keyboard"].exists)
        XCTAssertFalse(app.buttons["chat-keyboard-done"].exists)
    }

    @MainActor
    func testVoiceFirstExplicitKeyboardEditsThenDismisses() {
        let app = launchSessionTree()
        enableVoiceFirst(app)
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        let openKeyboard = app.buttons["chat-keyboard"]
        XCTAssertTrue(openKeyboard.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(openKeyboard.frame.width, 44)
        XCTAssertGreaterThanOrEqual(openKeyboard.frame.height, 44)

        openKeyboard.tap()
        XCTAssertTrue(app.buttons["chat-keyboard-done"].waitForExistence(timeout: 5), "显式键盘按钮应进入编辑态")
        assertSoftwareKeyboardVisible(app)
        let editing = waitForCaretProbe(app, contains: "keyboard=system")
        XCTAssertTrue(editing.contains("first=1"), editing)
        input.typeText("vfkeep9")
        XCTAssertTrue((input.value as? String)?.contains("vfkeep9") == true, "显式编辑应写入草稿")

        app.buttons["chat-keyboard-done"].tap()
        XCTAssertTrue(app.buttons["chat-keyboard"].waitForExistence(timeout: 5), "收起后应回到非编辑键盘按钮")
        XCTAssertFalse(app.buttons["chat-keyboard-done"].exists)
        assertSoftwareKeyboardDismissed(app)
        XCTAssertTrue((input.value as? String)?.contains("vfkeep9") == true, "收起键盘不应清草稿")
        input.tap()
        let refocused = waitForCaretProbe(app, contains: "first=1")
        XCTAssertTrue(refocused.contains("keyboard=suppressed"), refocused)
        assertSoftwareKeyboardHidden(app)
    }

    @MainActor
    func testVoiceFirstSessionSwitchEndsEditing() {
        let app = launchSessionTree()
        enableVoiceFirst(app)
        XCTAssertTrue(app.navigationBars["Root Session"].waitForExistence(timeout: 8))
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        app.buttons["chat-keyboard"].tap()
        XCTAssertTrue(app.buttons["chat-keyboard-done"].waitForExistence(timeout: 5))
        assertSoftwareKeyboardVisible(app)
        input.typeText("vfsw9")
        XCTAssertTrue((input.value as? String)?.contains("vfsw9") == true, "切换前应已真正写入草稿")

        selectSession(app, id: "child-session")
        XCTAssertTrue(app.navigationBars["Child Session"].waitForExistence(timeout: 8), "应切到 child-session，而不是只收起键盘")
        XCTAssertTrue(app.buttons["chat-keyboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat-keyboard-done"].exists)
        assertSoftwareKeyboardDismissed(app)
    }

    @MainActor
    func testVoiceFirstPasteControlAppendsDraftWithoutKeyboardOrSend() {
        let app = launchSessionTree(pasteSeed: true)
        enableVoiceFirst(app)
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        let paste = marked(app, "chat-paste")
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "chat-paste 应是真实 PasteControl 的 accessibility ID")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat-paste").count, 1)
        XCTAssertGreaterThanOrEqual(paste.frame.width, 44)
        XCTAssertGreaterThanOrEqual(paste.frame.height, 44)
        XCTAssertTrue(
            paste.isEnabled,
            "chat-paste 未启用。fixture 应已把系统剪贴板写成 sentinel，且不要用测试进程伪造点击"
        )
        XCTAssertTrue(paste.isHittable)
        if failIfPastePrompt(app, name: "paste-blocked-before-tap") {
            return
        }

        paste.tap()
        var value = waitForPasteCount(app, input: input, count: 1, timeout: 8)
        if failIfPastePrompt(app, name: "paste-permission-alert") {
            return
        }
        XCTAssertGreaterThanOrEqual(pasteCount(value), 1, "第一次真实粘贴应写入空草稿，当前值=\(value)")
        assertPasteDidNotEditOrSend(app, input: input, value: value)

        paste.tap()
        value = waitForPasteCount(app, input: input, count: 2, timeout: 8)
        if failIfPastePrompt(app, name: "paste-permission-alert") {
            return
        }
        XCTAssertGreaterThanOrEqual(pasteCount(value), 2, "第二次粘贴应换行追加，不应覆盖。当前值=\(value)")
        assertPasteInsertedNewline(value)
        assertPasteDidNotEditOrSend(app, input: input, value: value)
    }

    @MainActor
    func testVoiceFirstCaretTapFocusesWithoutKeyboardAndPasteUsesSelection() {
        let app = launchSessionTree(pasteSeed: true)
        enableVoiceFirst(app)
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        app.buttons["chat-keyboard"].tap()
        assertSoftwareKeyboardVisible(app)
        input.typeText("ab")
        app.buttons["chat-keyboard-done"].tap()
        assertSoftwareKeyboardDismissed(app)
        XCTAssertEqual(input.value as? String, "ab")

        input.tap()
        let probe = waitForCaretProbe(app, contains: "first=1")
        XCTAssertTrue(probe.contains("keyboard=suppressed"), probe)
        assertSoftwareKeyboardHidden(app)
        capture(app, name: "caret-focused-no-keyboard")
        guard let range = probeRange(probe) else {
            XCTFail("probe 没有选区：\(probe)")
            return
        }
        let paste = marked(app, "chat-paste")
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        XCTAssertTrue(paste.isEnabled)
        paste.tap()
        let value = waitForPasteCount(app, input: input, count: 1, timeout: 8)
        if failIfPastePrompt(app, name: "caret-paste-alert") { return }
        let expected = inserted(draft: "ab", addition: pasteSentinel, range: range)
        XCTAssertEqual(value, expected, "聚焦后粘贴应落在 caret，而不是未聚焦的换行追加。probe=\(probe)")
        XCTAssertNotEqual(value, "ab\n\(pasteSentinel)")
        assertSoftwareKeyboardHidden(app)
        XCTAssertEqual(count(app, prefix: "user-message-"), 0)
        capture(app, name: "caret-paste-at-selection")
    }

    @MainActor
    func testVoiceFirstSurvivesPortraitLandscapeRotation() {
        let app = launchSessionTree()
        rotate(app, to: .portrait)
        enableVoiceFirst(app)
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        app.buttons["chat-keyboard"].tap()
        XCTAssertTrue(app.buttons["chat-keyboard-done"].waitForExistence(timeout: 5))
        assertSoftwareKeyboardVisible(app)
        input.typeText(rotationDraft)
        XCTAssertTrue((input.value as? String)?.contains(rotationDraft) == true)
        app.buttons["chat-keyboard-done"].tap()
        XCTAssertTrue(app.buttons["chat-keyboard"].waitForExistence(timeout: 5))
        assertSoftwareKeyboardDismissed(app)

        let surface = surfaceTag(app)
        assertVoiceFirstResting(app, input: input)
        capture(app, name: "voice-first-rotation-portrait-\(surface)")

        rotate(app, to: .landscapeLeft)
        assertVoiceFirstResting(app, input: input)
        capture(app, name: "voice-first-rotation-landscape-\(surface)")

        rotate(app, to: .portrait)
        assertVoiceFirstResting(app, input: input)
        capture(app, name: "voice-first-rotation-portrait-restored-\(surface)")
    }

    @MainActor
    func testIPadAutomaticFocusSwitchRetainsPreview() throws {
        let app = XCUIApplication()
        launchedApp = app
        app.launchArguments = ["UITEST_FILE_SEARCH_FIXTURE"]
        app.launchEnvironment = [
            "FILE_SEARCH_FIXTURE_MODE": "results",
            "UITEST_FILE_SEARCH_OPEN_PREVIEW": "1"
        ]
        app.launch()

        guard waitForRootLayout(app) == .regular else {
            throw XCTSkip("根布局不是 ipad-workspace-layout。phone 或 Duo 外屏跳过，不把 compact 记成内屏通过。")
        }
        XCTAssertFalse(marked(app, "compact-workspace-layout").exists)
        XCTAssertTrue(app.staticTexts[previewSentinel].waitForExistence(timeout: 8), "列预览应显示 fixture 正文")
        XCTAssertEqual(count(app, "file-content-screen"), 1)
        XCTAssertEqual(count(app, "chat-inline-file-preview"), 0)
        XCTAssertTrue(app.textViews["chat-input"].exists)

        selectLayoutSegment(app, index: 1)
        assertFocusPreviewRetained(app, note: "portrait")
        capture(app, name: "focus-preview-portrait")

        rotate(app, to: .landscapeLeft)
        assertFocusPreviewRetained(app, note: "landscape")
        capture(app, name: "focus-preview-landscape")

        rotate(app, to: .portrait)
        assertFocusPreviewRetained(app, note: "portrait-restored")
        capture(app, name: "focus-preview-portrait-restored")

        selectLayoutSegment(app, index: 0)
        XCTAssertTrue(marked(app, "ipad-workspace-layout").waitForExistence(timeout: 8))
        XCTAssertFalse(marked(app, "compact-workspace-layout").exists)
        let inline = marked(app, "chat-inline-file-preview")
        if inline.exists {
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: inline)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "回到 Auto 后内联预览应迁回中栏")
        }
        XCTAssertEqual(count(app, "chat-inline-file-preview"), 0)
        XCTAssertEqual(count(app, "file-content-screen"), 1)
        XCTAssertTrue(app.staticTexts[previewSentinel].waitForExistence(timeout: 8), "回到 Auto 后正文应仍在中栏")
    }

    @MainActor
    private func launchSessionTree(pasteSeed: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        launchedApp = app
        app.launchArguments = ["UITEST_SESSION_TREE_FIXTURE"]
        app.launchEnvironment["UITEST_COMPOSER_SPEECH_CONFIGURED"] = "1"
        if pasteSeed {
            app.launchEnvironment["UITEST_PASTE_SENTINEL"] = pasteSentinel
        }
        app.launch()
        return app
    }

    @MainActor
    private func enableVoiceFirst(_ app: XCUIApplication) {
        openSettings(app)
        let row = revealVoiceFirstSwitch(app)
        if !row.exists || !row.isHittable {
            failVoiceFirst(app, row, "settings-voice-first Switch 不可点")
            return
        }
        let inner = row.descendants(matching: .switch).firstMatch
        if !switchIsOn(row) && !(inner.exists && switchIsOn(inner)) {
            if inner.exists {
                inner.tap()
            } else {
                row.tap()
            }
        }
        if !waitUntilVoiceFirstOn(row, inner) {
            let innerDetail = inner.exists ? "innerValue=\(String(describing: inner.value))" : "inner=missing"
            failVoiceFirst(app, row, "点内部开关后 row/inner value 未变为 1。\(innerDetail)")
            return
        }
        closeSettings(app)
        let keyboard = app.buttons["chat-keyboard"]
        if !keyboard.waitForExistence(timeout: 8) {
            let afterChat = "afterChat keyboard=\(keyboard.exists) actions=\(marked(app, "chat-voice-first-actions").exists) paste=\(marked(app, "chat-paste").exists) input=\(app.textViews["chat-input"].exists)"
            print("VOICE_FIRST_DIAG \(afterChat)")
            openSettings(app)
            let again = revealVoiceFirstSwitch(app)
            let againOn = again.exists && (switchIsOn(again) || {
                let nested = again.descendants(matching: .switch).firstMatch
                return nested.exists && switchIsOn(nested)
            }())
            print("VOICE_FIRST_DIAG settingsRecheck exists=\(again.exists) on=\(againOn)")
            failVoiceFirst(app, again, "主界面没有 chat-keyboard，语音优先未生效。\(afterChat) settingsRecheckOn=\(againOn)")
            return
        }
        XCTAssertTrue(app.textViews["chat-input"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func waitUntilVoiceFirstOn(_ row: XCUIElement, _ inner: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if switchIsOn(row) || (inner.exists && switchIsOn(inner)) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return switchIsOn(row) || (inner.exists && switchIsOn(inner))
    }

    @MainActor
    private func revealVoiceFirstSwitch(_ app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["settings-voice-first"]
        if toggle.waitForExistence(timeout: 1), toggle.isHittable {
            return toggle
        }
        if marked(app, "settings-current-host").exists {
            let scroller = settingsScroller(app)
            for _ in 0..<8 {
                scroller.swipeUp()
                if toggle.exists, toggle.isHittable {
                    return toggle
                }
            }
        }
        return toggle
    }

    @MainActor
    private func failVoiceFirst(_ app: XCUIApplication, _ toggle: XCUIElement, _ message: String) {
        let detail: String
        if toggle.exists {
            detail = "type=\(toggle.elementType.rawValue) identifier=\(toggle.identifier) value=\(String(describing: toggle.value)) exists=true hittable=\(toggle.isHittable) switchCount=\(app.switches.matching(identifier: "settings-voice-first").count)"
        } else {
            detail = "toggle=missing exists=false switchCount=\(app.switches.count)"
        }
        print("VOICE_FIRST_TOGGLE \(detail)")
        print(app.debugDescription)
        didAttachFailureDiagnostics = true
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "voice-first-toggle-debugDescription"
        tree.lifetime = .keepAlways
        add(tree)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "voice-first-toggle-screenshot"
        shot.lifetime = .keepAlways
        add(shot)
        XCTFail("\(message)。\(detail)")
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let ipadSettings = app.buttons["ipad-settings-button"]
        if ipadSettings.exists {
            XCTAssertTrue(ipadSettings.isHittable, "ipad-settings-button 不可点。\(navigationSummary(app))")
            ipadSettings.tap()
            return
        }
        guard let settings = waitForChrome(app, label: "Settings") else {
            XCTFail("找不到设置入口。\(navigationSummary(app))")
            return
        }
        XCTAssertTrue(settings.isHittable, "设置入口不可点。\(navigationSummary(app))")
        settings.tap()
    }

    @MainActor
    private func closeSettings(_ app: XCUIApplication) {
        if !alreadyOnMain(app) {
            let done = app.navigationBars.buttons["Done"]
            if done.exists, done.isHittable {
                done.tap()
            } else if let chat = waitForChrome(app, label: "Chat") {
                XCTAssertTrue(chat.isHittable, "Chat 入口不可点。\(navigationSummary(app))")
                chat.tap()
            } else {
                XCTFail("找不到离开设置的入口。\(navigationSummary(app))")
                return
            }
        }
        assertReturnedToMain(app)
    }

    @MainActor
    private func selectLayoutSegment(_ app: XCUIApplication, index: Int) {
        openSettings(app)
        let picker = reveal("settings-layout-preference", in: app)
        let buttons = picker.descendants(matching: .button)
        XCTAssertEqual(buttons.count, 2, "settings-layout-preference 应只有两段。不回退到菜单文本")
        let segment = buttons.element(boundBy: index)
        XCTAssertTrue(segment.isHittable)
        segment.tap()
        closeSettings(app)
    }

    @MainActor
    private func waitForChrome(_ app: XCUIApplication, label: String) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let found = chromeControl(app, label: label) {
                return found
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return chromeControl(app, label: label)
    }

    @MainActor
    private func chromeControl(_ app: XCUIApplication, label: String) -> XCUIElement? {
        let tab = app.tabBars.buttons[label]
        if tab.exists {
            return tab
        }
        let button = app.buttons[label]
        if button.exists, button.isHittable {
            return button
        }
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        let matches = app.descendants(matching: .any).matching(predicate)
        var fallback: XCUIElement?
        for index in 0..<min(matches.count, 8) {
            let element = matches.element(boundBy: index)
            guard element.exists else { continue }
            if element.elementType == .button, element.isHittable {
                return element
            }
            if fallback == nil, element.isHittable {
                fallback = element
            }
        }
        if button.exists {
            return button
        }
        return fallback
    }

    @MainActor
    private func alreadyOnMain(_ app: XCUIApplication) -> Bool {
        let input = app.textViews["chat-input"]
        let settingsOpen = marked(app, "settings-layout-preference").exists && marked(app, "settings-voice-first").exists
        return input.exists && input.isHittable && !settingsOpen
    }

    @MainActor
    private func assertReturnedToMain(_ app: XCUIApplication) {
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8), "关闭设置后应回到主界面。\(navigationSummary(app))")
        XCTAssertFalse(
            marked(app, "settings-layout-preference").exists && !input.isHittable,
            "分段切换后设置页仍挡住主界面。\(navigationSummary(app))"
        )
    }

    @MainActor
    private func navigationSummary(_ app: XCUIApplication) -> String {
        let tabs = app.tabBars.buttons.allElementsBoundByIndex.map { "\($0.label)#\($0.identifier)" }
        let chrome = app.buttons.allElementsBoundByIndex.filter {
            let label = $0.label
            return label == "Settings" || label == "Chat" || label == "Files" || label == "Done" || $0.identifier == "ipad-settings-button"
        }.map { "\($0.label)#\($0.identifier) hittable=\($0.isHittable)" }
        return "tabBars=[\(tabs.joined(separator: "; "))] chrome=[\(chrome.joined(separator: "; "))]"
    }

    @MainActor
    private func attachFailureDiagnosticsIfNeeded() {
        guard !didAttachFailureDiagnostics, let app = launchedApp else { return }
        didAttachFailureDiagnostics = true
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "failure-app-debugDescription"
        tree.lifetime = .keepAlways
        add(tree)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "failure-screenshot"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func selectSession(_ app: XCUIApplication, id: String) {
        let row = marked(app, "session-row-\(id)")
        if !row.exists {
            let list = app.buttons["chat-toolbar-session-list"]
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            XCTAssertTrue(list.isHittable, "chat-toolbar-session-list 不可点")
            list.tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.isHittable, "session-row-\(id) 不可点，不回退到标题文本")
        row.tap()
    }

    @MainActor
    private func reveal(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let target = marked(app, identifier)
        if target.waitForExistence(timeout: 1), target.isHittable {
            return target
        }
        let scroller = settingsScroller(app)
        for _ in 0..<8 {
            scroller.swipeUp()
            if target.exists, target.isHittable {
                return target
            }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 2), "\(identifier) 未出现")
        return target
    }

    @MainActor
    private func settingsScroller(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(marked(app, "settings-current-host").waitForExistence(timeout: 8))
        for container in app.collectionViews.allElementsBoundByIndex where container.descendants(matching: .any)["settings-current-host"].exists {
            return container
        }
        for container in app.tables.allElementsBoundByIndex where container.descendants(matching: .any)["settings-current-host"].exists {
            return container
        }
        XCTFail("设置列表滚动容器不可用，不能靠坐标去找开关")
        return marked(app, "settings-current-host")
    }

    @MainActor
    private func assertSoftwareKeyboardHidden(_ app: XCUIApplication, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(
            app.keyboards.firstMatch.waitForExistence(timeout: 2),
            "软键盘不应出现",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertSoftwareKeyboardVisible(_ app: XCUIApplication, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "显式编辑应唤起软键盘。若开启了 Connect Hardware Keyboard，先关掉再跑",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertSoftwareKeyboardDismissed(_ app: XCUIApplication, file: StaticString = #file, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "软键盘应收起", file: file, line: line)
    }

    @MainActor
    private func assertVoiceFirstResting(_ app: XCUIApplication, input: XCUIElement) {
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        let value = input.value as? String ?? ""
        XCTAssertTrue(value.contains(rotationDraft), "旋转后草稿应保留，当前值=\(value)")
        assertSoftwareKeyboardHidden(app)
        XCTAssertTrue(app.buttons["chat-keyboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat-keyboard-done"].exists)
        assertHittable(app, "speech-transport")
        assertHittable(app, "chat-send")
        assertHittable(app, "chat-keyboard")
        assertHittable(app, "chat-paste")
    }

    @MainActor
    private func assertHittable(_ app: XCUIApplication, _ identifier: String) {
        let element = marked(app, identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(identifier) 应存在")
        XCTAssertTrue(element.isHittable, "\(identifier) 应可见可点")
    }

    @MainActor
    private func assertFocusPreviewRetained(_ app: XCUIApplication, note: String) {
        XCTAssertTrue(marked(app, "compact-workspace-layout").waitForExistence(timeout: 8), "\(note)：应保持 Focus 根布局")
        XCTAssertFalse(marked(app, "ipad-workspace-layout").exists, "\(note)：旋转不应退出 Focus")
        XCTAssertTrue(marked(app, "chat-inline-file-preview").waitForExistence(timeout: 8), "\(note)：内联预览应保留")
        XCTAssertEqual(substantialCount(app, "chat-inline-file-preview"), 1, "\(note)：应只有一块实质内联预览")
        XCTAssertTrue(app.navigationBars["notes.txt"].waitForExistence(timeout: 8), "\(note)：预览应仍是 notes.txt")
        XCTAssertTrue(app.staticTexts[previewSentinel].waitForExistence(timeout: 8), "\(note)：正文应保留")
        let input = app.textViews["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isHittable, "\(note)：输入区应仍可点")
    }

    @MainActor
    private func assertPasteDidNotEditOrSend(_ app: XCUIApplication, input: XCUIElement, value: String) {
        if failIfPastePrompt(app, name: "paste-permission-alert") {
            return
        }
        assertSoftwareKeyboardHidden(app)
        XCTAssertTrue(app.buttons["chat-keyboard"].exists)
        XCTAssertFalse(app.buttons["chat-keyboard-done"].exists)
        XCTAssertEqual(count(app, prefix: "user-message-"), 0, "粘贴不应发送")
        XCTAssertTrue(value.contains(pasteSentinel), "发送会清空草稿；粘贴后草稿应仍含 sentinel")
    }

    private func assertPasteInsertedNewline(_ value: String, file: StaticString = #file, line: UInt = #line) {
        guard let first = value.range(of: pasteSentinel),
              let second = value.range(of: pasteSentinel, range: first.upperBound..<value.endIndex) else {
            XCTFail("草稿里没有两次 sentinel：\(value)", file: file, line: line)
            return
        }
        XCTAssertTrue(value[first.upperBound..<second.lowerBound].contains("\n"), "两次粘贴之间应有换行：\(value)", file: file, line: line)
    }

    @MainActor
    private func waitForPasteCount(
        _ app: XCUIApplication,
        input: XCUIElement,
        count expected: Int,
        timeout: TimeInterval
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = input.value as? String ?? ""
        while Date() < deadline {
            if blockingPastePrompt(app) != nil {
                return latest
            }
            latest = input.value as? String ?? ""
            if pasteCount(latest) >= expected {
                return latest
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return input.value as? String ?? ""
    }

    @MainActor
    @discardableResult
    private func failIfPastePrompt(_ app: XCUIApplication, name: String) -> Bool {
        guard let prompt = blockingPastePrompt(app) else { return false }
        capture(app, name: name)
        XCTFail("粘贴路径出现授权弹窗，未点允许或拒绝。\(prompt)")
        return true
    }

    @MainActor
    private func blockingPastePrompt(_ app: XCUIApplication) -> String? {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for alert in [app.alerts.firstMatch, springboard.alerts.firstMatch] where alert.exists {
            let buttons = alert.buttons.allElementsBoundByIndex.map(\.label).joined(separator: ",")
            return "alert:\(alert.label) buttons:\(buttons)"
        }
        for label in ["Allow Paste", "Don't Allow Paste", "允许粘贴", "不允许粘贴"] {
            if app.buttons[label].exists {
                return "app-button:\(label)"
            }
            if springboard.buttons[label].exists {
                return "springboard-button:\(label)"
            }
        }
        return nil
    }

    private func pasteCount(_ value: String) -> Int {
        value.components(separatedBy: pasteSentinel).count - 1
    }

    @MainActor
    private func waitForCaretProbe(_ app: XCUIApplication, contains needle: String, timeout: TimeInterval = 5) -> String {
        let probe = marked(app, "chat-input-caret-probe")
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "caret probe 应只在 session tree fixture 出现")
        let deadline = Date().addingTimeInterval(timeout)
        var latest = probe.value as? String ?? ""
        while Date() < deadline {
            latest = probe.value as? String ?? ""
            if latest.contains(needle) { return latest }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return latest
    }

    private func probeRange(_ probe: String) -> NSRange? {
        guard let match = probe.range(of: "range=") else { return nil }
        let tail = probe[match.upperBound...]
        let pair = tail.prefix { $0 != ";" }
        let parts = pair.split(separator: ",")
        guard parts.count == 2, let location = Int(parts[0]), let length = Int(parts[1]) else { return nil }
        return NSRange(location: location, length: length)
    }

    private func inserted(draft: String, addition: String, range: NSRange) -> String {
        let ns = draft as NSString
        let location = min(max(0, range.location), ns.length)
        let length = min(max(0, range.length), ns.length - location)
        return ns.replacingCharacters(in: NSRange(location: location, length: length), with: addition)
    }

    private func switchIsOn(_ toggle: XCUIElement) -> Bool {
        if let number = toggle.value as? NSNumber {
            return number.intValue == 1
        }
        return (toggle.value as? String) == "1"
    }

    @MainActor
    private func marked(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func count(_ app: XCUIApplication, _ identifier: String) -> Int {
        app.descendants(matching: .any).matching(identifier: identifier).count
    }

    @MainActor
    private func substantialCount(_ app: XCUIApplication, _ identifier: String) -> Int {
        app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex.filter {
            $0.frame.width > 100 && $0.frame.height > 100
        }.count
    }

    @MainActor
    private func count(_ app: XCUIApplication, prefix: String) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).count
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func surfaceTag(_ app: XCUIApplication) -> String {
        let idiom = UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone"
        let layout = marked(app, "ipad-workspace-layout").exists ? "regular" : "compact"
        return "\(idiom)-\(layout)"
    }

    private enum RootLayout {
        case regular
        case compact
        case missing
    }

    @MainActor
    private func waitForRootLayout(_ app: XCUIApplication) -> RootLayout {
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

    @MainActor
    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let frame = primaryWindowFrame(app)
            if frame.width > 1, frame.height > 1, (frame.width > frame.height) == landscape {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("未转到\(landscape ? "横屏" : "竖屏")，窗口 \(primaryWindowFrame(app))")
    }

    @MainActor
    private func primaryWindowFrame(_ app: XCUIApplication) -> CGRect {
        var best = CGRect.zero
        var bestArea: CGFloat = 0
        for window in app.windows.allElementsBoundByIndex {
            let area = window.frame.width * window.frame.height
            if area > bestArea {
                best = window.frame
                bestArea = area
            }
        }
        return best
    }
}
