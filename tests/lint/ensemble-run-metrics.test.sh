#!/usr/bin/env bash
# tests/lint/ensemble-run-metrics.test.sh
#
# EN16 U11. The 2026-09-06 cost analysis was a manual transcript reconstruction.
# This helper leaves a per-run file behind so the next pass reads evidence.
# Two properties matter more than the schema: it never blocks a run (every
# failure is one stderr line and exit 0), and a failed update never truncates
# the file it was updating.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-run-metrics"

M="$REPO_ROOT/skills/en-plan/scripts/ensemble-run-metrics"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

command -v jq >/dev/null 2>&1 || { pass "SKIPPED — jq not installed"; report; }

# --- happy path in a temp git repo ---
mkdir -p "$WORK/repo" && (cd "$WORK/repo" && git init -q)
f=$(cd "$WORK/repo" && bash "$M" start --plan EN99 --run-id t1 2>"$WORK/err")
assert_eq "" "$(cat "$WORK/err")" "start prints nothing to stderr in a git repo"
case "$f" in */repo/.git/ensemble/runs/EN99-t1.json) pass "start writes under .git/ensemble/runs/<plan>-<run>.json" ;; *) fail "start writes under .git/ensemble/runs/" "$f" ;; esac
assert_eq "EN99" "$(jq -r .plan_id "$f")" "the file carries plan_id"
assert_eq "true" "$(jq -r '.started != null and .finished == null' "$f")" "started is set and finished is null"

(cd "$WORK/repo" && bash "$M" event "$f" --kind dispatch --json '{"agent":"repo-research","model":"sonnet"}' \
                  && bash "$M" event "$f" --kind peer --json '{"iteration":1}' \
                  && bash "$M" event "$f" --kind lint --json '{"scope":"docs/plans/active","seconds":5}') 2>"$WORK/err"
assert_eq "" "$(cat "$WORK/err")" "three events append silently"
assert_eq "3" "$(jq '.events | length' "$f")" "three events recorded in order"
assert_eq "dispatch peer lint" "$(jq -r '[.events[].kind] | join(" ")' "$f")" "events keep insertion order"
assert_eq "true" "$(jq -r '.events[0].at != null and .events[0].agent == "repo-research"' "$f")" "an event carries its timestamp and payload"
(cd "$WORK/repo" && bash "$M" finish "$f")
assert_eq "true" "$(jq -r '.finished != null' "$f")" "finish sets finished"
assert_eq "1 dispatches, 1 peer passes, 1 lint runs" "$(cd "$WORK/repo" && bash "$M" summary "$f")" "summary counts by kind"
jq . "$f" >/dev/null 2>&1 && pass "the file is valid JSON end to end" || fail "the file is valid JSON end to end"

# --- bad payloads never truncate the file ---
cp "$f" "$WORK/before.json"
(cd "$WORK/repo" && bash "$M" event "$f" --kind lint --json '["not","an","object"]') 2>"$WORK/err"; rc=$?
assert_exit_code 0 $rc "a non-object payload exits 0"
grep -q "must be a JSON object" "$WORK/err" && pass "a non-object payload is named on stderr" || fail "a non-object payload is named on stderr" "$(cat "$WORK/err")"
cmp -s "$f" "$WORK/before.json" && pass "a rejected payload leaves the file unchanged" || fail "a rejected payload leaves the file unchanged"
(cd "$WORK/repo" && bash "$M" event "$f" --kind bogus --json '{}') 2>"$WORK/err"
grep -q "kind must be" "$WORK/err" && cmp -s "$f" "$WORK/before.json" \
  && pass "an unknown kind is rejected and the file is unchanged" \
  || fail "an unknown kind is rejected and the file is unchanged" "$(cat "$WORK/err")"

# --- outside a git repo: disabled, never fatal ---
mkdir -p "$WORK/nogit"
out=$(cd "$WORK/nogit" && bash "$M" start --plan EN99 2>"$WORK/err"); rc=$?
assert_exit_code 0 $rc "start outside a git repo exits 0"
assert_eq "" "$out" "start outside a git repo prints no path"
grep -q "not inside a git repository" "$WORK/err" && pass "start outside a git repo says why on stderr" || fail "start outside a git repo says why on stderr" "$(cat "$WORK/err")"
(cd "$WORK/nogit" && bash "$M" event "" --kind lint --json '{}' 2>"$WORK/err"); rc=$?
assert_exit_code 0 $rc "event with an empty file argument is a silent no-op"
assert_eq "" "$(cat "$WORK/err")" "event with an empty file argument prints nothing"

# --- the skill names the helper and the reference documents the call points ---
S="$REPO_ROOT/skills/en-plan/SKILL.md"; R="$REPO_ROOT/skills/en-plan/references/run-metrics.md"
grep -qF "scripts/ensemble-run-metrics" "$S" && pass "SKILL.md names the helper" || fail "SKILL.md names the helper"
grep -qF "references/run-metrics.md" "$S" && pass "SKILL.md points at the run-metrics reference" || fail "SKILL.md points at the run-metrics reference"
grep -qF "metrics: <path>" "$S" && pass "the report line is in SKILL.md" || fail "the report line is in SKILL.md"
for k in dispatch peer lint findings; do
  grep -qF -- "--kind $k" "$R" && pass "the reference documents the $k call point" || fail "the reference documents the $k call point"
done
grep -qi "compaction count and dollar cost are not" "$R" && pass "the reference says what is not observable" || fail "the reference says what is not observable"

report
