//
//  TaskNotificationParserTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

struct TaskNotificationParserTests {

    @Test func parsesCompletedEnvelope() {
        let notification = TaskNotificationParser.parse("""
        <task id="ses_child" state="completed">
        <summary>Background task completed: Inspect the API client</summary>
        <task_result>
        Found **three** failing tests.
        </task_result>
        </task>
        """)
        #expect(notification?.sessionID == "ses_child")
        #expect(notification?.state == .completed)
        #expect(notification?.isFailed == false)
        #expect(notification?.summary == "Background task completed: Inspect the API client")
        #expect(notification?.resultText == "Found **three** failing tests.")
        #expect(notification?.displayTitle == "Inspect the API client")
    }

    @Test func parsesErrorEnvelope() {
        let notification = TaskNotificationParser.parse("""
        <task id="ses_err" state="error">
        <summary>Background task failed: disk full</summary>
        <task_error>
        No space left on device.
        </task_error>
        </task>
        """)
        #expect(notification?.state == .error)
        #expect(notification?.isFailed == true)
        #expect(notification?.resultText == "No space left on device.")
        #expect(notification?.displayTitle == "disk full")
    }

    @Test func parsesRunningEnvelope() {
        let notification = TaskNotificationParser.parse("""
        <task id="ses_run" state="running">
        <summary>Background task completed: still going</summary>
        <task_result>
        partial
        </task_result>
        </task>
        """)
        #expect(notification?.state == .running)
        #expect(notification?.isFailed == false)
        #expect(notification?.resultText == "partial")
    }

    @Test func missingSummaryFallsBackToShortSessionID() {
        let sessionID = "ses_very_long_child_identifier"
        let notification = TaskNotificationParser.parse("""
        <task id="\(sessionID)" state="completed">
        <task_result>
        done
        </task_result>
        </task>
        """)
        #expect(notification?.summary == nil)
        #expect(notification?.resultText == "done")
        #expect(notification?.displayTitle == TaskNotificationParser.shortSessionID(sessionID))
        #expect(notification?.displayTitle == "…" + String(sessionID.suffix(8)))
    }

    @Test func truncatedEnvelopeReturnsNil() {
        let text = """
        <task id="ses_child" state="completed">
        <summary>Background task completed: cut off</summary>
        <task_result>
        still streaming
        """
        #expect(TaskNotificationParser.parse(text) == nil)
    }

    @Test func nonTaskTextReturnsNil() {
        #expect(TaskNotificationParser.parse("please review the API client") == nil)
        #expect(TaskNotificationParser.parse("<summary>not a task</summary>") == nil)
        #expect(TaskNotificationParser.parse("<task_result>orphan</task_result>") == nil)
    }

    @Test func nestedAngleBracketsStayInsideResult() {
        let nested = "see </task> and <xml><child>a < b</child></xml>"
        let notification = TaskNotificationParser.parse("""
        <task id="ses_nested" state="completed">
        <summary>Background task completed: nested</summary>
        <task_result>
        \(nested)
        </task_result>
        </task>
        """)
        #expect(notification?.resultText == nested)
        #expect(notification?.sessionID == "ses_nested")
    }

    @Test func emptyResultStillParses() {
        let notification = TaskNotificationParser.parse("""
        <task id="ses_empty" state="completed">
        <summary>Background task completed: noop</summary>
        <task_result>
        </task_result>
        </task>
        """)
        #expect(notification?.resultText == "")
        #expect(notification?.displayTitle == "noop")
    }

    @Test func surroundingWhitespaceStillParses() {
        let notification = TaskNotificationParser.parse("\n\n<task id=\"ses_pad\" state=\"error\">\n<task_error>\nboom\n</task_error>\n</task>\n\n")
        #expect(notification?.sessionID == "ses_pad")
        #expect(notification?.state == .error)
        #expect(notification?.resultText == "boom")
    }

    @Test func missingIDOrResultReturnsNil() {
        #expect(TaskNotificationParser.parse("""
        <task state="completed">
        <task_result>
        x
        </task_result>
        </task>
        """) == nil)
        #expect(TaskNotificationParser.parse("""
        <task id="ses_child" state="completed">
        <summary>Background task completed: no body</summary>
        </task>
        """) == nil)
    }
}

struct TaskNotificationRenderingTests {

    @Test func missingSyntheticDecodesAsNotSynthetic() throws {
        let part = try decodePart([
            "id": "p1",
            "messageID": "m1",
            "sessionID": "s1",
            "type": "text",
            "text": "hello",
        ])
        #expect(part.synthetic == nil)
        #expect(part.isSyntheticText == false)
    }

    @Test func syntheticTrueDecodes() throws {
        let part = try decodePart([
            "id": "p1",
            "messageID": "m1",
            "sessionID": "s1",
            "type": "text",
            "synthetic": true,
            "text": "hello",
        ])
        #expect(part.synthetic == true)
        #expect(part.isSyntheticText == true)
    }

    @Test func syntheticFalseIsNotSyntheticText() throws {
        let part = try decodePart([
            "id": "p1",
            "messageID": "m1",
            "sessionID": "s1",
            "type": "text",
            "synthetic": false,
            "text": "hello",
        ])
        #expect(part.synthetic == false)
        #expect(part.isSyntheticText == false)
    }

    @Test func syntheticEnvelopeRendersTaskNotificationCard() throws {
        let message = try receiptMessage(synthetic: true)
        #expect(MessageRowView.taskNotificationAccessibilityIdentifier(for: message) == "task-notification-card")
        #expect(TaskNotificationParser.openSessionAccessibilityIdentifier == "task-notification-open-session")
        #expect(MessageRowView.taskNotification(in: message)?.resultText == "Found the failing test.")
        #expect(MessageRowView.showsEditFromHere(message) == false)
    }

    @Test func sameTextWithoutSyntheticStaysUserBubble() throws {
        let message = try receiptMessage(synthetic: false)
        #expect(MessageRowView.taskNotificationAccessibilityIdentifier(for: message) == nil)
        #expect(MessageRowView.taskNotification(in: message) == nil)
        #expect(MessageRowView.showsEditFromHere(message) == true)
        #expect(MessageRowView.copyableText(for: message).contains("<task"))
    }

    @Test func copyableTextReturnsResultBody() throws {
        let message = try receiptMessage(synthetic: true)
        #expect(MessageRowView.copyableText(for: message) == "Found the failing test.")
    }

    private func receiptMessage(synthetic: Bool?) throws -> MessageWithParts {
        let envelope = """
        <task id="ses_child" state="completed">
        <summary>Background task completed: Inspect the API client</summary>
        <task_result>
        Found the failing test.
        </task_result>
        </task>
        """
        var object: [String: Any] = [
            "id": "p1",
            "messageID": "m1",
            "sessionID": "s1",
            "type": "text",
            "text": envelope,
        ]
        if let synthetic {
            object["synthetic"] = synthetic
        }
        let part = try decodePart(object)
        let info = Message(
            id: "m1",
            sessionID: "s1",
            role: "user",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 1, completed: 1),
            finish: nil,
            tokens: nil,
            cost: nil
        )
        return MessageWithParts(info: info, parts: [part])
    }
}

private func decodePart(_ object: [String: Any]) throws -> Part {
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(Part.self, from: data)
}
