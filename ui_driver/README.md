# iOS ui_driver

Deterministic `xcrun simctl` operation skeleton for the OpenCode iOS client.

This is Tier 4 infrastructure: a CLI performs repeatable simulator operations,
then an agent judges the result from JSON output, XCTest summaries, and
screenshots. V1 is intentionally small. It supports launch, screenshots, device
listing, high-level `configure-server` / `send-prompt` XCTest flows, a
screenshot-backed `tree` command, and an XCTest-backed observation mode for
stable UI assertions. It does not pretend to provide a full accessibility tree
like Android `uiautomator dump`.

## Install / Run

```bash
cd ui_driver
uv venv
source .venv/bin/activate
uv pip install -e '.[dev]'
python -m ui_driver --help
```

## Commands

```bash
python -m ui_driver devices
python -m ui_driver launch --bundle-id com.grapeot.OpenCodeClient
python -m ui_driver screenshot --output artifacts/screen.png
python -m ui_driver tree --screenshot artifacts/screen.png
python -m ui_driver tree \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --result-bundle "artifacts/tier4-observation-$(date +%Y%m%d-%H%M%S).xcresult"
python -m ui_driver configure-server \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --server-url http://127.0.0.1:4096 \
  --username "$OPENCODE_USERNAME" \
  --password-env OPENCODE_PASSWORD \
  --result-bundle "artifacts/configure-server-$(date +%Y%m%d-%H%M%S).xcresult"
python -m ui_driver send-prompt \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --prompt 'Read README.md and summarize it in one sentence.' \
  --result-bundle "artifacts/send-prompt-$(date +%Y%m%d-%H%M%S).xcresult"
python -m ui_driver run-xcuitest \
  --cwd ../OpenCodeClient \
  --project OpenCodeClient.xcodeproj \
  --scheme OpenCodeClient \
  --destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  --only-testing OpenCodeClientUITests/ToolCardsUITests/testToolCardsFixtureRendersFileCardsAndMergedToolCalls \
  --result-bundle "artifacts/read-card-visible-$(date +%Y%m%d-%H%M%S).xcresult"
```

Device selection precedence:

1. `--udid <simulator-udid>`
2. `--device <name>` among booted simulators
3. first booted simulator
4. structured error listing available devices

## Output Contract

All commands write JSON to stdout. Failures preserve raw `simctl` arguments,
exit code, stdout, and stderr.

Without Xcode arguments, `tree` returns screenshot-only observability:

```json
{
  "ok": true,
  "command": "tree",
  "observability": "screenshot_only",
  "nodes": [],
  "compact": [],
  "warnings": ["iOS V1 driver does not provide an accessibility tree yet."]
}
```

With `--project`, `--scheme`, and `--destination`, `tree` runs
`Tier4DriverUITests/testAccessibilityObservationSnapshot` and returns
`observability: xcuitest_accessibility_snapshot`. This is a focused XCTest
bridge, not a full tree dump. For iOS, the XCTest bridge is the preferred stable
surface for exact element identity: it sees accessibility identifiers such as
`chat-input`, `chat-send`, `settings-server-url`, and `toolcard.read.*` without
relying on coordinates.

`configure-server` and `send-prompt` pass URL, username, password, and prompt to
XCTest through a temporary `0600` config file at `/tmp/opencode-ios-tier4-config.json`.
Prefer `--password-env OPENCODE_PASSWORD` over `--password` so secrets are not
placed on the driver command line. Password entry uses paste/keyboard shortcut
rather than `typeText`, and JSON output masks passwords in stdout/stderr tails.
The driver also adds `-parallel-testing-enabled NO` to avoid flaky Xcode UI test
runner clones.

Live validation against a dedicated 4097 OpenCode server has passed for both
`configure-server` and `send-prompt`.

## Tests

```bash
python -m pytest -q
```

Unit tests mock the `simctl` boundary, so they do not require a running
simulator.
