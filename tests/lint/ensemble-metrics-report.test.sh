#!/usr/bin/env bash
# tests/lint/ensemble-metrics-report.test.sh
#
# Three named reports, not a query tool. Each encodes how to read its own
# numbers, which is the whole reason they are named rather than generic.
#
# Guarded here:
#
#   BOTH GENERATIONS      rotation moves history into <repo>.jsonl.1, so a
#                         report that reads one file loses everything before
#                         the last rotation. Each line is counted exactly once.
#   NULL IS NOT ZERO      a run that recorded no outcome is EXCLUDED from
#                         --peer-value and said so, never averaged in as a zero.
#   A DISTRIBUTION        --peer-value prints per-run rows and a histogram. A
#                         peer that finds nothing on easy diffs and everything
#                         on hard ones averages to mediocre, so the single
#                         ratio is the one shape that cannot answer this.
#   JUNK IS SURVIVABLE    a truncated final line is skipped and counted, never
#                         a traceback.
#   IT NEVER WRITES       the reports read; the isolation guard covers writers,
#                         and this one must not become one.
#
# Negative controls at authoring: reading only <repo>.jsonl turned the rotation
# assertion red; counting outcome-null runs as zeroes turned the exclusion
# assertion red; dropping the small-sample threshold turned the note assertions
# red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-metrics named reports"

M="$REPO_ROOT/bin/ensemble-metrics"
assert_file_exists "$M" "the report tool exists"
[ -x "$M" ] && pass "the report tool is executable" || fail "the report tool is executable"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
A="$WORK/analytics"; mkdir -p "$A"
R="$A/proj.jsonl"
m() { "$M" "$@" --repo proj --analytics-dir "$A"; }

line() {  # <run_id> <skill> <duration> <outcome-json|null> <select-json|null>
  printf '{"schema":1,"run_id":"%s","skill":"%s","plan_id":null,"repo":"proj","parent_run_id":null,' "$1" "$2"
  printf '"started_at":"2026-09-10T00:00:00Z","ended_at":"2026-09-10T00:01:00Z","duration_s":%s,' "$3"
  printf '"counts":{"peer":2,"lint":1},"outcome":%s,"detail":{"select":%s,"peer":[]},"dropped":0}\n' "$4" "$5"
}

O() { printf '{"findings_total":%s,"peer_only":%s,"corroborated":%s,"host_only":%s}' "$1" "$2" "$3" "$4"; }
S() { printf '{"tier":"%s","count":%s,"total":%s}' "$1" "$2" "$3"; }

# --- empty and absent stores -------------------------------------------------
out=$(m --time); rc=$?
assert_exit_code 0 $rc "an absent store exits 0"
assert_contains "$out" "no data yet" "and says there is no data"
: > "$R"
out=$(m --time); rc=$?
assert_exit_code 0 $rc "an empty file exits 0"
assert_contains "$out" "no data yet" "and says the same"

# --- twelve runs across three skills ----------------------------------------
: > "$R"
for i in 1 2 3 4; do line "a$i" en-review "$((i * 10))" "$(O 9 3 4 2)" "$(S graph 4 260)" >> "$R"; done
for i in 1 2 3 4; do line "b$i" en-build  "$((i * 100))" null "$(S full-suite 260 260)" >> "$R"; done
for i in 1 2 3 4; do line "c$i" en-ship   "5" "$(O 0 0 0 0)" null >> "$R"; done

out=$(m --time)
assert_contains "$out" "12 finished run(s)" "--time counts every run"
j=$(m --time --json)
assert_eq "12" "$(printf '%s' "$j" | jq -r '.runs')" "and the same in JSON"
assert_eq "25" "$(printf '%s' "$j" | jq -r '.skills[] | select(.skill=="en-review") | .median_s')" \
  "the median is the hand-computed value (10,20,30,40 -> 25)"
assert_eq "400" "$(printf '%s' "$j" | jq -r '.skills[] | select(.skill=="en-build") | .max_s')" \
  "and the max is the largest duration"
assert_eq "8" "$(printf '%s' "$j" | jq -r '.skills[] | select(.skill=="en-review") | .counts.peer')" \
  "per-kind event counts sum across a skill's runs"

# --- peer-value: a distribution, and null is not zero ------------------------
j=$(m --peer-value --json)
assert_eq "8" "$(printf '%s' "$j" | jq -r '.runs_scored')" "only runs with an outcome are scored"
assert_eq "4" "$(printf '%s' "$j" | jq -r '.runs_without_outcome')" \
  "and the outcome-null runs are excluded, with a count"
assert_eq "8" "$(printf '%s' "$j" | jq -r '[.peer_only_histogram[]] | add')" \
  "the histogram buckets sum to the scored runs"
assert_eq "4" "$(printf '%s' "$j" | jq -r '.runs_where_peer_found_nothing')" \
  "and it names how often the peer found nothing new"
out=$(m --peer-value)
assert_contains "$out" "peer-only findings per run" "the text report prints the distribution"
assert_contains "$out" "read the spread, not an average" "and says why a single ratio misleads"

# --- selection ---------------------------------------------------------------
j=$(m --selection --json)
assert_eq "4" "$(printf '%s' "$j" | jq -r '.tiers[] | select(.tier=="graph") | .runs')" \
  "each tier carries its run count"
assert_eq "0.02" "$(printf '%s' "$j" | jq -r '.tiers[] | select(.tier=="graph") | .mean_ratio * 100 | round / 100')" \
  "and the fraction of the suite it selected (16 of 1040)"
assert_eq "true" "$(printf '%s' "$j" | jq -r '.tiers[] | select(.tier=="full-suite") | .mean_ratio == 1')" \
  "full-suite selects everything, which is the number that makes narrowing visible"

# --- both generations, each line exactly once --------------------------------
mv "$R" "$A/proj.jsonl.1"
: > "$R"
line z1 en-qa 7 null null >> "$R"
j=$(m --time --json)
assert_eq "13" "$(printf '%s' "$j" | jq -r '.runs')" \
  "a rotated generation is read alongside the current one"
# `.runs`, not the entry count: report_time groups per skill, so the cardinality
# is 1 whether the store is read once or twice. A double read raises `.runs`.
assert_eq "1" "$(printf '%s' "$j" | jq -r '.skills[] | select(.skill=="en-qa") | .runs')" \
  "and neither file is read twice"

# --- junk survives -----------------------------------------------------------
printf 'this is not json\n' >> "$R"
printf '{"schema":1,"run_id":"trunc","skill":"en-b' >> "$R"
out=$(m --time 2>&1); rc=$?
assert_exit_code 0 $rc "a truncated line and a junk line are not fatal"
assert_contains "$out" "2 unparseable line(s) skipped" "and the skip is counted, not hidden"
assert_not_contains "$out" "Traceback" "with no traceback"
j=$(m --time --json)
assert_eq "13" "$(printf '%s' "$j" | jq -r '.runs')" "the valid lines are still reported"

# --- small-sample note -------------------------------------------------------
: > "$R"; rm -f "$A/proj.jsonl.1"
for i in 1 2 3; do line "s$i" en-build 10 null null >> "$R"; done
assert_contains "$(m --time)" "is an anecdote" "under five runs the report says so"
for i in 4 5 6; do line "s$i" en-build 10 null null >> "$R"; done
assert_not_contains "$(m --time)" "is an anecdote" "at five or more it does not"

# --- flags and shape ---------------------------------------------------------
m --nonsense >/dev/null 2>&1
assert_exit_code 2 $? "an unknown flag exits 2"
"$M" --analytics-dir "$A" --repo proj >/dev/null 2>&1
assert_exit_code 2 $? "naming no report exits 2"
for r in --peer-value --time --selection; do
  m "$r" --json | jq -e . >/dev/null 2>&1 \
    && pass "$r --json is parseable" || fail "$r --json is parseable"
done

# --- it reads, it never writes ----------------------------------------------
store_hash() { for f in $(find "$A" -type f | sort); do hash_file "$f"; done; }
before=$(store_hash)
m --peer-value >/dev/null; m --time >/dev/null; m --selection >/dev/null
assert_eq "$before" "$(store_hash)" \
  "running every report leaves the store byte-unchanged"

report
