#!/usr/bin/env bash
# tests/evals/grade.test.sh
#
# Offline tests for tests/evals/grade and the run-behavioral dispatch (EN25 U5).
# Behavioral runs spend real tokens and never run in CI; their grader does, here,
# against recorded outputs, so a grading bug cannot hide behind the cost of a run.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="behavioral eval grader"

G="$REPO_ROOT/tests/evals/grade"
RB="$REPO_ROOT/tests/evals/run-behavioral"
CASES="$REPO_ROOT/tests/evals/behavioral"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

field() {  # $1=json $2=python expression over d
  printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print($2)" 2>/dev/null
}
envelope() {  # $1=file, $2=findings json array, [$3=personas json array]
  printf 'preamble\n{"verdict":"revise","personas":%s,"findings":%s,"sub_threshold_findings":[]}\n' "${3:-[\"correctness\"]}" "$2" > "$1"
}
expect() {  # $1=file, $2=defects json, $3=bars json, [$4=personas_include]
  printf '{"version":1,"kind":"review","invocation":"/ensemble:en-review","defects":%s,"bars":%s%s}\n' \
    "$2" "$3" "${4:+,\"personas_include\":$4}" > "$1"
}

TWO='[{"file":"src/a.js","lines":[10,10],"min_severity":"P2"},{"file":"src/a.js","lines":[20,22],"min_severity":"P2"}]'

# --- happy path: the recorded sample for review-logic ------------------------------
out=$("$G" review "$CASES/review-logic/expect.json" "$REPO_ROOT/tests/evals/fixtures/review-output-sample.txt"); rc=$?
assert_exit_code 0 "$rc" "the recorded review-logic sample passes"
assert_eq "1.0" "$(field "$out" 'd["recall"]')" "both planted defects are found"
assert_eq "0.67" "$(field "$out" 'round(d["precision"],2)')" "the unmatched finding lowers precision"

# --- edge cases: line slack, severity floor, one finding per defect ------------------
expect "$T/e.json" "$TWO" '{"min_recall":1.0}'
envelope "$T/o.txt" '[{"severity":"P1","location":"src/a.js:10"},{"severity":"P1","location":"src/a.js:27"}]'
out=$("$G" review "$T/e.json" "$T/o.txt"); rc=$?
assert_eq "0.5" "$(field "$out" 'd["recall"]')" "a finding 5 lines past the range does not match"
assert_exit_code 1 "$rc" "partial recall under min_recall 1.0 fails"
expect "$T/e.json" "$TWO" '{"min_recall":0.5}'
"$G" review "$T/e.json" "$T/o.txt" >/dev/null; rc=$?
assert_exit_code 0 "$rc" "the same partial recall passes at min_recall 0.5"

expect "$T/e.json" "$TWO" '{"min_recall":0.5}'
envelope "$T/o.txt" '[{"severity":"P3","location":"src/a.js:10"}]'
out=$("$G" review "$T/e.json" "$T/o.txt")
assert_eq "0.0" "$(field "$out" 'd["recall"]')" "a finding below min_severity does not match"

envelope "$T/o.txt" '[{"severity":"P1","location":"src/a.js:10-21"}]'
out=$("$G" review "$T/e.json" "$T/o.txt")
assert_eq "0.5" "$(field "$out" 'd["recall"]')" "one finding cannot satisfy two defects"

# --- empty sets and the clean-case cap -----------------------------------------------
expect "$T/e.json" '[]' '{"max_findings":{"at_or_above":"P1","count":0}}'
envelope "$T/o.txt" '[]'
out=$("$G" review "$T/e.json" "$T/o.txt"); rc=$?
assert_exit_code 0 "$rc" "a clean case with no findings passes"
assert_eq "None None" "$(field "$out" 'str(d["recall"])+" "+str(d["precision"])')" "recall and precision are null on empty sets"
envelope "$T/o.txt" '[{"severity":"P1","location":"src/b.js:3","title":"spurious"}]'
out=$("$G" review "$T/e.json" "$T/o.txt"); rc=$?
assert_exit_code 1 "$rc" "a clean case with a P1 finding fails the cap"
assert_contains "$out" "src/b.js:3" "the cap failure names the finding"

# --- personas -----------------------------------------------------------------------
expect "$T/e.json" '[]' '{}' '["security"]'
envelope "$T/o.txt" '[]' '["correctness","testing"]'
out=$("$G" review "$T/e.json" "$T/o.txt"); rc=$?
assert_exit_code 1 "$rc" "a missing required persona fails"
assert_contains "$out" "persona security not dispatched" "the failure names the persona"

# --- no envelope ---------------------------------------------------------------------
printf 'The review could not run.\n' > "$T/o.txt"
out=$("$G" review "$CASES/review-logic/expect.json" "$T/o.txt"); rc=$?
assert_exit_code 1 "$rc" "output with no envelope fails"
assert_contains "$out" "no-envelope" "and says so, never recall 0 with exit 0"

# --- the case contract ---------------------------------------------------------------
for c in review-logic review-security review-test-weakening; do
  "$G" validate "$CASES/$c" >/dev/null; assert_exit_code 0 "$?" "case $c is valid"
done
mk() { rm -rf "$T/case"; mkdir -p "$T/case/base"; echo p > "$T/case/prompt.md"; printf '%s\n' "$1" > "$T/case/expect.json"; }
mk '{"version":1,"kind":"review","invocation":"/x","defects":[]}'
out=$("$G" validate "$T/case"); rc=$?
assert_exit_code 2 "$rc" "a review case with no change/ is invalid"
assert_contains "$out" "change/" "and the error names change/"
mk '{"version":1,"kind":"poem","invocation":"/x"}'
"$G" validate "$T/case" >/dev/null; assert_exit_code 2 "$?" "an unknown kind is invalid"
mk '{"version":1,"kind":"fix","invocation":"/x","test_command":"t","base_from":"review-logic"}'
"$G" validate "$T/case" >/dev/null; assert_exit_code 2 "$?" "base/ with base_from is invalid"

# --- dry run spends nothing ----------------------------------------------------------
out=$(PATH="$T/nobin:/usr/bin:/bin" "$RB" review-logic --dry-run --runs 1 2>&1); rc=$?
assert_exit_code 0 "$rc" "a dry run succeeds without claude on PATH"
assert_contains "$out" "--plugin-dir" "the dry run prints the exact claude command"
assert_contains "$out" "/ensemble:en-review --mode headless --base main --peer" "with the plugin-qualified invocation and mode"

# --- dispatch: a review session that prints prose grades no-envelope ----------------
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "I reviewed it and it looks fine."\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
out=$(PATH="$T/bin:$PATH" EVAL_RESULTS_DIR="$T/results" "$RB" review-logic --runs 1 2>&1); rc=$?
assert_exit_code 1 "$rc" "a review run whose session prints no envelope fails"
assert_contains "$out" "ERROR no-envelope" "and the summary says why"

report
