#!/bin/bash
# UI test runner: pinned simulator + preflight probe + dedicated DerivedData +
# incremental build-for-testing + test-without-building (voiceflow_ios
# practices, see AGENTS.md "Build/test"). Launch/perf tests are skipped by
# default (slow, not a functional signal): OpenCodeClientUITestsLaunchTests
# and testLaunchPerformance. Include them with
# OPENCODE_UI_TEST_INCLUDE_LAUNCH=1.
#
# Typical steady-state wall time: ~5.5 min for the full suite (2026-09-30,
# pinned iPhone 16 simulator, warm build).
#
# Environment overrides (shared with test_unit.sh via lib_simulator.sh):
#   OPENCODE_TEST_DESTINATION='platform=iOS Simulator,id=<UDID>'  skip pinning
#   OPENCODE_TEST_DERIVED_DATA=/path/to/dd                        dedicated dd
#   OPENCODE_TEST_REBUILD=1                                       nuke products first
#   OPENCODE_UI_TEST_ONLY='OpenCodeClientUITests/MyClass'         narrow -only-testing
#   OPENCODE_UI_TEST_INCLUDE_LAUNCH=1                             also run LaunchTests

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib_simulator.sh"

PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj"
SCHEME="OpenCodeClient"
UI_TARGET="OpenCodeClientUITests"
DERIVED_DATA="${OPENCODE_TEST_DERIVED_DATA:-$REPO_ROOT/.occlient/DerivedData}"
REBUILD="${OPENCODE_TEST_REBUILD:-0}"
ONLY="${OPENCODE_UI_TEST_ONLY:-}"
INCLUDE_LAUNCH="${OPENCODE_UI_TEST_INCLUDE_LAUNCH:-0}"

if [ "$REBUILD" = "1" ]; then
  echo "OPENCODE_TEST_REBUILD=1: removing previous products"
  rm -rf "$DERIVED_DATA/Build/Products"
fi

BUILD_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  BUILD_ARGS+=(-only-testing:"$ONLY")
else
  BUILD_ARGS+=(-only-testing:"$UI_TARGET")
fi

START=$((SECONDS))
echo "build-for-testing (incremental) ..."
xcodebuild build-for-testing "${BUILD_ARGS[@]}" -quiet

echo "test-without-building ..."
TEST_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -destination "$SIM_DEST" -derivedDataPath "$DERIVED_DATA")
if [ -n "$ONLY" ]; then
  TEST_ARGS+=(-only-testing:"$ONLY")
else
  TEST_ARGS+=(-only-testing:"$UI_TARGET")
  if [ "$INCLUDE_LAUNCH" != "1" ]; then
    TEST_ARGS+=(-skip-testing:"$UI_TARGET/OpenCodeClientUITestsLaunchTests")
    # testLaunchPerformance lives in the main class, not the LaunchTests class.
    TEST_ARGS+=(-skip-testing:"$UI_TARGET/OpenCodeClientUITests/testLaunchPerformance")
  fi
fi
xcodebuild test-without-building "${TEST_ARGS[@]}" 2>&1 | grep -E 'Test Case|Test Suite|error:|TEST' | tail -80
echo "elapsed: $((SECONDS - START))s"
