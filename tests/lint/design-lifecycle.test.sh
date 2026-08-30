#!/usr/bin/env bash
# tests/lint/design-lifecycle.test.sh
#
# The design-doc lifecycle was described but never ran. The template said
# /en-learn flipped a design's status "as part of its post-ship sweep when it
# sees related_plan: populated"; en-learn had no such sweep, and nothing in the
# repo ever wrote related_plan:, so the trigger could not fire even if it had.
#
# Consequence compounded with use. /en-brainstorm's resume scan globs designs
# with status: open, so every design ever written stayed a resume candidate and
# the disambiguation prompt grew with every brainstorm.
#
# /en-plan now closes a design out in the same promotion that flips a plan to
# status: open. It is the only skill that can choose between `accepted` and
# `superseded`, because it is the one holding both the design's recommendation
# and what the plan actually commits to.
#
# The placement is the fragile part. Step 16 reaches `open` by SIX conditions,
# and a Lightweight plan commonly gets there with no peer pass at all. A
# close-out hooked to the peer-approve bullet would skip those silently, which
# is the same class of bug as the original: a lifecycle that looks wired up and
# runs on a fraction of the paths.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="design lifecycle"

PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
TMPL="$REPO_ROOT/skills/en-brainstorm/references/templates/design-doc-template.md"
LEARN="$REPO_ROOT/skills/en-learn/SKILL.md"
LINT="$REPO_ROOT/bin/ensemble-lint"

# --- 1. the close-out lives in the promotion block, not on one path into it ---
promote=$(grep -n 'Promote to `open`' "$PLAN" | head -1 | cut -d: -f1)
closeout=$(grep -n 'Close out the design doc' "$PLAN" | head -1 | cut -d: -f1)
next_step=$(awk -v p="$promote" 'NR>p && /^[0-9]+\. \*\*/ {print NR; exit}' "$PLAN")

if [ -n "$promote" ] && [ -n "$closeout" ] && [ -n "$next_step" ] \
   && [ "$closeout" -gt "$promote" ] && [ "$closeout" -lt "$next_step" ]; then
  pass "the close-out sits inside the promotion block (line $closeout, block $promote-$next_step)"
else
  fail "the close-out must sit inside the promotion block" \
       "promote=$promote closeout=$closeout next=$next_step"
fi

# The block must still reach `open` by more than the peer-approve path, or the
# placement above stops meaning anything.
# Count only the conditions ABOVE the close-out: the close-out's own bullets are
# inside the same block and would otherwise pad this number into meaninglessness.
conds=$(awk -v a="$promote" -v b="$closeout" 'NR>a && NR<b' "$PLAN" | grep -c '^    - ')
[ "${conds:-0}" -ge 6 ] \
  && pass "the promotion block still lists $conds conditions reaching open" \
  || fail "the promotion block must list every path to open" "found ${conds:-0}, expected >= 6"

# --- 2. both outcomes, and the back-reference, are written ---
missing=""
grep -qF 'accepted' "$PLAN"    || missing="$missing accepted"
grep -qF 'superseded' "$PLAN"  || missing="$missing superseded"
grep -qF 'related_plan' "$PLAN" || missing="$missing related_plan"
[ -z "$missing" ] \
  && pass "the close-out sets accepted/superseded and writes related_plan" \
  || fail "the close-out must set both outcomes and write related_plan" "missing:$missing"

# --- 3. ownership: en-learn must not claim the flip it never performed ---
if grep -qiE 'post-ship sweep' "$TMPL" || grep -qiE "en-learn.{0,40}flip the design" "$TMPL"; then
  fail "the template must not attribute the flip to /en-learn" \
       "that sweep does not exist; the claim is what hid the dead lifecycle"
else
  pass "the template attributes the close-out to its real owner"
fi

if grep -qE 'docs/designs' "$LEARN"; then
  fail "en-learn must not claim a design-status path" "$(grep -n 'docs/designs' "$LEARN" | head -1)"
else
  pass "en-learn claims no design-status path"
fi

# --- 4. the never-planned case is stated, so nobody "fixes" it ---
if grep -qiE 'never produces a plan stays .?open' "$TMPL"; then
  pass "designs that never produce a plan are documented as correctly staying open"
else
  fail "the never-planned case must be stated" \
       "without it the next reader treats a lingering open design as a bug"
fi

# --- 5. the lint catches a half-applied close-out ---
if grep -qF 'with no related_plan' "$LINT"; then
  pass "lint catches a closed-out design with no related_plan"
else
  fail "lint must catch a half-applied close-out (status set, related_plan empty)"
fi

report
