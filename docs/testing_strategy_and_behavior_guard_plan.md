# OpenCode iOS Client Testing Strategy and Behavior-Guard Plan

Date: 2026-03-13

## Goal

This document explains the current automated test system in the OpenCode iOS client and proposes a practical behavior-guard strategy for regressions such as the recent session-list issue, where functionality still existed but the user-visible interaction path regressed.

The main objective is not just to increase test count. The objective is to make product behavior legible, isolate the right seams for regression coverage, and keep future UI or state refactors from silently changing user-visible behavior.

## Current Test System

### Test targets

The repository currently has two test targets:

| Target | Framework | Role | Current state |
| --- | --- | --- | --- |
| `OpenCodeClientTests` | Swift Testing (`import Testing`) | Unit, contract, reducer, and state-flow tests | Primary coverage layer |
| `OpenCodeClientUITests` | XCTest UI Testing | Launch and basic interaction smoke tests | Very light coverage |

### Main test locations

- `OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITestsLaunchTests.swift`

### Current unit-test design

The main unit-test target already covers several important layers:

1. API/data contract tests
   - JSON decoding for `Session`, `Message`, `Part`, `SSEEvent`, `TodoItem`, `Project`, `QuestionRequest`, and related models.
   - These tests protect compatibility against API shape drift and optional-field regressions.

2. Business-logic tests
   - Static or pure-ish helpers such as URL normalization, pagination limits, path normalization, deletion selection, and session tree construction.
   - These tests are fast and stable because they do not depend on live UI state.

3. AppState flow tests
   - `AppState` is injected with `MockAPIClient` and `MockSSEClient`, allowing end-to-end state transitions to be tested without network calls.
   - This is currently the most valuable integration seam in the project.

4. Focused subsystem tests
   - Permission handling, SSH helpers, Activity tracking, file parsing, and SSE event routing already have targeted checks.

### Current UI-test design

The UI-test target is intentionally small today:

- app launch succeeds
- Chat tab shows the input field

This means the project already has a smoke-test shell, but it does not yet protect complex interaction regressions around session lists, message rendering, or session switching.

## Strengths of the Current System

- The project already uses dependency injection in `AppState`, which makes behavior tests far easier to add than in a tightly coupled app.
- The repository already treats state transitions as testable logic instead of hiding everything inside view bodies.
- Session behavior already has a partial foundation: `buildSessionTree`, `sidebarSessions`, `toggleSessionExpanded`, and `loadMoreSessions` are all observable seams.
- The existing test file is large but coherent: new behavior tests can be added without inventing a brand-new framework.

## Current Gaps

The current system is strongest at validating data contracts and local state logic. It is weaker at guarding behavior that sits across a view-model boundary.

The recent session-list regression is a good example:

- `AppState.sessionTree` remained valid.
- `AppState.sidebarSessions` remained valid.
- the regression happened because the view consumed the wrong source for the user-visible list.

So the missing guard is not just "more unit tests." The missing guard is a deliberate layer that checks whether important product behaviors are wired to the right state seam.

## Testing Taxonomy Going Forward

The test system should be treated as four layers, each with a different purpose.

### Layer 0: contract tests

Purpose:
- protect decoding, optional fields, wire formats, and compatibility with server events

Best examples in the current codebase:
- model decoding tests
- SSE event shape tests

### Layer 1: state and business-logic tests

Purpose:
- protect pure logic and deterministic state transforms

Best examples in the current codebase:
- `AppState.buildSessionTree(from:)`
- `AppState.nextSessionIDAfterDeleting(...)`
- pagination helpers
- path and URL normalization helpers

### Layer 2: state-flow tests with mocks

Purpose:
- protect behavior that spans API responses, SSE updates, and `AppState`

Best examples in the current codebase:
- `loadSessions`
- `loadMoreSessions`
- session selection / message reload flows
- message update filtering by `sessionID`

### Layer 3: UI smoke tests

Purpose:
- protect a few critical user journeys where the behavior can regress even if state helpers still pass

These should remain few in number. They are slower and more fragile, but they are the only layer that can directly catch "the right data exists but the user cannot reach it anymore."

## What a Behavior Guard Means in This Project

In this repository, a behavior guard should protect one of the following:

- a user-visible workflow that must remain reachable
- an important invariant across multiple layers
- a bug pattern that can recur during refactors

It should not be used for purely cosmetic details unless those details are core to interaction.

Examples of valid behavior guards:

- child/subagent sessions remain visible in the session list hierarchy
- deleting the current session selects the right fallback session
- non-current session SSE updates do not overwrite the visible session
- sending a message does not leave a duplicate optimistic user row behind

## Immediate Behavior-Guard Plan: Session List Regressions

### Problem statement

The session-list regression happened because the rendered list changed from a full tree to a root-only list. The bug was not a missing backend capability. The bug was a mismatch between product behavior and the chosen UI data source.

### Guard strategy

This class of regression should be covered at two layers.

#### A. State-flow guard

Add or strengthen tests around these seams:

- `AppState.sessionTree`
- `AppState.sidebarSessions`
- `AppState.loadMoreSessions()`
- `AppState.toggleSessionExpanded(_:)`

Required invariants:

1. `sessionTree` preserves parent/child structure for visible sessions.
2. `sidebarSessions` remains a root-only pagination helper, not the canonical full list.
3. loading more sessions can reveal additional root sessions without deleting child hierarchy from the canonical tree.
4. archived filtering applies consistently to both tree and root-only helper views.

#### B. UI wiring guard

Add one light UI-level guard to prove the session list surfaces tree content.

Good options:

- a view inspection approach, if the project later adopts a view inspection library
- or a targeted UI smoke test with stable accessibility identifiers on session rows / expand buttons

What this test must prove:

- a child session can be made visible from the list UI
- the user-visible session list is not limited to root sessions only

### Why both layers are needed

If only state tests exist, a future edit can keep `sessionTree` correct while accidentally rendering `sidebarSessions` again.

If only UI tests exist, the tests become slow, narrow, and hard to debug.

The right combination is:

- state-flow tests for deterministic behavior
- one lightweight UI guard for wiring

## Proposed Near-Term Test Work

### P0: add behavior guards for current high-risk regressions

1. Session list hierarchy visibility
2. Session pagination versus root-only helper semantics
3. Current-session deletion fallback
4. Current-session-only reload behavior for SSE-driven updates

### P1: add one or two critical UI smoke tests

Candidates:

1. Chat tab is usable after launch
2. Session list can show a child session
3. Switching sessions updates visible conversation content

### P2: expand recurring bug-pattern coverage

Candidates:

1. duplicate optimistic user messages after send
2. stale streaming rows after session switch
3. file preview jumps caused by stale async responses

## Recommended Test-Seam Ownership

The codebase should use these ownership rules when new work lands.

| Behavior type | Primary seam | Secondary seam |
| --- | --- | --- |
| API shape / decoding | model tests | AppState flow tests |
| deterministic state transform | pure helper / AppState property tests | AppState flow tests |
| async state orchestration | AppState flow tests with mocks | UI smoke tests |
| user-visible interaction reachability | UI smoke tests | AppState flow tests |
| refactor-sensitive cross-layer behavior | AppState flow tests plus one UI check | none |

## Practical Rules for Future Changes

When changing behavior in this project, use the following rules:

1. If a change modifies a visible workflow, add or update at least one regression test in the same branch.
2. If the change selects a different source of truth for a view, add a guard that proves the old user-visible behavior is still reachable.
3. If a bug can be fixed by switching sessions, refreshing, or reopening the view, the root cause likely spans state plus presentation; do not stop at a pure helper test.
4. Keep UI tests narrow. Use them to confirm reachability, not every detail of layout or copy.
5. Prefer deterministic mocked-flow tests over broad end-to-end tests unless the regression is explicitly about UI wiring.

## Verification Workflow

Recommended verification commands for test-related changes:

```bash
xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'generic/platform=iOS Simulator'
xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

Notes:

- local simulator infrastructure can fail independently of application code
- when simulator clone issues occur, build success still provides useful compile-level validation, but the environment problem should be called out explicitly

## Immediate Deliverables to Implement After This Plan

1. add a regression test that locks the intended relationship between `sessionTree` and `sidebarSessions`
2. add a regression test for pagination behavior when child sessions dominate the first page
3. add a lightweight UI smoke test for session-list hierarchy visibility once stable accessibility hooks exist
4. use the same framework to investigate and later guard the duplicate-sent-message ghost-row bug

## Summary

The current OpenCode iOS client already has a solid unit and state-flow testing foundation. The main gap is not absence of tests; it is absence of deliberate behavior guards at the seam where view wiring can silently drift from the intended product interaction.

The strategy in this document is to keep contract and flow tests as the backbone, then add a very small number of focused UI guards where they buy real protection. That keeps the suite fast enough to use regularly while still catching the class of regressions that matter most to actual users.
