# UI Test Prompt: read operation is visibly marked as read

You are testing the OpenCode iOS client in Simulator. First read `docs/skill_operate_ios_simulator.md` and `docs/skill_ui_test_tasks.md`. Use `ui_driver` where it has deterministic commands, and do not invent unsupported capabilities.

## Goal

Verify that a user can see a file read operation represented as read, distinct from write/edit operations.

## Current Setup Options

Preferred deterministic setup:

- Launch the app with `UITEST_TOOL_CARDS_FIXTURE`.
- Use `ui_driver run-xcuitest` to run `OpenCodeClientUITests/ToolCardsUITests/testToolCardsFixtureRendersFileCardsAndMergedToolCalls`, which launches with `UITEST_TOOL_CARDS_FIXTURE` and asserts that `toolcard.read.*` and `toolcard.write.*` are distinguishable.

Live setup, only when server credentials and a booted simulator are available:

- Use the local read-only test server, preferably port `4097`.
- Send a read-only prompt: `Read the file AGENTS.md and reply with only its first line. Do not create, edit, or write any file.`
- Do not ask the app to create, edit, or write files.

## Acceptance Criteria

All must hold for PASS:

1. The app is launched in Simulator.
2. The observed UI or deterministic test output proves a read file card exists.
3. The read card is distinguishable from write/edit cards via `toolcard.read.*`, `Read file <name>`, or clear screenshot evidence.
4. No write/edit card appears in the live read-only scenario. Fixture mode may include write cards by design; in fixture mode the requirement is only that read and write are distinguishable.

## Reporting

Return PASS / FAIL / BLOCKED.

Include evidence:

- screenshot path, if used,
- relevant test command and result, if used,
- exact reason if blocked.

Known BLOCKED reasons include no booted simulator, app not installed, live server unavailable, missing credentials, or current iOS `ui_driver` screenshot-only observability being insufficient for a confident live UI verdict.
