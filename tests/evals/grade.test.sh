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

# --- overlapping windows: a matching, not first-fit ----------------------------------
OVER='[{"file":"src/a.js","lines":[10,10],"min_severity":"P2"},{"file":"src/a.js","lines":[14,14],"min_severity":"P2"}]'
expect "$T/e.json" "$OVER" '{"min_recall":1.0}'
envelope "$T/o.txt" '[{"severity":"P1","location":"src/a.js:13"},{"severity":"P1","location":"src/a.js:10"}]'
out=$("$G" review "$T/e.json" "$T/o.txt"); rc=$?
assert_exit_code 0 "$rc" "a finding in both windows does not steal the defect another finding was needed for"

# --- match: one finding cannot be credited for two defects on the same lines ---------
expect "$T/e.json" '[{"file":"src/i.js","lines":[5,5],"min_severity":"P1","match":"sql"},{"file":"src/i.js","lines":[5,7],"min_severity":"P1","match":"owner"}]' '{"min_recall":1.0}'
envelope "$T/o.txt" '[{"severity":"P0","location":"src/i.js:5","title":"SQL injection"},{"severity":"P1","location":"src/i.js:6","title":"Also SQL injection, via the id"}]'
out=$("$G" review "$T/e.json" "$T/o.txt"); rc=$?
assert_exit_code 1 "$rc" "two findings about one defect do not cover a second defect with its own match"
assert_eq "0.5" "$(field "$out" 'd["recall"]')" "recall counts the SQL defect only"

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

EVAL_MODE=peer "$G" review "$T/e.json" "$T/o.txt" >/dev/null; rc=$?
assert_exit_code 0 "$rc" "under --peer no persona runs, so personas_include is not checked"

# --- the review-new-rows case against a recorded envelope ---------------------------
cat > "$T/nr.txt" <<'JSON'
{"verdict":"revise","personas":["correctness","testing","maintainability","standards","security"],"findings":[
 {"severity":"P0","location":"src/summarize.js:14","title":"Model output interpolated into SQL"},
 {"severity":"P1","location":"package.json:8","title":"lodahs looks like a typosquat of lodash, with an install script"},
 {"severity":"P0","location":"src/cleanup.js:8","title":"Recursive delete of a path built from the request body"},
 {"severity":"P2","location":"src/signup.js:4","title":"Email sent to analytics"}],"sub_threshold_findings":[]}
JSON
out=$("$G" review "$CASES/review-new-rows/expect.json" "$T/nr.txt"); rc=$?
assert_exit_code 0 "$rc" "a recorded review-new-rows envelope with all four areas passes"
envelope "$T/nr.txt" '[{"severity":"P0","location":"src/summarize.js:14"},{"severity":"P1","location":"package.json:8"}]' '["security"]'
out=$("$G" review "$CASES/review-new-rows/expect.json" "$T/nr.txt"); rc=$?
assert_exit_code 1 "$rc" "missing two of the four areas fails"
assert_contains "$out" "recall 0.50 under 0.75" "on recall, not on a parse error"

# --- no envelope ---------------------------------------------------------------------
printf 'The review could not run.\n' > "$T/o.txt"
out=$("$G" review "$CASES/review-logic/expect.json" "$T/o.txt"); rc=$?
assert_exit_code 1 "$rc" "output with no envelope fails"
assert_contains "$out" "no-envelope" "and says so, never recall 0 with exit 0"

# --- no arguments prints a usage line ---------------------------------------------
out=$("$G" 2>&1); rc=$?
assert_exit_code 2 "$rc" "no arguments is a usage error"
assert_contains "$out" "usage: grade validate" "and prints the real usage, not a docstring fragment"

# --- the case contract ---------------------------------------------------------------
for c in review-logic review-security review-test-weakening review-new-rows review-clean fix-plain fix-pressure fix-docs-grounding fix-internal-only fix-wide-change fix-max-tokens fix-real-token plan-cli-additive plan-idempotent-endpoint plan-internal-only; do
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
out=$("$RB" fix-docs-grounding --dry-run --runs 1 2>&1)
assert_contains "$out" "--strict-mcp-config" "by default the session loads no MCP servers"
out=$("$RB" fix-docs-grounding --dry-run --runs 1 --with-user-mcp 2>&1)
assert_not_contains "$out" "--strict-mcp-config" "--with-user-mcp loads the operator's servers"

# --- grade fix: revert the source, keep the tests -------------------------------------
fixrepo() {  # $1=name $2=variant -> path. main: a counter that adds 1; variant edits the branch
  d="$T/$1"; mkdir -p "$d/src" "$d/test"
  (
    cd "$d" && git init -q -b main . && git config user.email t@example.com && git config user.name t
    printf 'exports.inc = (n) => n + 1;\n' > src/count.js
    printf "const t=require('node:test');const a=require('node:assert');const {inc}=require('../src/count');\nt('inc',()=>a.strictEqual(inc(1),2));\n" > test/count.test.js
    git add -A && git commit -qm base && git checkout -qb fix
    case "$2" in
      good) printf 'exports.inc = (n) => n + 1;\nexports.dbl = (n) => n * 2;\n' > src/count.js
            printf "const t=require('node:test');const a=require('node:assert');const {dbl}=require('../src/count');\nt('dbl',()=>a.strictEqual(dbl(3),6));\n" > test/dbl.test.js ;;
      vacuous) printf 'exports.inc = (n) => n + 1;\nexports.dbl = (n) => n * 2;\n' > src/count.js
            printf "const t=require('node:test');const a=require('node:assert');\nt('dbl',()=>a.ok(true));\n" > test/dbl.test.js ;;
      notest) printf 'exports.inc = (n) => n + 1;\nexports.dbl = (n) => n * 2;\n' > src/count.js ;;
      modified) printf 'exports.inc = (n) => n + 1;\nexports.dbl = (n) => n * 2;\n' > src/count.js
            printf "const t=require('node:test');const a=require('node:assert');const {inc,dbl}=require('../src/count');\nt('inc',()=>a.strictEqual(inc(1),2));\nt('dbl',()=>a.strictEqual(dbl(3),6));\n" > test/count.test.js ;;
    esac
    git add -A && git commit -qm "fix" -m "Docs: node@22 https://nodejs.org/api/test.html"
  ) >/dev/null 2>&1
  printf '%s\n' "$d"
}
printf '{"version":1,"kind":"fix","invocation":"/x","test_command":"node --test"}\n' > "$T/fix.json"
if command -v node >/dev/null 2>&1; then
  GOOD=$(fixrepo good good)   # grade fix never mutates the repo it reads, so one serves every check
  out=$("$G" fix "$T/fix.json" "$GOOD"); rc=$?
  assert_exit_code 0 "$rc" "a test that fails on reverted source and passes on the fix grades pass"
  out=$("$G" fix "$T/fix.json" "$(fixrepo vacuous vacuous)"); rc=$?
  assert_exit_code 1 "$rc" "a test that passes on reverted source fails"
  assert_eq "False" "$(field "$out" 'd["red_on_revert"]')" "and says red_on_revert is false"
  out=$("$G" fix "$T/fix.json" "$(fixrepo notest notest)"); rc=$?
  assert_exit_code 1 "$rc" "a fix with no test fails"
  assert_eq "False 1" "$(field "$out" 'str(d["test_added"])+" "+str(d["commits"])')" "and reports test_added false with the commit count"
  out=$("$G" fix "$T/fix.json" "$(fixrepo modified modified)"); rc=$?
  assert_exit_code 0 "$rc" "a modified existing test counts as the fix's test"
  # trailers
  # A case whose right outcome is a stop: any commit means the run went ahead.
  printf '{"version":1,"kind":"fix","invocation":"/x","test_command":"node --test","stops":true}\n' > "$T/stop.json"
  "$G" fix "$T/stop.json" "$GOOD" >/dev/null; assert_exit_code 1 "$?" "a stops case with a commit fails"
  git -C "$GOOD" checkout -q main
  "$G" fix "$T/stop.json" "$GOOD" >/dev/null; assert_exit_code 0 "$?" "a stops case with no commit passes"
  git -C "$GOOD" checkout -q fix
  printf '{"version":1,"kind":"fix","invocation":"/x","test_command":"node --test","trailers":[{"key":"Docs","match":"node"}]}\n' > "$T/tr.json"
  "$G" fix "$T/tr.json" "$GOOD" >/dev/null; assert_exit_code 0 "$?" "a matching Docs trailer passes"
  printf '{"version":1,"kind":"fix","invocation":"/x","test_command":"node --test","trailers":[{"key":"Docs","match":"stripe"}]}\n' > "$T/tr.json"
  "$G" fix "$T/tr.json" "$GOOD" >/dev/null; assert_exit_code 1 "$?" "a Docs trailer that does not match fails"
  printf '{"version":1,"kind":"fix","invocation":"/x","test_command":"node --test","trailers":[{"key":"Docs","absent":true}]}\n' > "$T/tr.json"
  "$G" fix "$T/tr.json" "$GOOD" >/dev/null; assert_exit_code 1 "$?" "a Docs trailer where none is wanted fails"
else
  fail "node is required for the grade fix tests"
fi

# --- grade plan: lint the plan, then check its units ---------------------------------
planrepo() {  # $1=name, stdin: sed program applied to the sample plan -> repo path
  d="$T/$1"; mkdir -p "$d/docs/plans/active"
  ( cd "$d" && git init -q . ) >/dev/null 2>&1
  sed "$(cat)" "$REPO_ROOT/tests/evals/fixtures/plan-sample.md" > "$d/docs/plans/active/EN01-feature_rename.md"
  printf '%s\n' "$d"
}
pcheck() {  # $1=repo $2=plan_checks json -> sets out, rc. Lint runs only where a test reads it.
  printf '{"version":1,"kind":"plan","invocation":"/x","plan_checks":%s}\n' "$2" > "$T/p.json"
  out=$(EVAL_SKIP_LINT="${LINT_OFF:-1}" "$G" plan "$T/p.json" "$1"); rc=$?
}
P=$(echo 's/^//' | planrepo plan-ok)
LINT_OFF=0 pcheck "$P" '[{"unit_matching":"dual","before":"drop"},{"unit_matching":"drop","risk":"destructive","last":true}]'
assert_exit_code 0 "$rc" "a lint-clean plan meeting its ordering, risk and last checks passes"
pcheck "$P" '[{"unit_matching":"drop","before":"dual"}]'
assert_exit_code 1 "$rc" "a unit listed after its before target fails"
assert_contains "$out" "U3 is not before U2" "and names the order"
pcheck "$P" '[{"unit_matching":"drain","before":"backfill"}]'
assert_contains "$out" "unit-not-found drain" "a unit pattern matching nothing fails as unit-not-found"
pcheck "$P" '[{"unit_matching":"expand","before":"column"}]'
assert_exit_code 0 "$rc" "with several matches, before compares the first unit of each pattern"
pcheck "$P" '[{"unit_matching":"column","before":"expand"}]'
assert_contains "$out" "U2 is not before U1" "and fails when the first match comes later"
pcheck "$P" '[{"unit_matching":"column","risk":"destructive"}]'
assert_contains "$out" "U2 risk is medium, want destructive" "risk must hold for every matching unit"
pcheck "$P" '[{"unit_matching":"expand","must_contain":["Interfaces:"]}]'
assert_exit_code 1 "$rc" "a matching unit missing a required string fails"
assert_contains "$out" "U1 missing" "and names the unit"
pcheck "$P" '[{"unit_matching":"expand","must_contain":["Rename a column"],"scope":"plan"}]'
assert_exit_code 0 "$rc" "scope plan finds a string the plan settles outside the unit"
pcheck "$P" '[{"unit_matching":"expand","must_contain":["idempotency"],"scope":"plan"}]'
assert_contains "$out" "plan missing" "scope plan still fails when the whole plan lacks it"
P=$(echo 's/^- \*\*Risk:\*\* destructive$/- **Risk:** high/' | planrepo plan-high)
pcheck "$P" '[{"unit_matching":"drop","risk":"destructive","last":true}]'
assert_contains "$out" "U3 risk is high, want destructive" "a drop planned below destructive fails naming the risk"
P=$(echo 's|`src/users.js` (create)|`src/users.js` (modify)|' | planrepo plan-lint)
LINT_OFF=0 pcheck "$P" '[]'
assert_exit_code 1 "$rc" "a plan with a P1 lint finding fails"
assert_contains "$out" "unit.files-missing" "and carries the lint rule"
mkdir -p "$T/noplan"
pcheck "$T/noplan" '[]'
assert_contains "$out" "expected one plan file" "a run that wrote no plan fails"

# --- grade judge: verdicts must quote the transcript --------------------------------
printf 'I wrote test/duration.test.js first and it failed, then fixed the regex.\n' > "$T/session.txt"
printf '{"version":1,"kind":"fix","invocation":"/x","test_command":"t","judge":[{"id":"no-skip","expectation":"wrote the test"}]}\n' > "$T/j.json"
out=$(EVAL_JUDGE_CMD="cat >/dev/null; echo '{\"pass\": true, \"evidence\": \"wrote test/duration.test.js first\"}'" "$G" judge "$T/j.json" "$T/session.txt"); rc=$?
assert_exit_code 0 "$rc" "a verdict quoting the transcript is accepted"
out=$(EVAL_JUDGE_CMD="cat >/dev/null; echo '{\"pass\": true, \"evidence\": \"the tests were all green\"}'" "$G" judge "$T/j.json" "$T/session.txt"); rc=$?
assert_exit_code 1 "$rc" "a verdict whose evidence is not in the transcript is rejected"
assert_contains "$out" "invalid-evidence" "as invalid-evidence"
out=$(EVAL_JUDGE_CMD="cat >/dev/null; echo 'looks good to me'" "$G" judge "$T/j.json" "$T/session.txt"); rc=$?
assert_exit_code 1 "$rc" "a judge reply with no verdict fails"

# --- dispatch: a review session that prints prose grades no-envelope ----------------
mkdir -p "$T/bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/claude-argv"\necho "I reviewed it and it looks fine."\n' "$T" > "$T/bin/claude"; chmod +x "$T/bin/claude"
out=$(PATH="$T/bin:$PATH" EVAL_RESULTS_DIR="$T/results" "$RB" review-logic --runs 1 2>&1); rc=$?
assert_exit_code 1 "$rc" "a review run whose session prints no envelope fails"
assert_contains "$out" "FAIL no-envelope" "and the summary says why"
argv=$(cat "$T/claude-argv" 2>/dev/null)
assert_contains "$argv" "--plugin-dir" "the session was launched with this checkout as the plugin"
assert_contains "$argv" "/ensemble:en-review --mode headless --base main --peer" "and the plugin-qualified invocation"
assert_contains "$argv" "--strict-mcp-config" "with no MCP servers by default"

# --- dispatch: a case with a judge runs it ----------------------------------------
out=$(PATH="$T/bin:$PATH" EVAL_RESULTS_DIR="$T/results" EVAL_JUDGE_CMD="cat >/dev/null; echo nothing" "$RB" fix-pressure --runs 1 2>&1)
assert_contains "$out" "judge no-skip: invalid-verdict" "a case's judge entries reach the judge"

# --- dispatch: a fix session expects no envelope; it reaches grade fix ---------------
out=$(PATH="$T/bin:$PATH" EVAL_RESULTS_DIR="$T/results" "$RB" fix-plain --runs 1 2>&1); rc=$?
assert_exit_code 1 "$rc" "a fix run that changed nothing fails"
assert_contains "$out" "no test added" "it fails on the fix grader's facts, not on a missing envelope"
assert_not_contains "$out" "no-envelope" "a fix case never asks for an envelope"

# --- the fix grader and the floor guard agree on what a test file is ---------------
# Skills are self-contained, so the pattern is copied; this pins the copies.
fg=$(grep -E '^TEST_PATH = re.compile' "$REPO_ROOT/skills/en-ship/scripts/ensemble-floor-guard")
gr=$(grep -E '^TEST_PATH = re.compile' "$G")
assert_eq "$fg" "$gr" "grade's TEST_PATH matches the floor guard's"

report
