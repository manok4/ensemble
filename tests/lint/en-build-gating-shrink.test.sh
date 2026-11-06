#!/usr/bin/env bash
# Drift guards for en-build gating shrink + preflight gate summary (FR01 U7).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build gating shrink"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
# Reads /en-plan's copy: it owns the plan template, and D52's payload cut
# removed en-build's, which it carried for one see-also cross-reference.
TEMPLATE="$REPO_ROOT/skills/en-plan/references/templates/plan-template.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- preflight gate summary ---
if grep -qiE "Preflight gate summary" "$SKILL"; then
  pass "en-build has a preflight gate summary"
else
  fail "en-build must have a preflight gate summary"
fi

# --- gated:true restricted to production-state-changing ---
if grep -qiE "production-state-changing" "$SKILL"; then
  pass "gated:true restricted to production-state-changing actions"
else
  fail "gated:true must be restricted to production-state-changing actions"
fi

# --- non-production side effects explicitly NOT gated ---
if grep -qiE "[Nn]on-production external side effects.*NOT|explicitly \*\*NOT\*\* gated|NOT.*gated" "$SKILL"; then
  pass "non-production side effects explicitly not gated"
else
  fail "non-production side effects must be explicitly not gated"
fi

# --- two narrow categories framing ---
if grep -qiE "two narrow categories" "$SKILL"; then
  pass "gating framed as two narrow categories"
else
  fail "gating should be framed as two narrow categories"
fi

# --- destructive remains its own category ---
if grep -qiE "risk: destructive.*own (literal-string )?category|its own literal-string category" "$SKILL"; then
  pass "risk:destructive kept as its own category"
else
  fail "risk:destructive must be kept distinct from gated:true"
fi

# --- plan-template keeps the tight bar ---
if grep -qiE "production user state|production-state" "$TEMPLATE"; then
  pass "plan-template keeps the tight gated bar"
else
  fail "plan-template must keep the tight gated bar"
fi

# --- foundation D33 reinforced ---
if grep -qiE "two narrow categories only|Gating surface is two narrow" "$FOUNDATION"; then
  pass "foundation D33 records the gating-surface narrowing"
else
  fail "foundation D33 must record the gating-surface narrowing"
fi

# --- no question tool: a gate returns, it is never skipped (EN27 U2) ---
step9a=$(grep -F '**9a. Mandatory safety gate' "$SKILL")
case "$step9a" in
  *'neither answered nor skipped'*'`gate_required: U<N>`'*) pass "step 9a returns gate_required when no question tool can reach the user" ;;
  *) fail "step 9a must say a gate is neither answered nor skipped, and return gate_required" ;;
esac
case "$step9a" in
  *'no question tool'*'`needs-decision: U<N>: <question>`'*) pass "any other stop-and-ask returns needs-decision on the same rule" ;;
  *) fail "step 9a must return needs-decision for any other stop-and-ask with no question tool" ;;
esac
contract="$REPO_ROOT/skills/en-build/CONTRACT.md"
if grep -qF '`gate_required: U<N>`' "$contract" && grep -qF '`needs-decision: U<N>: <question>`' "$contract"; then
  pass "the contract's Return table names both return lines"
else
  fail "en-build CONTRACT.md must name gate_required and needs-decision"
fi

report
