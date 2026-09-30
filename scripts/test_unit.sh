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
source "$REPO_ROOT/scripts/lib_simulator.sh"

PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj"
SCHEME="OpenCodeClient"
TEST_TARGET="OpenCodeClientTests"
DERIVED_DATA="${OPENCODE_TEST_DERIVED_DATA:-$REPO_ROOT/.occlient/DerivedData}"
REBUILD="${OPENCODE_TEST_REBUILD:-0}"
ONLY="${OPENCODE_TEST_ONLY:-}"

# --- Build (incremental) + test --------------------------------------------
if [ "$REBUILD" = "1" ]; then
  echo "OPENCODE_TEST_REBUILD=1: removing previous products"
  rm -rf "$DERIVED_DATA/Build/Products"
fi

BUILD_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  BUILD_ARGS+=(-only-testing:"$ONLY")
fi

echo "build-for-testing (incremental) ..."
xcodebuild build-for-testing "${BUILD_ARGS[@]}" -quiet

TEST_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  TEST_ARGS+=(-only-testing:"$ONLY")
else
  TEST_ARGS+=(-only-testing:"$TEST_TARGET")
fi

echo "test-without-building ..."
xcodebuild test-without-building "${TEST_ARGS[@]}" 2>&1 | grep -E 'error:|✘|✔|Test Suite|Test run' | tail -60
