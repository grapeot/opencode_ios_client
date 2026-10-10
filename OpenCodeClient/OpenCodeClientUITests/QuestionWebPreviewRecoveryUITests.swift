import XCTest

final class QuestionWebPreviewRecoveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuestionFailureKeepsAnswersThenSuccessRemovesTargetCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_QUESTION_RECOVERY_FIXTURE",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let target = app.descendants(matching: .any)["question-card-q-target"]
        let other = app.descendants(matching: .any)["question-card-q-other"]
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        XCTAssertTrue(other.exists)

        let optionID = "question-option-q-target-Build"
        let option = app.buttons[optionID]
        XCTAssertTrue(option.waitForExistence(timeout: 4))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier == %@", optionID)).count, 1)
        reveal(option, in: app)
        option.tap()

        let customToggle = app.descendants(matching: .any)["question-custom-toggle-q-target"]
        XCTAssertTrue(customToggle.waitForExistence(timeout: 4))
        customToggle.tap()
        let field = app.textFields["question-custom-field-q-target"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        field.typeText("kept-answer")

        let submit = app.buttons["question-submit-q-target"]
        reveal(submit, in: app)
        submit.tap()
        waitUntil(submit, isEnabled: false)
        waitUntil(submit, isEnabled: true)

        XCTAssertEqual(option.value as? String, "selected")
        XCTAssertEqual(field.value as? String, "kept-answer")
        XCTAssertEqual(app.descendants(matching: .any)["question-recovery-recorded"].label, "Build+kept-answer")
        XCTAssertTrue(submit.isEnabled)
        XCTAssertTrue(target.exists)
        XCTAssertTrue(other.exists)

        reveal(submit, in: app)
        submit.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: target)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(other.exists)
    }

    @MainActor
    func testWebPreviewContainerRetryRendersSentinel() {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_WEB_PREVIEW_RETRY_FIXTURE",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let identityID = "web-preview-fixture-identity"
        let identity = app.descendants(matching: .any)[identityID]
        XCTAssertTrue(identity.waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identityID)).count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "web-preview-fixture-root")).count, 0)
        XCTAssertEqual(identity.value as? String, "/tmp/w03-preview/note.md|W03_PREVIEW_SENTINEL")

        let retryID = "markdown-web-preview-retry"
        let retry = app.buttons[retryID]
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier == %@", retryID)).count, 1)
        let webView = app.webViews["markdown-web-preview-webview"]
        XCTAssertFalse(webView.staticTexts["W03_PREVIEW_SENTINEL"].exists)

        let recorded = identity.value as? String
        retry.tap()
        let sentinel = webView.staticTexts["W03_PREVIEW_SENTINEL"]
        XCTAssertTrue(sentinel.waitForExistence(timeout: 12))
        XCTAssertEqual(identity.value as? String, recorded)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable && attempts < 3 {
            app.swipeUp()
            attempts += 1
        }
    }

    @MainActor
    private func waitUntil(_ element: XCUIElement, isEnabled enabled: Bool) {
        let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled))
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 6)
    }
}
