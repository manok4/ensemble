#!/usr/bin/env bash
# tests/lint/en-build-stop-conditions.test.sh
#
# en-build's autonomy contract is one-sided by design: it enumerates five
# legitimate pauses to stop the agent inserting "let me checkpoint here" between
# units. That solved over-pausing and left the opposite failure unaddressed —
# guessing through a blocker rather than asking.
#
# The two conditions added here are the ones the flow could not otherwise
# surface, and both are silent when they go wrong:
#
#   SCOPE. A unit that needs files outside its `Files` list. The list is what
#   the plan was reviewed against. This one no longer stops by default: asking
#   "widen?" every time the plan missed a file was a pause the user always
#   answered yes, so the build widens on its own when the unit's Goal needs it.
#   What must not go silent is the widening itself, so each added path is
#   recorded in the commit body, and two cases still stop: a separate
#   deliverable (split territory) and gated or destructive work, which would
#   otherwise ride a widening past the 9a gate.
#
#   THIN APPROACH. Pre-flight checks the `Approach` field is PRESENT, never that
#   it is sufficient. A guessed interpretation passes the tests written to match
#   the guess.
#
# They are failure-protocol rows, not new pause authority — the autonomy
# contract's last case already routes there, so the two documents compose
# instead of contradicting. That composition is what clause 3 checks.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build stop conditions"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"

# --- 1. scope widening is autonomous, recorded, and bounded ---
# Checked in SKILL.md and the full failure table, so the two cannot drift into
# one widening silently and the other still asking.
FAILURES="$REPO_ROOT/skills/en-build/references/build-failures.md"
for f in "$SKILL" "$FAILURES"; do
  name="${f#$REPO_ROOT/}"
  if grep -qiE 'Unit needs files outside its .Files. list' "$f" \
     && grep -qiE 'Widen without asking' "$f" \
     && grep -qiE 'Scope widened:' "$f" \
     && grep -qiE 'commit body' "$f"; then
    pass "$name: scope widening proceeds and is recorded in the commit"
  else
    fail "$name: a unit needing files outside its scope must widen and record it" \
         "an unrecorded widening is invisible until step 10 reads a diff nobody scoped"
  fi
  if grep -qiE 'deliverable of its own' "$f" \
     && grep -qiE 'gated or destructive' "$f" \
     && grep -qiE 'skip 9a|past 9a' "$f"; then
    pass "$name: widening still stops for a separate deliverable or gated work"
  else
    fail "$name: widening must stop for a separate deliverable or gated/destructive work" \
         "otherwise a widening carries gated work past the 9a safety gate"
  fi
  if grep -qiE 'ask: widen' "$f"; then
    fail "$name: the old widen/split/abort prompt is back" \
         "the build decides a needed widening itself"
  else
    pass "$name: no widen prompt survives"
  fi
done

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
# The contract restricts pauses to five cases (seven until D108 retired the two
# phase-level ones). These rows are legitimate only because the last case routes
# to the failure protocol; without it they become the agent-initiated pauses the
# contract forbids.
# EN18 U8 moved the contract to references/autonomy-contract.md; the clause
# follows the prose rather than loosening to match wherever it ended up.
CONTRACT="$REPO_ROOT/skills/en-build/references/autonomy-contract.md"
if grep -qiE 'Failure protocol fires' "$CONTRACT" \
   && grep -qiE 'five (enumerated |legitimate )?(pause )?cases|five cases' "$CONTRACT"; then
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
