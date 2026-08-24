# Skill: operate the OpenCode iOS client in Simulator

Type: API Guide / operation layer

Use when an agent needs to launch the OpenCode iOS client, capture screenshots, or gather basic simulator state for Tier 4 UI testing.

This skill is the iOS counterpart to Android's emulator operation skill. The current iOS `ui_driver` is backed by `xcrun simctl` plus an XCTest bridge. It supports deterministic launch/screenshot/status operations, targeted XCUITest runs, high-level `configure-server` / `send-prompt` flows, and XCTest-backed focused observations. It still does not expose a full Android-style accessibility tree.

## Project Facts

- Project root: `/Users/grapeot/co/knowledge_working/adhoc_jobs/opencode_ios_client`
- Xcode project: `OpenCodeClient/OpenCodeClient.xcodeproj`
- Scheme: `OpenCodeClient`
- App bundle id: `com.grapeot.OpenCodeClient`
- Driver path: `ui_driver/`
- Driver command: `ui_driver/.venv/bin/python -m ui_driver`

## Setup

Before Python operations, ensure the repo-local environment exists:

```bash
cd /Users/grapeot/co/knowledge_working/adhoc_jobs/opencode_ios_client/ui_driver
uv venv
source .venv/bin/activate
uv pip install -e '.[dev]'
```

Run driver tests without a simulator:

```bash
.venv/bin/python -m pytest -q
```

## Driver Commands

List simulators:

```bash
.venv/bin/python -m ui_driver devices
```

Launch the app on the first booted simulator:

```bash
.venv/bin/python -m ui_driver launch --bundle-id com.grapeot.OpenCodeClient
```

Launch with fixture arguments:

```bash
.venv/bin/python -m ui_driver launch --bundle-id com.grapeot.OpenCodeClient UITEST_TOOL_CARDS_FIXTURE
```

Capture a screenshot:

```bash
.venv/bin/python -m ui_driver screenshot --output artifacts/current.png
```

Get current observation state:

```bash
.venv/bin/python -m ui_driver tree --screenshot artifacts/current.png
```

Without Xcode arguments, `tree` returns `observability: screenshot_only`, with empty `nodes` and `compact`. This remains intentional.

For focused accessibility observation, route `tree` through XCTest:

```bash
.venv/bin/python -m ui_driver tree \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --result-bundle "artifacts/tier4-observation-$(date +%Y%m%d-%H%M%S).xcresult"
```

This returns `observability: xcuitest_accessibility_snapshot` and XCTest summaries. It is a focused bridge over known identifiers, not a full tree dump.

High-level live flows:

```bash
.venv/bin/python -m ui_driver configure-server \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --server-url http://127.0.0.1:4096 \
  --username "$OPENCODE_USERNAME" \
  --password-env OPENCODE_PASSWORD \
  --result-bundle "artifacts/configure-server-$(date +%Y%m%d-%H%M%S).xcresult"

.venv/bin/python -m ui_driver send-prompt \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --prompt 'Read README.md and summarize it in one sentence.' \
  --result-bundle "artifacts/send-prompt-$(date +%Y%m%d-%H%M%S).xcresult"
```

Passwords are read from the named environment variable and passed to XCTest through a temporary `0600` config file at `/tmp/opencode-ios-tier4-config.json`. The password is pasted into the secure field rather than typed, and JSON output masks password values in stdout/stderr tails. The driver runs Xcode UI tests with `-parallel-testing-enabled NO` to avoid runner clone flakiness.

Verified live 4097 flow:

- `configure-server` against `http://127.0.0.1:4097` passed via `Tier4DriverUITests/testConfigureServerFromEnvironment`.
- `send-prompt` against `http://127.0.0.1:4097` passed via `Tier4DriverUITests/testSendPromptFromEnvironment` after creating a fresh session and sending `T4PING4097`.

Run a targeted XCTest UI harness and return JSON summaries:

```bash
.venv/bin/python -m ui_driver run-xcuitest \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --only-testing OpenCodeClientUITests/ToolCardsUITests/testToolCardsFixtureRendersFileCardsAndMergedToolCalls \
  --result-bundle "artifacts/read-card-visible-$(date +%Y%m%d-%H%M%S).xcresult"
```

This is the current best-practice bridge for exact UI identity on iOS. `simctl` can launch and screenshot, but XCTest is the stable way to assert accessibility identifiers like `toolcard.read.*` and `toolcard.write.*`.

## Device Selection

The driver chooses a simulator in this order:

1. `--udid <simulator-udid>`
2. `--device <name>` among booted simulators
3. first booted simulator
4. structured `device_selection_failed` error

## Safety Rules

- Use deterministic fixture launch arguments whenever possible.
- For live OpenCode server flows, use read-only prompts. Do not ask the app to create, edit, or write files unless the server cwd is a dedicated sandbox.
- Store screenshots under `ui_driver/artifacts/` or another ignored path.
- Do not commit screenshots, `.xcresult`, `.venv`, credentials, or Xcode user data.

## Known Limitations

- No full accessibility tree in v1.
- No reliable generic `tap-label` command yet.
- Exact element identity is available through targeted XCUITest runs and XCTest-backed `tree`, not through a raw simulator tree dump.
- Live read-card flows are currently better validated by Tier 3 Swift tests and fixture XCUITest; Tier 4 uses this driver for launch/screenshot/XCTest evidence until richer iOS observation exists.
