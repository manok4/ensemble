#!/usr/bin/env bash
# Guards that en-plan escalates to /en-brainstorm on INSUFFICIENT CONTEXT, not merely
# on a missing design doc — and that it still never hard-gates.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan context sufficiency"

PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- 1. the trigger is context sufficiency, with concrete decidable conditions ---
c_ok=1
grep -qiE "Context-sufficiency check" "$PLAN" || c_ok=0
grep -qiE "not whether a design doc happens to exist" "$PLAN" || c_ok=0
grep -qiE "The problem is unstated" "$PLAN" || c_ok=0
grep -qiE "The approach is genuinely open" "$PLAN" || c_ok=0
grep -qiE "Scope has no edges" "$PLAN" || c_ok=0
if [ "$c_ok" -eq 1 ]; then
  pass "escalation triggers on insufficient context, with three decidable conditions"
else
  fail "trigger must be context sufficiency (problem / approach / scope), not design-doc absence"
fi

# --- 2. insufficient context offers /en-brainstorm and recommends it ---
if grep -qiE "I don.t have enough to plan from yet" "$PLAN" \
   && grep -qF "/en-brainstorm" "$PLAN" \
   && grep -qiE "Recommend .brainstorm." "$PLAN"; then
  pass "insufficient context offers /en-brainstorm as the recommended path"
else
  fail "insufficient context must offer /en-brainstorm and recommend it"
fi

# --- 3. still never a hard gate; proceeding records the gaps as assumptions ---
if grep -qiE "proceeding is always allowed" "$PLAN" \
   && grep -qiE "never a hard gate" "$PLAN" \
   && grep -qiE "record each unresolved gap" "$PLAN"; then
  pass "proceeding stays allowed; unresolved gaps land as explicit assumptions"
else
  fail "must stay a soft gate AND record gaps as assumptions when the user proceeds"
fi

# --- 4. a well-specified request is not dragged through the heavy offer ---
if grep -qiE "Sufficient but no design doc" "$PLAN" \
   && grep -qiE "does not need to be talked out of being well-specified" "$PLAN"; then
  pass "sufficient-context requests get the light nudge, not the escalation"
else
  fail "a well-specified request must not get the insufficient-context escalation"
fi

report
