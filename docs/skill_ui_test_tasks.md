# Skill: run Tier 4 iOS UI test tasks

Type: Workflow

Use for LLM-driven UI testing of the OpenCode iOS client: tasks where fixed assertions are not enough and an agent must inspect simulator evidence, decide whether to wait/retry, and return PASS / FAIL / BLOCKED with evidence.

This workflow depends on `docs/skill_operate_ios_simulator.md`.

## Core Pattern

Tier 4 separates mechanical operations from judgment:

- `ui_driver` CLI is the skeleton. It launches the app, captures screenshots, lists devices, runs targeted XCUITest harnesses, and returns JSON.
- The agent is the judge. It reads JSON and screenshots, decides whether the evidence satisfies the user scenario, and reports a verdict.
- Each test is a prompt under `docs/ui_test_prompts/`.

Do not turn a Tier 4 prompt into a coordinate script. If every step is fixed, write an XCUITest or Tier 3 integration test instead.

## Running A Test Prompt

1. Read the prompt file.
2. Read `docs/skill_operate_ios_simulator.md`.
3. Build/install the app if needed using standard Xcode workflows.
4. Use `ui_driver` for available deterministic operations.
5. For exact iOS element identity, use `ui_driver run-xcuitest` against a focused UI test rather than coordinate tapping.
6. Use screenshots and deterministic test output as evidence.
7. Return exactly one verdict: PASS, FAIL, or BLOCKED.

## Verdict Standard

PASS means every acceptance criterion in the prompt is satisfied with evidence.

FAIL means the app was reachable but one or more acceptance criteria were not met. Say which criterion failed and cite screenshot/UI/test evidence.

BLOCKED means infrastructure prevented a confident verdict: no booted simulator, app not installed, server unavailable, missing credentials, or current driver observability is insufficient. A precise BLOCKED report is a successful Tier 4 run; vague abandonment is not.

## Current v1 Limitation

The iOS driver does not expose a full Android-style accessibility tree. For scenarios requiring exact element identity, combine:

- Tier 2 XCUITest assertions for deterministic fixture state.
- Tier 3 live integration tests for server/client contract.
- Tier 4 screenshots for visual/UX judgment.

The preferred Tier 4 bridge is `run-xcuitest` or XCTest-backed `tree`: it invokes XCTest through the driver and returns a JSON verdict surface (`ok`, `exit_code`, `test_summaries`, `result_bundle`). This keeps iOS automation on stable accessibility identifiers and avoids brittle coordinate scripts. Use `configure-server` and `send-prompt` for the standard live server flow; they pass secrets through a temporary `0600` config file, paste passwords instead of typing them, mask passwords in JSON output, and run Xcode with parallel UI testing disabled.

When a prompt asks for read/write card distinction, prefer evidence from `toolcard.read.*` / `toolcard.write.*` XCUITest or visible screenshot labels. If neither is available, return BLOCKED and say the driver needs richer accessibility observation.

## Deterministic Screenshot QA

Curated fixture data can still be Tier 4 when the run drives the real app on a real simulator, captures a screenshot, and the agent judges the rendered UX. The boundary is not whether data is synthetic; it is whether the output is only fixed assertions (Tier 2) or visual/interaction evidence used for a scenario verdict (Tier 4).

Prefer deterministic screenshot harnesses for design QA. They avoid live server drift, secrets, stale real sessions, and network timing while still proving whether the UI actually rendered on iPhone/iPad. For archive UI, `OpenCodeClientUITests/testCaptureSessionArchiveFixtureScreenshot` is the reusable harness: set `TIER4_SCREENSHOT_PATH` or `/tmp/opencode-ios-tier4-config.json` with `screenshot_path`, run that focused test, then inspect the PNG under `tmp/visual_qa/`.

Check in reusable code that improves the workflow: launch arguments, fixtures, screenshot harnesses, `ui_driver` commands, redaction helpers, and docs. Do not check in screenshots, `.xcresult`, `/tmp/opencode-ios-tier4-config.json`, DerivedData, Xcode `xcuserdata`, credential JSON, or real session captures.

## Safety Boundary

Live server Tier 4 tests must be read-only. Do not send prompts that create, edit, or write files against the shared workspace. Keep screenshots and artifacts out of git.

## From Tier 4 Back To Lower Tiers

When Tier 4 exposes a stable behavior that can be asserted deterministically, add a Tier 2 XCUITest or Tier 3 integration test. Tier 4 explores; lower tiers preserve.
