# Skill: operate the OpenCode iOS client in Simulator

Type: API Guide / operation layer

Use when an agent needs to launch the OpenCode iOS client, capture screenshots, or gather basic simulator state for Tier 4 UI testing.

This skill is the iOS counterpart to Android's emulator operation skill. The current iOS `ui_driver` is a v1 skeleton backed by `xcrun simctl`; it supports deterministic launch/screenshot/status operations but does not yet expose a full accessibility tree.

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

`tree` currently returns `observability: screenshot_only`, with empty `nodes` and `compact`. This is intentional. For deterministic element assertions use XCUITest; for Tier 4 v1, use screenshot evidence and exact BLOCKED reporting when the missing accessibility tree prevents a confident verdict.

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
- No reliable `tap-label`, `configure-server`, or `send-prompt` command yet.
- Live read-card flows are currently better validated by Tier 3 Swift tests and fixture XCUITest; Tier 4 uses this driver for launch/screenshot evidence until richer iOS observation exists.
