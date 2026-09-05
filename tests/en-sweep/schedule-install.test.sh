#!/usr/bin/env bash
# tests/en-sweep/schedule-install.test.sh
#
# D101: install-sweep-schedule renders a launchd agent for the runner. Runs the
# real script with ENSEMBLE_NO_LAUNCHCTL=1 so nothing is loaded; plist shape is
# asserted on the rendered XML and, where the host has it, on `plutil -lint`.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-sweep schedule install (D101)"

INST="$REPO_ROOT/skills/en-sweep/scripts/install-sweep-schedule"
assert_file_exists "$INST" "installer exists"
[ -x "$INST" ] && pass "installer is executable" || fail "installer is executable"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export ENSEMBLE_HOME_DIR="$T/ensemble" ENSEMBLE_SWEEP_REPOS="$T/repos" ENSEMBLE_LAUNCH_AGENTS="$T/la" ENSEMBLE_NO_LAUNCHCTL=1

# ---- render ----------------------------------------------------------------
weekly=$(bash "$INST" print --cadence weekly --hour 9 --minute 30 --weekday 1 --model fable --effort high 2>&1)
printf '%s' "$weekly" | grep -q '<key>Weekday</key><integer>1</integer>' && pass "weekly renders a Weekday" || fail "weekly renders a Weekday"
printf '%s' "$weekly" | grep -q '<key>Hour</key><integer>9</integer>' && pass "hour is rendered" || fail "hour is rendered"
printf '%s' "$weekly" | grep -q '<key>Minute</key><integer>30</integer>' && pass "minute is rendered" || fail "minute is rendered"
printf '%s' "$weekly" | grep -q 'ensemble-sweep-runner</string>' && pass "the program is the runner" || fail "the program is the runner"
printf '%s' "$weekly" | grep -q '<key>ENSEMBLE_SWEEP_MODEL</key><string>fable</string>' && pass "--model becomes the runner's default model" || fail "--model becomes the runner's default model"
printf '%s' "$weekly" | grep -q '<key>ENSEMBLE_SWEEP_EFFORT</key><string>high</string>' && pass "--effort becomes the runner's default effort" || fail "--effort becomes the runner's default effort"
printf '%s' "$weekly" | grep -q "<key>ENSEMBLE_SWEEP_REPOS</key><string>$T/repos</string>" && pass "the repo list path is pinned in the plist" || fail "the repo list path is pinned"
printf '%s' "$weekly" | grep -q '<key>PATH</key><string>' && pass "a PATH is pinned for the job" || fail "a PATH is pinned for the job"
printf '%s' "$weekly" | grep -q '<key>RunAtLoad</key><false/>' && pass "the job does not fire on load" || fail "the job does not fire on load"

daily=$(bash "$INST" print --cadence daily 2>&1)
printf '%s' "$daily" | grep -q 'Weekday' && fail "daily has no Weekday" || pass "daily has no Weekday"
printf '%s' "$daily" | grep -q 'ENSEMBLE_SWEEP_MODEL' && fail "no model means no model env" || pass "no model means no model env"
monthly=$(bash "$INST" print --cadence monthly --day 3 2>&1)
printf '%s' "$monthly" | grep -q '<key>Day</key><integer>3</integer>' && pass "monthly renders a Day" || fail "monthly renders a Day"

# ---- validation -------------------------------------------------------------
bash "$INST" print --cadence hourly >/dev/null 2>&1; assert_exit_code 2 "$?" "an unknown cadence is refused"
bash "$INST" print --hour 25 >/dev/null 2>&1;       assert_exit_code 2 "$?" "hour 25 is refused"
bash "$INST" print --effort turbo >/dev/null 2>&1;  assert_exit_code 2 "$?" "an unknown effort is refused"
bash "$INST" print --model 'x --bad' >/dev/null 2>&1; assert_exit_code 2 "$?" "a model with a space is refused"

# ---- repo list ---------------------------------------------------------------
( cd "$T" && git init -q r && cd r && git commit -q --allow-empty -m init ) 2>/dev/null
bash "$INST" add-repo "$T/r" >/dev/null 2>&1; assert_exit_code 0 "$?" "add-repo accepts a checkout"
grep -qx "$(cd "$T/r" && pwd -P)" "$T/repos" && pass "the checkout is listed by absolute path" || fail "the checkout is listed by absolute path"
bash "$INST" add-repo "$T/r" >/dev/null 2>&1; [ "$(wc -l < "$T/repos" | tr -d ' ')" = "1" ] && pass "add-repo is idempotent" || fail "add-repo is idempotent"
mkdir -p "$T/notgit"; bash "$INST" add-repo "$T/notgit" >/dev/null 2>&1; assert_exit_code 2 "$?" "a non-checkout is refused"

# ---- install writes the plist without touching launchctl --------------------
bash "$INST" install --cadence weekly >/dev/null 2>&1; assert_exit_code 0 "$?" "install exits 0"
assert_file_exists "$T/la/com.ensemble.sweep.plist" "install writes the plist"
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$T/la/com.ensemble.sweep.plist" >/dev/null 2>&1 && pass "the plist parses (plutil -lint)" || fail "the plist parses (plutil -lint)"
else
  pass "SKIPPED plutil not on this host"
fi
st=$(bash "$INST" status 2>&1)
printf '%s' "$st" | grep -q "plist: $T/la" && pass "status reports the plist" || fail "status reports the plist"
bash "$INST" uninstall >/dev/null 2>&1
[ ! -f "$T/la/com.ensemble.sweep.plist" ] && pass "uninstall removes the plist" || fail "uninstall removes the plist"
[ -f "$T/repos" ] && pass "uninstall leaves the repo list" || fail "uninstall leaves the repo list"

report
