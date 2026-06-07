//
//  SessionDisplayStateTests.swift
//  OpenCodeClientTests
//
//  Covers F2 4a: the five-state session display model (SessionDisplayState.derive)
//  and the row title/summary helper (SessionTitleSummary). All cases are pure and
//  deterministic — `now`/`updated`/`lastViewedAt` are injected explicitly.
//

import Foundation
import Testing
@testable import OpenCodeClient

// MARK: - Fixtures

private func makeSession(
    id: String = "s1",
    title: String = "Title",
    updated: Int = 0
) -> Session {
    Session(
        id: id,
        slug: id,
        projectID: "p1",
        directory: "/tmp",
        parentID: nil,
        title: title,
        version: "1",
        time: .init(created: 0, updated: updated, archived: nil),
        share: nil,
        summary: nil
    )
}

private func makeStatus(_ type: String) -> SessionStatus {
    SessionStatus(type: type, attempt: nil, message: nil, next: nil)
}

/// Builds a `MessageWithParts` via JSON decoding to match the construction style
/// used elsewhere in the suite (Message/Part have decode-oriented initializers).
private func makeMessage(
    id: String = "m1",
    role: String = "user",
    text: String? = "Hello"
) throws -> MessageWithParts {
    let textStr = text.map { "\"\($0)\"" } ?? "null"
    let partsJSON: String = text == nil
        ? "[]"
        : """
          [{"id":"p1","messageID":"\(id)","sessionID":"s1","type":"text","text":\(textStr),"tool":null,"callID":null,"state":null,"metadata":null,"files":null}]
          """
    let json = """
    {"info":{"id":"\(id)","sessionID":"s1","role":"\(role)","parentID":null,"model":null,"time":{"created":0,"completed":null},"finish":null},"parts":\(partsJSON)}
    """
    return try JSONDecoder().decode(MessageWithParts.self, from: json.data(using: .utf8)!)
}

// MARK: - SessionDisplayState.derive

struct SessionDisplayStateTests {

    private let staleThreshold = SessionDisplayState.defaultStaleThreshold

    // 1. blocked → needsYou (regardless of status)
    @Test func blockedIsNeedsYouRegardlessOfStatus() {
        let session = makeSession(updated: 1000)
        // Even with a "busy" status and a viewed/idle session, blocked wins.
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("busy"),
            isBlocked: true,
            lastViewedAt: 2000,
            staleThreshold: staleThreshold,
            now: 2000
        )
        #expect(state == .needsYou)
    }

    @Test func blockedIsNeedsYouEvenWhenIdleAndRead() {
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("idle"),
            isBlocked: true,
            lastViewedAt: 5000,
            staleThreshold: staleThreshold,
            now: 5000
        )
        #expect(state == .needsYou)
    }

    // 2. busy/retry → running
    @Test func busyStatusIsRunning() {
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("busy"),
            isBlocked: false,
            lastViewedAt: 2000,
            staleThreshold: staleThreshold,
            now: 2000
        )
        #expect(state == .running)
    }

    @Test func retryStatusIsRunning() {
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("retry"),
            isBlocked: false,
            lastViewedAt: 2000,
            staleThreshold: staleThreshold,
            now: 2000
        )
        #expect(state == .running)
    }

    // Priority: blocked beats busy.
    @Test func blockedBeatsBusy() {
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("busy"),
            isBlocked: true,
            lastViewedAt: 2000,
            staleThreshold: staleThreshold,
            now: 2000
        )
        #expect(state == .needsYou)
    }

    // 3a. idle + never viewed → doneUnread
    @Test func idleNeverViewedIsDoneUnread() {
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("idle"),
            isBlocked: false,
            lastViewedAt: nil,
            staleThreshold: staleThreshold,
            now: 1000
        )
        #expect(state == .doneUnread)
    }

    @Test func idleViewedBeforeUpdateIsDoneUnread() {
        // Viewed at 500, but updated at 1000 afterwards → unread.
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("idle"),
            isBlocked: false,
            lastViewedAt: 500,
            staleThreshold: staleThreshold,
            now: 1000
        )
        #expect(state == .doneUnread)
    }

    // 4. idle + viewed at/after update, within threshold → doneRead
    @Test func idleViewedAfterUpdateIsDoneRead() {
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("idle"),
            isBlocked: false,
            lastViewedAt: 1500,
            staleThreshold: staleThreshold,
            now: 2000
        )
        #expect(state == .doneRead)
    }

    @Test func idleViewedExactlyAtUpdateIsDoneRead() {
        // Boundary: lastViewedAt == updated is "read" (not strictly less-than).
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("idle"),
            isBlocked: false,
            lastViewedAt: 1000,
            staleThreshold: staleThreshold,
            now: 1000
        )
        #expect(state == .doneRead)
    }

    // 5. idle + read + older than threshold → stale
    @Test func idleReadButOldIsStale() {
        let updated = 1000
        let session = makeSession(updated: updated)
        // now is more than `staleThreshold` past updated, and it has been read.
        let now = updated + staleThreshold + 1
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("idle"),
            isBlocked: false,
            lastViewedAt: updated,
            staleThreshold: staleThreshold,
            now: now
        )
        #expect(state == .stale)
    }

    @Test func idleReadAtThresholdBoundaryIsNotStale() {
        // Exactly at the threshold (now - updated == threshold) is not yet stale.
        let updated = 1000
        let session = makeSession(updated: updated)
        let now = updated + staleThreshold
        let state = SessionDisplayState.derive(
            session: session,
            status: makeStatus("idle"),
            isBlocked: false,
            lastViewedAt: updated,
            staleThreshold: staleThreshold,
            now: now
        )
        #expect(state == .doneRead)
    }

    @Test func nilStatusTreatedAsIdle() {
        // No status known → not running; falls through to read/unread logic.
        let session = makeSession(updated: 1000)
        let state = SessionDisplayState.derive(
            session: session,
            status: nil,
            isBlocked: false,
            lastViewedAt: nil,
            staleThreshold: staleThreshold,
            now: 1000
        )
        #expect(state == .doneUnread)
    }
}

// MARK: - SessionTitleSummary

struct SessionTitleSummaryTests {

    @Test func realTitleIsPreserved() throws {
        let session = makeSession(title: "Fix the login bug")
        let messages = [try makeMessage(text: "please help with something else")]
        #expect(SessionTitleSummary.summary(for: session, messages: messages) == "Fix the login bug")
    }

    @Test func emptyTitleDerivesFromFirstUserMessage() throws {
        let session = makeSession(title: "")
        let messages = [try makeMessage(text: "Refactor the networking layer")]
        #expect(
            SessionTitleSummary.summary(for: session, messages: messages)
                == "Refactor the networking layer"
        )
    }

    @Test func autoGeneratedTimestampTitleDerivesFromFirstUserMessage() throws {
        let session = makeSession(title: "New session - 2026-06-07T12:34:56Z")
        let messages = [try makeMessage(text: "Add dark mode support")]
        #expect(
            SessionTitleSummary.summary(for: session, messages: messages)
                == "Add dark mode support"
        )
    }

    @Test func bareNewSessionTitleDerivesFromFirstUserMessage() throws {
        let session = makeSession(title: "New session")
        let messages = [try makeMessage(text: "Investigate the crash")]
        #expect(
            SessionTitleSummary.summary(for: session, messages: messages)
                == "Investigate the crash"
        )
    }

    @Test func derivationUsesFirstUserMessageNotAssistant() throws {
        let session = makeSession(title: "")
        let messages = [
            try makeMessage(id: "a1", role: "assistant", text: "Sure, I can help."),
            try makeMessage(id: "u1", role: "user", text: "Generate a report"),
        ]
        #expect(
            SessionTitleSummary.summary(for: session, messages: messages) == "Generate a report"
        )
    }

    @Test func derivationCollapsesWhitespaceToSingleLine() throws {
        let session = makeSession(title: "")
        let messages = [try makeMessage(text: "line one\\n\\n  line two   tail")]
        #expect(
            SessionTitleSummary.summary(for: session, messages: messages)
                == "line one line two tail"
        )
    }

    @Test func emptyMessagesFallsBackToOriginalTitle() throws {
        // Auto-generated title + no usable messages → return the original title.
        let session = makeSession(title: "New session")
        #expect(SessionTitleSummary.summary(for: session, messages: []) == "New session")
    }

    @Test func userMessageWithoutTextFallsBackToOriginalTitle() throws {
        // Auto-generated title, a user message but with no text part → fall back.
        let session = makeSession(title: "New session")
        let messages = [try makeMessage(text: nil)]
        #expect(SessionTitleSummary.summary(for: session, messages: messages) == "New session")
    }
}
