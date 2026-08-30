#!/usr/bin/env bash
# Behavior guards for the frontier-rounds asking cadence and non-blocking fact lookup.
# These exist because the latency win is worth ~3x round trips and is easy to silently revert.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm frontier rounds"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
SOCRATIC="$REPO_ROOT/skills/en-brainstorm/references/socratic-questions.md"

# --- 1. frontier batching, its safety rule, and its two carve-outs all survive together.
#        Batching WITHOUT the dependency rule is the dangerous half — guard them as one unit. ---
f_ok=1
grep -qiE "frontier" "$SKILL" || f_ok=0
grep -qiE "ask the whole frontier in one round" "$SKILL" || f_ok=0
grep -qiE "belongs to a \*later\* round" "$SKILL" || f_ok=0          # the dependency rule
grep -qiE "recommended answer" "$SKILL" || f_ok=0                     # per-question default
grep -qiE "Lightweight — one question per turn" "$SKILL" || f_ok=0    # carve-out 1
grep -qiE "Rigor probes stay one per turn" "$SKILL" || f_ok=0         # carve-out 2
grep -qiE "frontier" "$SOCRATIC" || f_ok=0                            # reference agrees on cadence
if [ "$f_ok" -eq 1 ]; then
  pass "frontier rounds + dependency rule + recommended answers + both one-per-turn carve-outs"
else
  fail "frontier cadence incomplete (batching without the dependency rule or carve-outs is unsafe)"
fi

# --- 2. facts are looked up (non-blocking); only decisions go to the user ---
if grep -qiE "Facts are yours to find" "$SKILL" \
   && grep -qiE "don.t block on it" "$SKILL" \
   && grep -qiE "downstream of that fact" "$SKILL" \
   && grep -qiE "Decisions stay with the user" "$SKILL"; then
  pass "facts looked up non-blocking; only downstream questions wait; decisions stay with the user"
else
  fail "fact-lookup contract must be non-blocking and must not push lookups onto the user"
fi

# --- 3. a spent budget with a live frontier records assumptions rather than dropping decisions ---
if grep -qiE "Stop when the frontier is empty" "$SKILL" \
   && grep -qiE "budget runs out with a live frontier" "$SKILL" \
   && grep -qiE "explicit assumptions" "$SKILL"; then
  pass "exit condition is frontier-empty or budget-spent; leftovers become explicit assumptions"
else
  fail "must exit on empty frontier or spent budget, recording leftover decisions as assumptions"
fi

# --- 4. boundaries are probed with a concrete case, not an abstract question ---
# From domain-modeling: asking how two concepts relate in the abstract returns an
# abstract answer, and the boundary is exactly where a design leaks. A scenario
# lets the user answer from how they think about the product rather than from a
# vocabulary they may not have yet. Guarded with its own restraint clause: fired
# on every relationship it becomes an interrogation, which is the same failure the
# blindspot gate's over-fire guard exists to prevent.
if grep -qiE 'Stress-test boundaries with an invented scenario' "$SKILL" \
   && grep -qiE 'abstract answer' "$SKILL" \
   && grep -qiE 'not on every relationship' "$SKILL"; then
  pass "boundary questions are probed with a concrete scenario, and the probe is restrained"
else
  fail "boundary probing needs a concrete scenario AND a restraint clause" \
       "an unrestrained scenario probe turns the interview into an interrogation"
fi

report
