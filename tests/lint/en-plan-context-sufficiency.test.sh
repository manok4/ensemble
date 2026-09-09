#!/usr/bin/env bash
# Guards that en-plan escalates to /en-brainstorm on INSUFFICIENT CONTEXT, not merely
# on a missing design doc — and that it still never hard-gates.
#
# The check itself lives in references/plan-intake.md; the source-the-request
# step reaches it. Clause 0 pins that pointer, because the rules are worth
# nothing if the step that needs them never opens the file.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan context sufficiency"

PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
INTAKE="$REPO_ROOT/skills/en-plan/references/plan-intake.md"

# --- 0. the step that sources the request reaches the check ---
# Scoped to the step, not the file: a mention anywhere else does not put the
# rules in front of the planner before it starts asking questions.
step=$(awk '/^4\. \*\*Source the request/{f=1} f&&/^5\. \*\*/{exit} f' "$PLAN")
if printf '%s' "$step" | grep -qF 'references/plan-intake.md'; then
  pass "the source-the-request step points at the intake reference"
else
  fail "the source-the-request step must cite references/plan-intake.md" \
       "without the pointer the sufficiency check is never read"
fi

# --- 1. the trigger is context sufficiency, with concrete decidable conditions ---
c_ok=1
grep -qiE "Context-sufficiency check" "$INTAKE" || c_ok=0
grep -qiE "not whether a design doc happens to exist" "$INTAKE" || c_ok=0
grep -qiE "The problem is unstated" "$INTAKE" || c_ok=0
grep -qiE "The approach is genuinely open" "$INTAKE" || c_ok=0
grep -qiE "Scope has no edges" "$INTAKE" || c_ok=0
if [ "$c_ok" -eq 1 ]; then
  pass "escalation triggers on insufficient context, with three decidable conditions"
else
  fail "trigger must be context sufficiency (problem / approach / scope), not design-doc absence"
fi

# --- 2. insufficient context offers /en-brainstorm and recommends it ---
if grep -qiE "I don.t have enough to plan from yet" "$INTAKE" \
   && grep -qF "/en-brainstorm" "$INTAKE" \
   && grep -qiE "Recommend .brainstorm." "$INTAKE"; then
  pass "insufficient context offers /en-brainstorm as the recommended path"
else
  fail "insufficient context must offer /en-brainstorm and recommend it"
fi

# --- 3. still never a hard gate; proceeding records the gaps as assumptions ---
if grep -qiE "proceeding is always allowed" "$INTAKE" \
   && grep -qiE "never a hard gate" "$INTAKE" \
   && grep -qiE "record each unresolved gap" "$INTAKE"; then
  pass "proceeding stays allowed; unresolved gaps land as explicit assumptions"
else
  fail "must stay a soft gate AND record gaps as assumptions when the user proceeds"
fi

# --- 4. a well-specified request is not dragged through the heavy offer ---
if grep -qiE "Sufficient but no design doc" "$INTAKE" \
   && grep -qiE "does not need to be talked out of being well-specified" "$INTAKE"; then
  pass "sufficient-context requests get the light nudge, not the escalation"
else
  fail "a well-specified request must not get the insufficient-context escalation"
fi

report
