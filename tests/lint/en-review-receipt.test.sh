#!/usr/bin/env bash
# tests/lint/en-review-receipt.test.sh
#
# /en-review is receipt-aware (D102). A review that applied nothing used to run
# no tests and a review that applied a fix re-ran them blind, so a review
# followed by a ship verified the same tree twice minutes apart, and en-ship
# could never skip on a review's word. The clauses here pin the shape that
# closes that: ask the receipt first, skip only when nothing was applied, run
# the graph-selected set after a fix, record targeted_tests and never full_suite.
#
# Negative controls at authoring: dropping `--by en-review` from the write line
# went red; adding `full_suite=passed` to it went red; deleting the script copy
# went red; swapping the verify and run sections of the reference went red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review is receipt-aware"

S="$REPO_ROOT/skills/en-review/SKILL.md"
R="$REPO_ROOT/skills/en-review/references/post-review-check.md"
SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
DOC="$REPO_ROOT/skills/en-ship/references/verification-receipt.md"

has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$1")"; }
lacks() { grep -qF -- "$2" "$1" && fail "$3" "found in $(basename "$1")" || pass "$3"; }

# --- the skill carries what it runs -----------------------------------------
[ -x "$REPO_ROOT/skills/en-review/scripts/ensemble-verification-receipt" ] \
  && pass "en-review carries its own executable copy of the receipt script" \
  || fail "en-review carries its own executable copy of the receipt script"
[ -f "$R" ] && pass "the post-review check reference exists" || fail "the post-review check reference exists"
has "$S" 'references/post-review-check.md' "SKILL.md points at the reference"
has "$S" '$SKILL_DIR/scripts/ensemble-verification-receipt' "SKILL.md names its own script copy, not en-ship's"
lacks "$S" 'SKILL_DIR/../en-ship' "SKILL.md reaches into no sibling skill"

# --- verify before running; skip only when nothing was applied ---------------
has "$R" 'verify --requires lint,typecheck,full_suite' "the check asks the receipt what it covers"
has "$R" '--requires lint,typecheck,targeted_tests' "a targeted receipt on the identical tree is honoured"
has "$R" 'only possible when nothing was applied' "a receipt never excuses re-testing a fix"
has "$S" 'only possible when nothing was applied' "SKILL.md states the same"
has "$R" 'surface the refusal reason verbatim' "a refusal is reported, never silent"
has "$R" 'There is no partial credit' "an invalid receipt means run everything"
has "$R" 'Never in `report-only`' "report-only runs and writes nothing"

verify_line=$(grep -n 'Ask whether another layer already proved' "$R" | head -1 | cut -d: -f1)
run_line=$(grep -n '^## 2. Run' "$R" | head -1 | cut -d: -f1)
if [ -n "$verify_line" ] && [ -n "$run_line" ] && [ "$verify_line" -lt "$run_line" ]; then
  pass "the receipt is consulted before anything runs"
else
  fail "the receipt is consulted before anything runs" "verify=$verify_line run=$run_line"
fi

# --- after a fix: the graph-selected set, then record targeted_tests --------
has "$R" 'test_changed_command' "the post-fix run uses the project's graph-selected set"
has "$R" 'selection: graph' "the selection tier is reported"
has "$R" 'Revert the applied edits' "a regression reverts the fix"
has "$R" '--check targeted_tests=passed --base origin/<base> --by en-review' "a passing run records targeted_tests as en-review"
lacks "$R" 'full_suite=passed' "en-review never claims full_suite"
has "$R" 'never `full_suite`' "the reference says so in words"
lacks "$S" 'full_suite=passed' "SKILL.md never claims full_suite either"

# --- the receipt is only written where en-ship will ask about it -------------
has "$R" 'Success on any other target.** Write nothing' "a receipt against another base is not written"

# --- en-ship honours what en-review wrote -------------------------------------
has "$SHIP" 'verify --requires lint,typecheck,full_suite' "en-ship still asks for the suite first"
has "$SHIP" '--requires lint,typecheck,targeted_tests' "en-ship asks for the targeted set second"
has "$DOC" '`/en-review`** reads before its post-review check' "the receipt reference lists en-review as a reader"

report
