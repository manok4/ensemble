#!/usr/bin/env bash
# tests/lint/en-plan-decomposition.test.sh
#
# Two decomposition rules that the unit-breakdown step had no answer for.
#
# BOUNDARIES. "One logical change, peer-reviewable, atomically committable" is
# three restatements of the same intuition and gives an author nothing to test a
# boundary against. superpowers/writing-plans supplies the operational form:
# could a reviewer reject this unit while approving its neighbour? If not, they
# are one unit.
#
# WIDE REFACTORS. A rename across hundreds of call sites cannot be an
# atomically-committable unit that lands green — the rule and the reality are in
# direct conflict, and the rule loses silently. to-tickets names this as the
# explicit exception and sequences it expand → migrate → contract.
#
# The phase interaction is the part worth guarding. Only the contract unit is
# destructive; the batches stay additive and depend on the expand. Every batch is
# therefore lower-risk than the contract unit that depends on it, which is
# exactly what /en-plan's phase invariant requires, so /en-build phases the whole
# sequence with no special-casing. Get that backwards — mark the batches
# destructive — and the invariant rejects the plan as a structural error.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan decomposition"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- 1. the boundary test is operational, not a restatement ---
if grep -qiE 'reject this unit while approving its neighbour' "$SKILL"; then
  pass "unit boundaries have an operational test a reviewer could apply"
else
  fail "unit boundaries need an operational test, not three restatements of 'one change'"
fi

# --- 2. all three phases of the sequence are named ---
missing=""
for ph in 'Expand:' 'Migrate:' 'Contract:'; do
  grep -qF "**$ph**" "$SKILL" || missing="$missing $ph"
done
grep -qiE 'blast radius' "$SKILL" || missing="$missing blast-radius"
[ -z "$missing" ] \
  && pass "wide refactors sequence expand/migrate/contract, batched by blast radius" \
  || fail "the expand-migrate-contract sequence is incomplete" "missing:$missing"

# --- 3. the risk assignment that keeps the phase invariant satisfied ---
# This is the half that silently breaks: marking the batches destructive makes
# the contract unit depend on same-risk work and the invariant rejects the plan.
if grep -qiE 'Only the contract unit is destructive' "$SKILL" \
   && grep -qiE 'batches stay additive' "$SKILL" \
   && grep -qiE 'phase invariant then holds' "$SKILL"; then
  pass "only the contract unit carries the destructive risk, satisfying the phase invariant"
else
  fail "the risk split must be stated, with its phase-invariant consequence" \
       "batches marked destructive make /en-build reject the plan as a structural error"
fi

# --- 4. the invariant it leans on still exists ---
# If the phase invariant were removed, clause 3 would be asserting against a
# rule that no longer runs.
if grep -qiE 'Phase invariant check' "$SKILL" && grep -qiE 'risk\(V\) <= risk\(U\)' "$SKILL"; then
  pass "the phase invariant the sequence relies on is still in force"
else
  fail "the phase invariant is gone; the wide-refactor risk split now rests on nothing"
fi

report
