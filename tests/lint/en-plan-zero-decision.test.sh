#!/usr/bin/env bash
# tests/lint/en-plan-zero-decision.test.sh
#
# EN24 U3. A unit that leaves the implementer to choose a schema, an API path,
# a dependency or an edge-case policy hands /en-build a decision the plan was
# supposed to make, and the build makes it silently, one unit at a time. The
# pre-write review now has a sixth check for it, and the plan peer a matching
# dimension (H0) whose severity follows impact, like every other dimension.
#
# What en-plan sends the peer is asserted in tests/build-peer-prompt/; this
# file holds the pre-write check and SKILL.md's pointer to it in step.
#
# NEGATIVE CONTROLS (run by hand 2026-10-29, each turned the test red):
#   - removed the sixth bullet from plan-prewrite.md
#   - put "five checks" back in SKILL.md step 13 with six bullets listed

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan settles every decision before the build"

PRE="$REPO_ROOT/skills/en-plan/references/plan-prewrite.md"
SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
BRIEF="$REPO_ROOT/skills/en-plan/references/peer-brief.md"

grep -qF -- '- **Zero decisions left to the implementer.**' "$PRE" \
  && pass "plan-prewrite.md carries the zero-decision check" \
  || fail "plan-prewrite.md carries the zero-decision check"

# The heading's count must match the bullets under it, and SKILL.md must say
# the same number: a pointer that says five while the file lists six is how a
# check gets skipped.
bullets=$(awk '/^## The .* checks$/{f=1; next} f && /^## /{exit} f && /^- \*\*/{n++} END{print n+0}' "$PRE")
word=$(sed -n 's/^## The \([a-z]*\) checks$/\1/p' "$PRE")
case "$word" in five) want=5 ;; six) want=6 ;; seven) want=7 ;; *) want=0 ;; esac
assert_eq 6 "$bullets" "plan-prewrite.md lists six checks"
assert_eq "$bullets" "$want" "the heading names the number of checks listed ($word)"
step=$(grep '^13\. \*\*Pre-write plan-quality review' "$SKILL")
assert_contains "$step" "run its $word checks" "SKILL.md step 13 names the same count"
assert_contains "$step" "zero decisions left to the implementer" "SKILL.md step 13 lists the new check"

grep -qF 'H0. Decisions left to the implementer.' "$BRIEF" \
  && pass "the peer brief carries dimension H0" \
  || fail "the peer brief carries dimension H0"

report
