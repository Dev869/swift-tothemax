#!/usr/bin/env bash
# ui-crawler-max orchestrator: boot sim -> stream console errors -> run crawler -> harvest crashes.
#
# Usage:   crawl.sh APP_PROJECT_DIR SCHEME [DEVICE]
# Example: crawl.sh ~/Projects/MyApp MyApp "iPhone 17 Pro"
#
# Env knobs (all optional):
#   CRAWL_ARTIFACTS   artifacts dir     (default: APP_PROJECT_DIR/crawl-artifacts/<timestamp>)
#   CRAWL_MAX_STEPS   step budget       (default: 150)
#   CRAWL_MAX_MINUTES time budget       (default: 5)
#   CRAWL_DENYLIST    comma-separated destructive labels (default baked into UICrawlerTests.swift)
#   UITEST_TARGET     UI test bundle target name         (default: <SCHEME>UITests)
#   APP_NAME          process name for log predicate + crash matching (default: SCHEME)
set -euo pipefail

PROJECT_DIR="${1:?usage: crawl.sh APP_PROJECT_DIR SCHEME [DEVICE]}"
SCHEME="${2:?usage: crawl.sh APP_PROJECT_DIR SCHEME [DEVICE]}"
DEVICE="${3:-iPhone 17 Pro}"
APP_NAME="${APP_NAME:-$SCHEME}"
UITEST_TARGET="${UITEST_TARGET:-${SCHEME}UITests}"
ART="${CRAWL_ARTIFACTS:-$PROJECT_DIR/crawl-artifacts/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$ART/crashes" "$ART/screens"
touch "$ART/.run-start"   # timestamp marker for post-run crash-report harvest

# --- 1. Resolve device UDID (exact name match, newest available runtime) and boot ---
UDID=$(xcrun simctl list devices available --json | python3 -c "
import json, sys
data = json.load(sys.stdin)['devices']
matches = [d['udid'] for runtime in sorted(data, reverse=True) for d in data[runtime]
           if d['name'] == '$DEVICE']
if not matches:
    sys.exit('no available simulator named: $DEVICE')
print(matches[0])")
echo "==> Simulator: $DEVICE ($UDID)"
xcrun simctl bootstatus "$UDID" -b   # boots if needed, blocks until ready

# --- 2. Start console error stream BEFORE the run (misses nothing) ---
# process == exact app name (NOT CONTAINS: that also matches the <App>UITests-Runner
# process and floods the log); messageType filter because --level has no "error" value.
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate "process == \"$APP_NAME\" AND (messageType == error OR messageType == fault)" \
  > "$ART/console-errors.log" 2>&1 &
LOG_PID=$!
trap 'kill "$LOG_PID" 2>/dev/null || true' EXIT
echo "==> Console error stream: PID $LOG_PID -> $ART/console-errors.log"

# --- 3. Run the crawler. TEST_RUNNER_ vars must be ENVIRONMENT of xcodebuild ---
#     (xcodebuild strips the prefix and injects them into the test runner; passing
#      them as KEY=VALUE build-setting args does NOT reach the runner).
set +e   # don't let pipefail+grep mask xcodebuild's real exit status
(cd "$PROJECT_DIR" && env \
    TEST_RUNNER_CRAWL_ARTIFACTS="$ART" \
    TEST_RUNNER_CRAWL_MAX_STEPS="${CRAWL_MAX_STEPS:-150}" \
    TEST_RUNNER_CRAWL_MAX_MINUTES="${CRAWL_MAX_MINUTES:-5}" \
    ${CRAWL_DENYLIST:+TEST_RUNNER_CRAWL_DENYLIST="$CRAWL_DENYLIST"} \
  xcodebuild test \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -only-testing:"$UITEST_TARGET/UICrawlerTests" \
    -resultBundlePath "$ART/crawl.xcresult" \
  ) 2>&1 | tee "$ART/xcodebuild.log" | grep -E "Test Case|Testing started|error:|BUILD"
XCODEBUILD_STATUS=${PIPESTATUS[0]}
set -e

# --- 4. Stop the log stream ---
kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true
trap - EXIT

# --- 5. Harvest .ips crash reports written since run start that mention the app ---
for DIR in "$HOME/Library/Logs/DiagnosticReports" "$HOME/Library/Logs/DiagnosticReports/Retired"; do
  [ -d "$DIR" ] || continue
  find "$DIR" -name '*.ips' -newer "$ART/.run-start" -maxdepth 1 2>/dev/null | while read -r f; do
    if [[ "$(basename "$f")" == "$APP_NAME"* ]] || grep -q "\"procName\":\"$APP_NAME\"" "$f" 2>/dev/null; then
      cp "$f" "$ART/crashes/" && echo "==> Crash report captured: $(basename "$f")"
    fi
  done
done

# --- 6. Print the artifact tree ---
echo ""
echo "==> Artifacts: $ART"
find "$ART" -type f | sort | sed "s|^$ART|.|"
echo ""
echo "==> Journal steps: $(wc -l < "$ART/journal.jsonl" 2>/dev/null || echo 0)"
echo "==> Screens captured: $(ls "$ART/screens/"*.png 2>/dev/null | wc -l | tr -d ' ')"
echo "==> Crashes (in-test): $(ls "$ART"/crash-*.json 2>/dev/null | wc -l | tr -d ' ')"
echo "==> Crash reports (.ips): $(ls "$ART/crashes/" 2>/dev/null | wc -l | tr -d ' ')"
echo "==> Console errors: $(grep -c . "$ART/console-errors.log" 2>/dev/null || echo 0) lines"
exit "$XCODEBUILD_STATUS"
