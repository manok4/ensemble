#!/usr/bin/env bash
# tests/lint/en-build-stop-conditions.test.sh
#
# en-build's autonomy contract is one-sided by design: it enumerates seven
# legitimate pauses to stop the agent inserting "let me checkpoint here" between
# units. That solved over-pausing and left the opposite failure unaddressed —
# guessing through a blocker rather than asking.
#
# The two conditions added here are the ones the flow could not otherwise
# surface, and both are silent when they go wrong:
#
#   SCOPE. A unit that needs files outside its `Files` list. The list is what
#   the plan was reviewed against, so quiet widening is invisible until step 10
#   reads a diff nobody scoped.
#
#   THIN APPROACH. Pre-flight checks the `Approach` field is PRESENT, never that
#   it is sufficient. A guessed interpretation passes the tests written to match
#   the guess.
#
# They are failure-protocol rows, not new pause authority — the autonomy
# contract's seventh case already routes there, so the two documents compose
# instead of contradicting. That composition is what clause 3 checks.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build stop conditions"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"

# --- 1. both conditions exist, and both say stop BEFORE acting ---
if grep -qiE 'Unit needs files outside its .Files. list' "$SKILL" \
   && grep -qiE 'Stop before making the change' "$SKILL" \
   && grep -qiE 'Do not quietly widen' "$SKILL"; then
  pass "scope expansion stops before the change, not after"
else
  fail "a unit needing files outside its scope must stop before widening" \
       "silent sprawl is invisible until step 10 reads a diff nobody scoped"
fi

if grep -qiE "Approach. is too thin to implement" "$SKILL" \
   && grep -qiE 'present, not that it is sufficient' "$SKILL"; then
  pass "a thin Approach stops and asks, and says why pre-flight missed it"
else
  fail "a unit too thin to implement must stop and ask"
fi

# --- 2. repeated verification failure has a bound ---
# Without one, "fix and re-run" is an unbounded loop whose usual exit is
# weakening the test until it passes.
if grep -qiE 'After two failed attempts on the same unit, stop' "$SKILL"; then
  pass "repeated verification failure is bounded"
else
  fail "repeated unit verification failure must be bounded" \
       "an unbounded retry loop exits by weakening the test"
fi

# --- 3. they compose with the autonomy contract instead of contradicting it ---
# The contract restricts pauses to seven cases. These are legitimate only
# because case 7 routes to the failure protocol; if that case were removed, the
# rows would become the agent-initiated pauses the contract forbids.
if grep -qiE 'Failure protocol fires' "$SKILL" \
   && grep -qiE 'seven (enumerated |legitimate )?(pause )?cases|seven cases' "$SKILL"; then
  pass "the failure-protocol pause case still exists for these rows to route through"
else
  fail "the autonomy contract must keep its failure-protocol case" \
       "without it these rows become the agent-initiated pauses the contract forbids"
fi

# --- 4. no stale row survives the model that produced it ---
# gate 1 / gate 2 were the per-unit simplifier sandwich; the worker was D52's.
stale=""
grep -qiE 'Verification gate [12]' "$SKILL" && stale="$stale gate-1/2"
grep -qiE 'Worker dispatch returns' "$SKILL" && stale="$stale worker-dispatch"
[ -z "$stale" ] \
  && pass "no failure row references a removed mechanism" \
  || fail "a failure row references a mechanism that no longer exists" "$stale"

report
