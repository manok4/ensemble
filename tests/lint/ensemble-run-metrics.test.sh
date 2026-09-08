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

# --- a flag with no value must not hang (correctness: shift 2 on one arg is a no-op, so the loop spun forever) ---
for args in "start --plan" "start --plan P1 --run-id" "event $f --kind" "event $f --kind note --json"; do
  ( cd "$WORK/repo" && timeout 5 bash "$M" $args >/dev/null 2>"$WORK/err" ); rc=$?
  [ "$rc" -eq 0 ] && grep -q "needs a value" "$WORK/err" && pass "'$args' exits 0 with a stderr note instead of hanging" \
    || fail "'$args' exits 0 with a stderr note instead of hanging" "rc=$rc err=$(cat "$WORK/err")"
done

# --- two starts in the same second get distinct files; a caller-supplied id never truncates (peer 1-4) ---
f1=$(cd "$WORK/repo" && bash "$M" start --plan EN98); f2=$(cd "$WORK/repo" && bash "$M" start --plan EN98)
[ -n "$f1" ] && [ -n "$f2" ] && [ "$f1" != "$f2" ] && pass "two starts in the same second write distinct files" || fail "two starts in the same second write distinct files" "$f1 $f2"
before=$(cat "$f")
out=$(cd "$WORK/repo" && bash "$M" start --plan EN99 --run-id t1 2>"$WORK/err")
[ -z "$out" ] && grep -q "already exists" "$WORK/err" && [ "$before" = "$(cat "$f")" ] \
  && pass "a repeated --run-id refuses to truncate the existing run" || fail "a repeated --run-id refuses to truncate the existing run" "out=$out err=$(cat "$WORK/err")"
# concurrent writers: twenty events from two background writers all land
for i in $(seq 1 10); do (cd "$WORK/repo" && bash "$M" event "$f" --kind note --json "{\"n\":$i}") & done; wait
for i in $(seq 11 20); do (cd "$WORK/repo" && bash "$M" event "$f" --kind note --json "{\"n\":$i}") & done; wait
assert_eq "23" "$(jq '.events | length' "$f")" "twenty concurrent events all land (3 earlier + 20)"
[ -d "$f.lock" ] && fail "no lock directory left behind" || pass "no lock directory left behind"

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

# --- the build kinds (D106) --------------------------------------------------
# /en-build's own cost analyses were reconstructed by hand twice, and the
# persona timings came out Unknown both times because nothing recorded them.
b=$(cd "$WORK/repo" && bash "$M" start --plan EN97 --run-id b1)
(cd "$WORK/repo" && bash "$M" event "$b" --kind unit  --json '{"unit":"U1","event":"start"}' \
                 && bash "$M" event "$b" --kind unit  --json '{"unit":"U1","event":"end","commit":"abc"}' \
                 && bash "$M" event "$b" --kind phase --json '{"phase":"P1","event":"end"}' \
                 && bash "$M" event "$b" --kind suite --json '{"where":"post-build","seconds":226}' \
                 && bash "$M" event "$b" --kind review --json '{"event":"end","reviewer":"cross-agent"}') 2>"$WORK/err"
assert_eq "" "$(cat "$WORK/err")" "unit, phase, suite and review events append silently"
assert_eq "5" "$(jq '.events | length' "$b")" "five build events recorded"
assert_eq "1 dispatches, 0 peer passes, 0 lint runs, 1 units, 1 phases, 1 suite runs" \
  "$( (cd "$WORK/repo" && bash "$M" event "$b" --kind dispatch --json '{}' >/dev/null; bash "$M" summary "$b") )" \
  "the summary appends the build counts after the three it always reports"
# A start event without its end is work still in flight, not a finished unit.
(cd "$WORK/repo" && bash "$M" event "$b" --kind unit --json '{"unit":"U2","event":"start"}')
assert_contains "$(cd "$WORK/repo" && bash "$M" summary "$b")" "1 units" "an unfinished unit is not counted as done"

B="$REPO_ROOT/skills/en-build/SKILL.md"; BR="$REPO_ROOT/skills/en-build/references/run-metrics.md"
grep -qF "scripts/ensemble-run-metrics" "$B" && pass "en-build names the helper" || fail "en-build names the helper"
grep -qF "references/run-metrics.md" "$B" && pass "en-build points at the run-metrics reference" || fail "en-build points at the run-metrics reference"
grep -qF "metrics: <path>" "$B" && pass "the report line is in en-build" || fail "the report line is in en-build"
for k in unit phase suite review; do
  grep -qF -- "--kind $k" "$BR" && pass "the reference documents the $k call point" || fail "the reference documents the $k call point"
done
grep -qF "never estimated" "$BR" && pass "an unmeasured duration is recorded as unmeasured" || fail "an unmeasured duration is recorded as unmeasured"

report
