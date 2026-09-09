#!/usr/bin/env bash
# tests/lint/ensemble-pr-body.test.sh
#
# Three of the body's four sections are derived from artifacts that already
# exist when the PR opens: the commit list, the receipt, the plan path. Leaving
# the composition to prose meant retyping them, and retyping is where the Test
# plan section goes wrong.
#
# THE ASSERTION THAT MATTERS: with no test result, the body says so and offers
# nothing else. An agent holding a changed-file list and no result will write a
# plausible checklist, and a checkbox nobody executed reads to a reviewer
# exactly like one that passed. That is a claim without evidence, and it is
# worse than an empty section because it displaces the question.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-pr-body"

B="$REPO_ROOT/skills/en-ship/scripts/ensemble-pr-body"
assert_file_exists "$B" "the pr-body helper exists"
[ -x "$B" ] && pass "the pr-body helper is executable" || fail "the pr-body helper is executable"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
D="$WORK/repo"; mkdir -p "$D"
(
  cd "$D" && git init -q . && git config user.email t@example.com && git config user.name tester
  printf 'a\n' > a.txt && git add a.txt && git commit -qm "feat(x): add the thing"
  printf 'b\n' > b.txt && git add b.txt && git commit -qm "fix(x): correct the thing"
  printf 'c\n' > c.txt && git add c.txt && git commit -qm "docs(x): note the thing"
) >/dev/null 2>&1
# The helper finds the receipt script beside itself, so give it a real neighbour.
mkdir -p "$WORK/bin" && cp "$B" "$WORK/bin/" \
  && cp "$REPO_ROOT/skills/en-ship/scripts/ensemble-verification-receipt" "$WORK/bin/"
BIN="$WORK/bin/ensemble-pr-body"

body() { OUT=$( cd "$D" && bash "$BIN" "$@" 2>&1 ); RC=$?; }

# --- no test result: say so, invent nothing -----------------------------------
body --base HEAD~2
assert_eq "0" "$RC" "a body generates without a test result"
printf '%s' "$OUT" | grep -qF "No test run recorded for this branch." \
  && pass "an absent test result is stated plainly" \
  || fail "the body must say no test run was recorded"
# The failure mode in one assertion: a checklist nobody ran.
printf '%s' "$OUT" | grep -qE '^\s*-?\s*\[[ x]\]' \
  && fail "the body invented a checkbox test plan with no result behind it" \
  || pass "no checkbox list is synthesised from the changed files"
printf '%s' "$OUT" | grep -qiE 'should pass|verify that|make sure' \
  && fail "the body wrote aspirational test prose instead of a result" \
  || pass "no aspirational test prose stands in for a result"

# --- a real test result is reported with its selection tier -------------------
body --base HEAD~2 --tests "4 targeted tests passed" --selection graph
printf '%s' "$OUT" | grep -qF "4 targeted tests passed" \
  && pass "a supplied test result appears" || fail "the test result must appear"
printf '%s' "$OUT" | grep -qF "selection: graph" \
  && pass "the selection tier travels into the body" \
  || fail "the selection tier must reach the reviewer"
printf '%s' "$OUT" | grep -qF "No test run recorded" \
  && fail "the no-result line must not appear alongside a result" \
  || pass "the no-result line is mutually exclusive with a result"

# --- the summary comes from commits, not from the diff ------------------------
body --base HEAD~2
printf '%s' "$OUT" | grep -qF "fix(x): correct the thing" \
  && pass "the summary defaults to the commit subjects" \
  || fail "the default summary must be the commit list"
body --base HEAD~2 --summary "one" --summary "two"
printf '%s' "$OUT" | grep -qF -- "- one" && printf '%s' "$OUT" | grep -qF -- "- two" \
  && pass "supplied summary bullets are used verbatim" \
  || fail "--summary must be usable more than once"
printf '%s' "$OUT" | grep -qF "fix(x): correct the thing" \
  && fail "a supplied summary must replace the commit list, not append to it" \
  || pass "a supplied summary replaces the commit list"

# --- the receipt section reflects reality -------------------------------------
body --base HEAD~2
printf '%s' "$OUT" | grep -qF "no verification receipt for this tree" \
  && pass "a tree with no receipt says so, rather than omitting the section" \
  || fail "an absent receipt must be reported, not hidden"
( cd "$D" && bash "$WORK/bin/ensemble-verification-receipt" write \
    --check full_suite=passed --check lint=passed --by en-build ) >/dev/null 2>&1
body --base HEAD~2
printf '%s' "$OUT" | grep -qF "full_suite, lint" \
  && pass "the receipt's checks are listed" || fail "the receipt's checks must be listed"
printf '%s' "$OUT" | grep -qF "recorded by: en-build" \
  && pass "the body names who recorded the evidence" \
  || fail "the writer must be named, so a skip is attributable"
printf '%s' "$OUT" | grep -qiF "CI does not trust this section" \
  && pass "the section says CI does not trust it" \
  || fail "the body must not let a reader read this as CI evidence"

# --- plan reference ------------------------------------------------------------
body --base HEAD~2 --plan docs/plans/completed/EN07-feature_x.md
printf '%s' "$OUT" | grep -qF "Closes plan: docs/plans/completed/EN07-feature_x.md" \
  && pass "a plan path becomes a Closes plan line" || fail "the plan path must be linked"
body --base HEAD~2
printf '%s' "$OUT" | grep -qF "Closes plan:" \
  && fail "a Closes plan line appeared with no plan" \
  || pass "no plan means no Closes plan line"

# --- usage ---------------------------------------------------------------------
body
assert_eq "2" "$RC" "a missing --base is a usage error"
body --base no-such-ref-xyz
assert_eq "2" "$RC" "an unresolvable base is a usage error, not an empty body"

report
