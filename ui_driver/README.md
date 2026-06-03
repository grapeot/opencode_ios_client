# iOS ui_driver

Deterministic `xcrun simctl` operation skeleton for the OpenCode iOS client.

This is Tier 4 infrastructure: a CLI performs repeatable simulator operations,
then an agent judges the result from JSON output and screenshots. V1 is
intentionally small. It supports launch, screenshots, device listing, and a
screenshot-backed `tree` command. It does not yet provide a full accessibility
tree like Android `uiautomator dump`.

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
```

Device selection precedence:

1. `--udid <simulator-udid>`
2. `--device <name>` among booted simulators
3. first booted simulator
4. structured error listing available devices

## Output Contract

All commands write JSON to stdout. Failures preserve raw `simctl` arguments,
exit code, stdout, and stderr.

`tree` currently returns screenshot-only observability:

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

Use screenshots as evidence or pair this driver with XCTest assertions until a
reliable accessibility-tree bridge is added.

## Tests

```bash
python -m pytest -q
```

Unit tests mock the `simctl` boundary, so they do not require a running
simulator.
