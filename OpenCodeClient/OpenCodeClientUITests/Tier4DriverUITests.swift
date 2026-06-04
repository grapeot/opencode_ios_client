//
//  Tier4DriverUITests.swift
//  OpenCodeClientUITests
//

import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class Tier4DriverUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private lazy var fileConfig: [String: String] = Self.loadFileConfig()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testConfigureServerFromEnvironment() throws {
        _ = try requiredServerURL()
        let app = launchApp()
        configureServer(in: app)
    }

    @MainActor
    func testSendPromptFromEnvironment() throws {
        let prompt = try requiredEnv("TIER4_PROMPT")
        let app = launchApp()
        if hasServerURL() {
            configureServer(in: app)
            app.terminate()
            app.launch()
        }
        openChat(in: app)
        ensureSessionExists(in: app)

        let input = app.descendants(matching: .any)["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 20), "chat-input should exist")
        replaceText(in: input, with: prompt)

        let send = app.descendants(matching: .any)["chat-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 8), "chat-send should exist")
        XCTAssertTrue(send.isEnabled, "chat-send should be enabled after typing prompt")
        send.tap()

        let accepted = waitForPromptAccepted(prompt, input: input, app: app, timeout: 15)
        XCTAssertTrue(accepted, "prompt should be accepted by the live send flow; alert=\(alertDescription(app)); input=\((input.value as? String) ?? "")")
    }

    @MainActor
    func testAccessibilityObservationSnapshot() throws {
        let app = launchApp()
        let identifiers = [
            "chat-input",
            "chat-send",
            "chat-toolbar-create-session",
            "settings-server-url",
            "settings-username",
            "settings-password",
            "settings-test-connection",
            "settings-connection-status",
        ]

        var lines: [String] = []
        for identifier in identifiers {
            let exists = app.descendants(matching: .any)[identifier].exists
            lines.append("\(identifier)=\(exists)")
        }

        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "tier4_accessibility_observation"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(app.descendants(matching: .any)["chat-input"].waitForExistence(timeout: 15), "chat-input should be observable")
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    @MainActor
    private func configureServer(in app: XCUIApplication) {
        openSettings(in: app)

        replaceText(in: app.descendants(matching: .any)["settings-server-url"], with: requiredServerURLOrFail())
        replaceText(in: app.descendants(matching: .any)["settings-username"], with: configValue("OPENCODE_USERNAME", "TIER4_USERNAME", "username"))
        replaceText(in: app.descendants(matching: .any)["settings-password"], with: configValue("OPENCODE_PASSWORD", "TIER4_PASSWORD", "password"), sensitive: true)

        let testConnection = app.descendants(matching: .any)["settings-test-connection"]
        XCTAssertTrue(testConnection.waitForExistence(timeout: 10), "settings-test-connection should exist")
        testConnection.tap()

        let connected = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Connected'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 30), "server should report connected")
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        if app.descendants(matching: .any)["settings-server-url"].exists { return }
        if app.tabBars.firstMatch.exists, app.tabBars.buttons.count >= 3 {
            app.tabBars.buttons.element(boundBy: 2).tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["settings-server-url"].waitForExistence(timeout: 15), "settings tab should open")
    }

    @MainActor
    private func openChat(in app: XCUIApplication) {
        if app.descendants(matching: .any)["chat-input"].exists { return }
        if app.tabBars.firstMatch.exists, app.tabBars.buttons.count >= 1 {
            app.tabBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["chat-input"].waitForExistence(timeout: 20), "chat tab should open")
    }

    @MainActor
    private func ensureSessionExists(in app: XCUIApplication) {
        let input = app.descendants(matching: .any)["chat-input"]
        let create = app.descendants(matching: .any)["chat-toolbar-create-session"]
        if create.waitForExistence(timeout: 10), create.isEnabled {
            create.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20), "chat-input should exist after creating or selecting a session")
    }

    @MainActor
    private func replaceText(in element: XCUIElement, with text: String, sensitive: Bool = false) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "element should exist before replacing text")
        element.tap()
        if let value = element.value as? String, !value.isEmpty, value != element.placeholderValue {
            element.press(forDuration: 1.0)
            let selectAll = XCUIApplication().menuItems["Select All"]
            if selectAll.waitForExistence(timeout: 2) {
                selectAll.tap()
            }
        }
        if sensitive {
            pasteSensitiveText(text)
            return
        }
        element.typeText(text.isEmpty ? XCUIKeyboardKey.delete.rawValue : text)
    }

    private func pasteSensitiveText(_ text: String) {
        #if canImport(UIKit)
        let previous = UIPasteboard.general.string
        UIPasteboard.general.string = text
        let paste = XCUIApplication().menuItems["Paste"]
        if paste.waitForExistence(timeout: 2) {
            paste.tap()
        } else {
            XCUIApplication().typeKey("v", modifierFlags: .command)
        }
        UIPasteboard.general.string = previous
        #else
        XCTFail("Sensitive paste is only implemented on UIKit platforms")
        #endif
    }

    @MainActor
    private func alertDescription(_ app: XCUIApplication) -> String {
        let alert = app.alerts.firstMatch
        guard alert.exists else { return "" }
        let labels = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        return labels.isEmpty ? alert.label : labels
    }

    @MainActor
    private func waitForPromptAccepted(_ prompt: String, input: XCUIElement, app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let sendFailed = app.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'failed'")).firstMatch.exists
            if sendFailed { return false }

            let value = (input.value as? String) ?? ""
            if !value.contains(prompt) {
                // sendMessage restores the prompt on API failure; staying clear here means the UI flow accepted it.
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
                let stableValue = (input.value as? String) ?? ""
                return !stableValue.contains(prompt)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func hasServerURL() -> Bool {
        !configValue("OPENCODE_SERVER_URL", "TIER4_SERVER_URL", "server_url").isEmpty
    }

    private func requiredServerURL() throws -> String {
        guard hasServerURL() else {
            throw XCTSkip("Missing required environment variable: OPENCODE_SERVER_URL or TIER4_SERVER_URL")
        }
        return configValue("OPENCODE_SERVER_URL", "TIER4_SERVER_URL", "server_url")
    }

    private func requiredServerURLOrFail() -> String {
        let value = configValue("OPENCODE_SERVER_URL", "TIER4_SERVER_URL", "server_url")
        XCTAssertFalse(value.isEmpty, "OPENCODE_SERVER_URL or TIER4_SERVER_URL should be set")
        return value
    }

    private func requiredEnv(_ key: String) throws -> String {
        let configKey = key == "TIER4_PROMPT" ? "prompt" : key
        let value = env[key] ?? fileConfig[configKey] ?? ""
        guard !value.isEmpty else {
            throw XCTSkip("Missing required environment variable: \(key)")
        }
        return value
    }

    private func configValue(_ keys: String...) -> String {
        for key in keys {
            if let value = env[key], !value.isEmpty { return value }
            if let value = fileConfig[key], !value.isEmpty { return value }
        }
        return ""
    }

    private static func loadFileConfig() -> [String: String] {
        let url = URL(fileURLWithPath: "/tmp/opencode-ios-tier4-config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.compactMapValues { $0 as? String }
    }
}
