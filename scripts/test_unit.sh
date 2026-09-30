#!/bin/bash
# Unit test runner with simulator pinning + preflight probe + incremental reuse.
#
# Practices adapted from voiceflow_ios/docs/test.md:
#   - One pinned simulator per repo (UDID persisted in .occlient/simulator-udid);
#     concurrent xcodebuild work from other repos must use a different device.
#   - 15s bounded `simctl io screenshot` preflight: a wedged simulator fails
#     fast with guidance instead of hanging xcodebuild for 10 minutes.
#   - Dedicated derivedDataPath (.occlient/DerivedData) so other agents'
#     xcodebuild runs on the default DerivedData cannot take the build.db lock.
#   - Warm incremental build-for-testing (seconds) before test-without-building;
#     the slow case is a wedged simulator or high machine load, not compilation.
#
# Environment overrides:
#   OPENCODE_TEST_DESTINATION='platform=iOS Simulator,id=<UDID>'  skip pinning
#   OPENCODE_TEST_DERIVED_DATA=/path/to/dd                        dedicated dd
#   OPENCODE_TEST_REBUILD=1                                       nuke products first
#   OPENCODE_TEST_ONLY='OpenCodeClientTests/MySuite'              -only-testing value

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="$REPO_ROOT/.occlient"
UDID_FILE="$STATE_DIR/simulator-udid"
PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj"
SCHEME="OpenCodeClient"
TEST_TARGET="OpenCodeClientTests"
DEST_OVERRIDE="${OPENCODE_TEST_DESTINATION:-}"
DERIVED_DATA="${OPENCODE_TEST_DERIVED_DATA:-$STATE_DIR/DerivedData}"
REBUILD="${OPENCODE_TEST_REBUILD:-0}"
ONLY="${OPENCODE_TEST_ONLY:-}"

mkdir -p "$STATE_DIR"

# --- Machine load warning (warn only) -------------------------------------
CPUS="$(sysctl -n hw.ncpu)"
LOAD1="$(sysctl -n vm.loadavg | awk -F'[ ]+' '{print $2}')"
if awk -v l="$LOAD1" -v c="$CPUS" 'BEGIN { exit !(l > c) }'; then
  echo "warn: machine load $LOAD1 exceeds $CPUS cores; test latency will be high (other xcodebuild work?)"
fi

# --- Simulator pinning ------------------------------------------------------
DEST=""
if [ -n "$DEST_OVERRIDE" ]; then
  DEST="$DEST_OVERRIDE"
else
  UDID=""
  if [ -f "$UDID_FILE" ]; then
    UDID="$(cat "$UDID_FILE" 2>/dev/null || true)"
    if [ -n "$UDID" ] && ! xcrun simctl list devices | grep -q "$UDID"; then
      UDID=""  # device gone (OS update); re-pin below
    fi
  fi
  if [ -z "$UDID" ]; then
    # Prefer an already-booted iPhone; else create/boot the first available one.
    UDID="$(xcrun simctl list devices booted | grep -E '^[[:space:]]+iPhone' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
    if [ -z "$UDID" ]; then
      UDID="$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
      if [ -z "$UDID" ]; then
        echo "error: no available iPhone simulator; run: xcrun simctl create iPhone ..." >&2
        exit 1
      fi
      echo "pinning simulator $UDID (first boot, slow)"
      xcrun simctl boot "$UDID"
    fi
    echo "$UDID" > "$UDID_FILE"
  fi
  # Ensure booted.
  if ! xcrun simctl list devices booted | grep -q "$UDID"; then
    echo "booting pinned simulator $UDID"
    xcrun simctl boot "$UDID"
  fi
  DEST="platform=iOS Simulator,id=$UDID"
fi

# --- Preflight: 15s bounded screenshot probe --------------------------------
PROBE_UDID="${DEST##*,id=}"
PROBE_PNG="$(mktemp -t occlient-sim-probe).png"
if ! timeout 15 xcrun simctl io "$PROBE_UDID" screenshot "$PROBE_PNG" >/dev/null 2>&1; then
  echo "error: simulator unresponsive within 15s (wedged?)." >&2
  echo "fixes, in order:" >&2
  echo "  1. stop concurrent xcodebuild work, wait for load to drop" >&2
  echo "  2. xcrun simctl shutdown <UDID> and rerun this script" >&2
  echo "  3. if concurrency is the norm, point another repo at a different simulator (OPENCODE_TEST_DESTINATION)" >&2
  rm -f "$PROBE_PNG"
  exit 1
fi
rm -f "$PROBE_PNG"

# --- Build (incremental) + test --------------------------------------------
if [ "$REBUILD" = "1" ]; then
  echo "OPENCODE_TEST_REBUILD=1: removing previous products"
  rm -rf "$DERIVED_DATA/Build/Products"
fi

BUILD_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  BUILD_ARGS+=(-only-testing:"$ONLY")
fi

echo "build-for-testing (incremental) ..."
xcodebuild build-for-testing "${BUILD_ARGS[@]}" -quiet

TEST_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  TEST_ARGS+=(-only-testing:"$ONLY")
else
  TEST_ARGS+=(-only-testing:"$TEST_TARGET")
fi

echo "test-without-building ..."
xcodebuild test-without-building "${TEST_ARGS[@]}" 2>&1 | grep -E 'error:|✘|✔|Test Suite|Test run' | tail -60
