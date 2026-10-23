#!/usr/bin/env bash
# Everything that can be verified from the shell, in one run:
#   1. swift build + swift test   the engine (BaikaKit) and the hub bridge (BaikaAccounts)
#   2. xcodegen generate          the Xcode project, from project.yml
#   3. xcodebuild                 the iOS app, built for the simulator
# The pre-push hook runs this; there is no CI on push or pull request (POLICY section 10).
#
#   ./check.sh            everything
#   ./check.sh quick      step 1 only (seconds)
#   ./check.sh usage      real-usage counters, read by `teyla products`
set -euo pipefail
cd "$(dirname "$0")"

# --- usage mode --------------------------------------------------------------
# Tier owner (POLICY section 17). Stories and audio live on the phone, so the only server-side
# trace is the metered calls in the accounts hub. Read-only.
case "${1:-}" in
  usage)
    command -v teyla >/dev/null || { echo "usage_probe=needs_teyla"; exit 0; }
    rc=0
    teyla probe-sql swgxlydagofazjtlqeiu "select count(*) as ai_calls_7d, coalesce(round(sum(cost_eur)::numeric, 2), 0) as ai_cost_eur_7d, count(distinct coalesce(user_id::text, external_user_id)) as ai_people_7d from accounts.usage where product = 'baika' and at > now() - interval '7 days'" || rc=1
    exit "$rc" ;;  # a failed query is a failed probe: teyla products shows the exit code
esac

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
unset SDKROOT

if ! command -v swift >/dev/null 2>&1; then
  if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
    # A cloud session has no Mac: say so, and the PR gets the needs-mac label.
    echo "skip: swift not available (needs a Mac)"
    exit 0
  fi
  echo "check.sh: swift is not on PATH; install Xcode or its command line tools" >&2
  exit 1
fi

# --- 1. the engine ---------------------------------------------------------------
echo "== swift build"
swift build 2>&1 | tail -3

echo "== swift test"
log="$(mktemp -t baika-test)"
if swift test >"$log" 2>&1; then
  tail -4 "$log"
  rm -f "$log"
else
  status=$?
  echo "--- failing tests ---"
  grep -E "✘|recorded an issue|error:" "$log" || true
  echo "--- tail ---"
  tail -5 "$log"
  echo "full output: $log"
  exit "$status"
fi

if [ "${1:-}" = "quick" ]; then
  echo "OK (quick: the app build was skipped)"
  exit 0
fi

# --- 2 and 3. the app --------------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "check.sh: xcodegen is not on PATH (brew install xcodegen)" >&2
  exit 1
fi
echo "== xcodegen"
xcodegen generate --quiet

echo "== xcodebuild (iOS simulator)"
log="$(mktemp -t baika-build)"
if xcodebuild -project Baika.xcodeproj -scheme Baika \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
     CODE_SIGNING_ALLOWED=NO build >"$log" 2>&1; then
  tail -2 "$log"
  rm -f "$log"
else
  status=$?
  echo "--- build errors ---"
  grep -E "error:" "$log" | sort -u | head -30 || true
  echo "full output: $log"
  exit "$status"
fi

echo "OK"
