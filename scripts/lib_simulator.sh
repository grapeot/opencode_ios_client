#!/bin/bash
# Shared simulator pinning + preflight for test runners (sourced, not executed).
# Requires: REPO_ROOT set by the caller.
# Sets: SIM_DEST ('platform=iOS Simulator,id=<UDID>'), SIM_UDID.
#
# Practices adapted from voiceflow_ios/docs/test.md:
#   - one pinned simulator per repo (UDID in .occlient/simulator-udid);
#     concurrent xcodebuild work from other repos must use its own device;
#   - 15s bounded `simctl io screenshot` preflight: a wedged simulator fails
#     fast with guidance instead of hanging xcodebuild for 10 minutes.

OC_STATE_DIR="${OC_STATE_DIR:-$REPO_ROOT/.occlient}"
OC_UDID_FILE="$OC_STATE_DIR/simulator-udid"
OC_DEST_OVERRIDE="${OPENCODE_TEST_DESTINATION:-}"

mkdir -p "$OC_STATE_DIR"

# --- Machine load warning (warn only) ---------------------------------------
CPUS="$(sysctl -n hw.ncpu)"
LOAD1="$(sysctl -n vm.loadavg | awk -F'[ ]+' '{print $2}')"
if awk -v l="$LOAD1" -v c="$CPUS" 'BEGIN { exit !(l > c) }'; then
  echo "warn: machine load $LOAD1 exceeds $CPUS cores; test latency will be high (other xcodebuild work?)"
fi

# --- Simulator pinning --------------------------------------------------------
if [ -n "$OC_DEST_OVERRIDE" ]; then
  SIM_DEST="$OC_DEST_OVERRIDE"
  SIM_UDID="${SIM_DEST##*,id=}"
else
  SIM_UDID=""
  if [ -f "$OC_UDID_FILE" ]; then
    SIM_UDID="$(cat "$OC_UDID_FILE" 2>/dev/null || true)"
    if [ -n "$SIM_UDID" ] && ! xcrun simctl list devices | grep -q "$SIM_UDID"; then
      SIM_UDID=""  # device gone (OS update); re-pin below
    fi
  fi
  if [ -z "$SIM_UDID" ]; then
    # Prefer an already-booted iPhone; else create/boot the first available one.
    SIM_UDID="$(xcrun simctl list devices booted | grep -E '^[[:space:]]+iPhone' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
    if [ -z "$SIM_UDID" ]; then
      SIM_UDID="$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
      if [ -z "$SIM_UDID" ]; then
        echo "error: no available iPhone simulator; run: xcrun simctl create iPhone ..." >&2
        exit 1
      fi
      echo "pinning simulator $SIM_UDID (first boot, slow)"
      xcrun simctl boot "$SIM_UDID"
    fi
    echo "$SIM_UDID" > "$OC_UDID_FILE"
  fi
  if ! xcrun simctl list devices booted | grep -q "$SIM_UDID"; then
    echo "booting pinned simulator $SIM_UDID"
    xcrun simctl boot "$SIM_UDID"
  fi
  SIM_DEST="platform=iOS Simulator,id=$SIM_UDID"
fi

# --- Preflight: 15s bounded screenshot probe ---------------------------------
PROBE_PNG="$(mktemp -t occlient-sim-probe).png"
if ! timeout 15 xcrun simctl io "$SIM_UDID" screenshot "$PROBE_PNG" >/dev/null 2>&1; then
  echo "error: simulator unresponsive within 15s (wedged?)." >&2
  echo "fixes, in order:" >&2
  echo "  1. stop concurrent xcodebuild work, wait for load to drop" >&2
  echo "  2. xcrun simctl shutdown $SIM_UDID and rerun this script" >&2
  echo "  3. if concurrency is the norm, point another repo at a different simulator (OPENCODE_TEST_DESTINATION)" >&2
  rm -f "$PROBE_PNG"
  exit 1
fi
rm -f "$PROBE_PNG"
