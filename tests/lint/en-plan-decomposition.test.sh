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
# The risk split is the part worth guarding. Only the contract unit is
# destructive; the batches stay additive and depend on the expand. The one
# destructive unit is therefore also the last one, which is exactly what
# unit.destructive-order requires, so the sequence needs no special-casing. Get
# that backwards and mark the batches destructive, and the rule rejects the plan
# as a structural error.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan decomposition"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
WIDE="$REPO_ROOT/skills/en-plan/references/wide-refactors.md"

# --- 0. the break-into-units step reaches the wide-refactor sequence ---
# Scoped to the step: the exception has to be in front of the planner while it
# is drawing unit boundaries, not findable somewhere else in the skill.
step=$(awk '/^8\. \*\*Break into units/{f=1} f&&/^9\. \*\*/{exit} f' "$SKILL")
if printf '%s' "$step" | grep -qF 'references/wide-refactors.md'; then
  pass "the break-into-units step points at the wide-refactor sequence"
else
  fail "the break-into-units step must cite references/wide-refactors.md" \
       "without the pointer a wide refactor gets forced into one unit again"
fi

# --- 1. the boundary test is operational, not a restatement ---
if grep -qiE 'reject this unit while approving its neighbour' "$SKILL"; then
  pass "unit boundaries have an operational test a reviewer could apply"
else
  fail "unit boundaries need an operational test, not three restatements of 'one change'"
fi

# --- 2. all three phases of the sequence are named ---
missing=""
for ph in 'Expand:' 'Migrate:' 'Contract:'; do
  grep -qF "**$ph**" "$WIDE" || missing="$missing $ph"
done
grep -qiE 'blast radius' "$WIDE" || missing="$missing blast-radius"
grep -qiE 'expand . migrate . contract' "$SKILL" || missing="$missing skill-names-the-sequence"
[ -z "$missing" ] \
  && pass "wide refactors sequence expand/migrate/contract, batched by blast radius" \
  || fail "the expand-migrate-contract sequence is incomplete" "missing:$missing"

# --- 3. the risk assignment that keeps unit.destructive-order satisfied ---
# This is the half that silently breaks: marking the batches destructive puts a
# destructive unit ahead of a non-destructive one and the rule rejects the plan.
if grep -qiE 'Only the contract unit is destructive' "$WIDE" \
   && grep -qiE 'batches stay additive' "$WIDE" \
   && grep -qiE 'destructive-order.{0,14}then holds' "$WIDE"; then
  pass "only the contract unit carries the destructive risk, satisfying unit.destructive-order"
else
  fail "the risk split must be stated, with its destructive-order consequence" \
       "batches marked destructive make /en-build reject the plan as a structural error"
fi

# --- 4. the ordering rule it leans on still exists ---
# The split puts the destructive contract unit last; if nothing enforced that
# order, clause 3 would be asserting against a rule that no longer runs. The
# phase invariant did this until D108; unit.destructive-order does now.
if grep -qiE 'Ordering check' "$SKILL" && grep -qF 'unit.destructive-order' "$SKILL"; then
  pass "the ordering rule the sequence relies on is still in force"
else
  fail "the ordering rule is gone; the wide-refactor risk split now rests on nothing"
fi

report
