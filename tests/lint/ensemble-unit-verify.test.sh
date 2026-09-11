#!/usr/bin/env bash
# tests/lint/ensemble-unit-verify.test.sh
#
# The EN16 build committed three units with a red assertion, and its phase
# boundary missed two content-anchored tests for two hours. Both are the same
# defect: "run the tests covering this unit" was a judgment call, and a judgment
# call under context pressure is a coin flip.
#
# ensemble-test-select resolves the selection mechanically and names the tier
# that produced it; ensemble-unit-verify runs the checks, keeps the output on
# disk, and exits non-zero so the commit can be gated on it. What is guarded
# here is the behaviour a build depends on, not the formatting:
#
#   TIER ORDER          cheap-suite, then graph, then map, then sibling.
#   NEVER SILENTLY EMPTY  a selection that matched nothing exits 3, not 0.
#   THE GATE BITES      a failing check exits 1 and prints the failure.
#   FAIL-SOFT INPUTS    a repo with no AGENTS.md gets a tier that says so.
#
# Negative controls at authoring: making run_check ignore rc turned the gate
# assertion red; returning tier `sibling` for an empty selection turned the
# exit-3 assertion red; dropping the `{files}` guard turned the "skipped when
# nothing changed" assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-test-select and ensemble-unit-verify"

SEL="$REPO_ROOT/skills/en-build/scripts/ensemble-test-select"
VER="$REPO_ROOT/skills/en-build/scripts/ensemble-unit-verify"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# A throwaway project: a source file, its sibling test, a mapped test, and a
# test that anchors on nothing a path heuristic can reach.
P="$WORK/proj"
mkdir -p "$P/src" "$P/lib" "$P/spec"
(cd "$P" && git init -q && git config user.email t@e && git config user.name t)
: > "$P/src/thing.js"; : > "$P/src/thing.test.js"
: > "$P/lib/other.js";  : > "$P/spec/other.spec.js"
sel() { (cd "$P" && bash "$SEL" "$@"); }
val() { printf '%s\n' "$1" | sed -n "s/^$2='\(.*\)'$/\1/p"; }

agents() {  # write AGENTS.md from stdin
  cat > "$P/AGENTS.md"
}

# --- 1. no AGENTS.md at all: fail-soft, and it says which way -----------------
# A selection is only useful if something can run it, so a project that declares
# no test command gets a tier naming that, not a list of paths nobody will run.
out=$(sel --files src/thing.js)
assert_eq "none-declared" "$(val "$out" TEST_SELECT_TIER)" "with no AGENTS.md the tier says nothing is declared"
assert_contains "$(val "$out" TEST_SELECT_REASON)" "no-test-command" "the reason names the missing declaration"

# --- 2. the tier order -------------------------------------------------------
agents <<'MD'
## Project shape

- **Test:** `jest`
- **Lint:** `eslint .`
- **Typecheck:** `<unset>`
MD
out=$(sel --files src/thing.js)
assert_eq "sibling" "$(val "$out" TEST_SELECT_TIER)" "with only a Test command, the sibling heuristic runs"
assert_eq "src/thing.test.js" "$(val "$out" TEST_SELECT_PATHS)" "the sibling is the .test. neighbour"

agents <<'MD'
- **Test:** `jest`

```yaml
test_impact:
  lib/: spec/
```
MD
out=$(sel --files lib/other.js)
assert_eq "impact-map" "$(val "$out" TEST_SELECT_TIER)" "a prefix map beats the sibling heuristic"
assert_eq "spec/" "$(val "$out" TEST_SELECT_PATHS)" "the map's test prefix is the selection"

agents <<'MD'
- **Test:** `jest`

```yaml
test_changed_command: "jest --findRelatedTests"
test_impact:
  lib/: spec/
```
MD
out=$(sel --files lib/other.js)
assert_eq "graph" "$(val "$out" TEST_SELECT_TIER)" "a declared graph command wins over the map"
assert_eq "jest --findRelatedTests" "$(val "$out" TEST_SELECT_COMMAND)" "the graph command is passed through verbatim"

# --- 3. the cheap-suite escape hatch, and that it is opt-in ------------------
# THE EN16 DEFECT. A test that greps a file's content is unreachable from the
# path that changed. A suite this cheap should just run.
agents <<'MD'
- **Test:** `jest`

```yaml
test_full_seconds: 90
test_changed_command: "jest --findRelatedTests"
```
MD
out=$(sel --files src/thing.js)
assert_eq "graph" "$(val "$out" TEST_SELECT_TIER)" "without the flag, a cheap suite changes nothing"
out=$(sel --files src/thing.js --prefer-full-when-cheap)
assert_eq "full-suite" "$(val "$out" TEST_SELECT_TIER)" "with the flag, a cheap suite beats every approximation"
assert_eq "jest" "$(val "$out" TEST_SELECT_COMMAND)" "the full-suite tier runs the project's Test command"
assert_contains "$(val "$out" TEST_SELECT_REASON)" "full-suite-cheap" "the reason names the rule that fired"
out=$(sel --files src/thing.js --prefer-full-when-cheap --cheap-seconds 30)
assert_eq "graph" "$(val "$out" TEST_SELECT_TIER)" "a suite over the threshold is not cheap"

# --- 4. an empty selection is reported as empty, never as a pass -------------
agents <<'MD'
- **Test:** `jest`
MD
: > "$P/src/unpaired.js"
out=$(sel --files src/unpaired.js)
assert_eq "empty" "$(val "$out" TEST_SELECT_TIER)" "a change with no matching test reports empty"

# --- 5. a changed test file always selects itself ----------------------------
out=$(sel --files src/thing.test.js)
assert_eq "src/thing.test.js" "$(val "$out" TEST_SELECT_PATHS)" "a changed test selects itself"

# --- 6. the 60% rule ---------------------------------------------------------
agents <<'MD'
- **Test:** `jest`

```yaml
test_impact:
  lib/: spec/
```
MD
(cd "$P" && git add -A >/dev/null 2>&1)
out=$(sel --files lib/other.js --max-fraction 10)
assert_eq "full-suite" "$(val "$out" TEST_SELECT_TIER)" "a selection past the fraction runs the suite instead"
assert_contains "$(val "$out" TEST_SELECT_REASON)" "of-suite" "the reason names the fraction rule"

# --- 7. unit-verify: the gate bites -----------------------------------------
agents <<'MD'
- **Test:** `false`
- **Lint:** `true`
MD
out=$( (cd "$P" && bash "$VER" --unit U9 --files src/thing.js) 2>&1 ); rc=$?
assert_exit_code 1 $rc "a failing check exits 1 so the commit can be gated on it"
assert_contains "$out" "FAIL" "the failing check is named"
assert_contains "$out" "last 40 lines" "the tail of the failure is printed"
assert_contains "$out" "log:" "the whole log stays on disk, not in the window"

agents <<'MD'
- **Test:** `true`
- **Lint:** `true`
MD
out=$( (cd "$P" && bash "$VER" --unit U9 --files src/thing.js) 2>&1 ); rc=$?
assert_exit_code 0 $rc "every check green exits 0"
assert_contains "$out" "lint: pass" "a passing check reports one line"
assert_not_contains "$out" "last 40 lines" "a green run prints no output tail"

# --- 8. an empty selection is exit 3, not a green light ----------------------
out=$( (cd "$P" && bash "$VER" --unit U9 --files src/unpaired.js) 2>&1 ); rc=$?
assert_exit_code 3 $rc "an empty selection exits 3 rather than passing"
assert_contains "$out" "not a pass" "it says why zero tests is not a pass"

# --- 9. nothing declared: exit 4, so the skill knows to verify by hand -------
agents <<'MD'
- **Test:** `<unset>`
- **Lint:** `<unset>`
- **Typecheck:** `<unset>`
MD
out=$( (cd "$P" && bash "$VER" --unit U9 --files src/thing.js) 2>&1 ); rc=$?
assert_exit_code 4 $rc "a project declaring no commands exits 4"
assert_contains "$out" "nothing verifiable" "it says nothing could be verified"

# --- 10. {files} substitution, and its empty guard --------------------------
agents <<'MD'
- **Test:** `true`
- **Lint:** `false`

```yaml
lint_changed_command: "test -f {files}"
```
MD
out=$( (cd "$P" && bash "$VER" --unit U9 --files src/thing.js) 2>&1 ); rc=$?
assert_exit_code 0 $rc "lint_changed_command wins over the whole-tree Lint command"
assert_contains "$out" "lint: pass" "the substituted command ran"

out=$( (cd "$P" && bash "$VER" --unit U9 --range HEAD..HEAD --no-tests) 2>&1 )
assert_contains "$out" "lint: skipped (nothing changed)" "a {files} command is skipped when nothing changed"

# --- 10b. {tests} and test_paths_command, for a runner that takes no paths ---
# ./tests/run.sh in this repo takes -k <pattern>; the default `<test command>
# <paths>` form hands it a flag it rejects, which is how this key was found.
agents <<'MD'
- **Test:** `jest`
- **Lint:** `true`

```yaml
test_paths_command: "test -f {tests}"
```
MD
out=$( (cd "$P" && bash "$VER" --unit U9 --files src/thing.js) 2>&1 ); rc=$?
assert_exit_code 0 $rc "test_paths_command runs in place of <test command> <paths>"
assert_contains "$out" "tests: pass" "the {tests} substitution ran the selected paths"
agents <<'MD'
- **Test:** `jest`
- **Lint:** `true`

```yaml
test_paths_command: "false {tests}"
```
MD
out=$( (cd "$P" && bash "$VER" --unit U9 --files src/thing.js) 2>&1 ); rc=$?
assert_exit_code 1 $rc "a failing test_paths_command still fails the gate"

# --- 11. usage errors are exit 2, and no flag hangs --------------------------
for args in "--unit" "--files" "--range"; do
  ( cd "$P" && timeout 5 bash "$VER" $args >/dev/null 2>&1 ); rc=$?
  assert_exit_code 2 $rc "'$args' with no value is a usage error, not a hang"
done
( cd "$P" && timeout 5 bash "$VER" >/dev/null 2>&1 ); rc=$?
assert_exit_code 2 $rc "no --unit is a usage error"

# --- the selection is recorded (EN17 U4) -------------------------------------
# The tier a run chose is the raw material for "did test selection narrow
# anything". It is recorded by the helper that decided it, so nothing has to
# remember; outside a run it records nothing at all, which is the property every
# assertion above depends on.
RM="$REPO_ROOT/skills/en-build/scripts/ensemble-run-metrics"
export ENSEMBLE_ANALYTICS_DIR="$WORK/analytics"
ledger() { ( cd "$P" && bash "$RM" "$@" ); }

agents <<'A'
- **Test:** `npm test`
- **Test (changed):** `npm test -- {files}`
A
L=$(ledger start --skill en-build)
out=$(sel --working)
sels=$(grep -c '"kind":"select"' "$L" || true)
assert_eq "1" "$sels" "a selection inside a run records exactly one event"
ev=$(grep '"kind":"select"' "$L" | tail -1)
assert_eq "$(val "$out" TEST_SELECT_TIER)"  "$(printf '%s' "$ev" | jq -r '.tier')"  "the recorded tier is the tier it printed"
assert_eq "$(val "$out" TEST_SELECT_COUNT)" "$(printf '%s' "$ev" | jq -r '.count')" "and the recorded count matches"
assert_eq "$(val "$out" TEST_SELECT_REASON)" "$(printf '%s' "$ev" | jq -r '.reason')" "and the reason verbatim"

# Every tier, including the ones that select nothing: a tier that found no
# tests is exactly the case worth having on disk.
agents <<'A'
- **Test:** `npm test`
A
before=$(grep -c '"kind":"select"' "$L" || true)
sel --working >/dev/null
sel --files "$P/nothing-here.js" >/dev/null
after=$(grep -c '"kind":"select"' "$L" || true)
assert_eq "$((before + 2))" "$after" "an empty or fallback selection records too"

# The stdout contract is byte-identical with and without a run open. Anything
# that eval's this output would break otherwise, and ensemble-unit-verify does.
agents <<'A'
- **Test:** `npm test`
- **Test (changed):** `npm test -- {files}`
A
in_run=$(sel --working)
closed=$(grep -c '"kind":"select"' "$L" || true)
ledger finish "$L"
no_run=$(sel --working)
assert_eq "$in_run" "$no_run" "the stdout contract is identical whether or not a run is open"
assert_eq "$closed" "$(grep -c '"kind":"select"' "$L" || true)" \
  "a selection after the run closed records nothing"
assert_eq "0" "$(wc -c < "$P/.git/ensemble/runs/active" | tr -d ' ')" \
  "and the closed run is off the active stack"

# A carrier missing the sibling helper degrades to silence, not an error.
LONE="$WORK/lone"
mkdir -p "$LONE"
cp "$SEL" "$LONE/ensemble-test-select"
out=$( cd "$P" && bash "$LONE/ensemble-test-select" --working 2>&1 )
rc=$?
assert_exit_code 0 $rc "a carrier without ensemble-run-metrics still exits 0"
assert_eq "$no_run" "$out" "and prints the same selection, with nothing on stderr"

report
