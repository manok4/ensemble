#!/usr/bin/env bash
# Behavior guards for en-brainstorm integration check + verify-before-claiming (EN05 U2, recalibrated).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm integration + verify"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
TEMPLATE="$REPO_ROOT/references/templates/design-doc-template.md"

# --- 1. ORDERING: both rigor steps run BEFORE approaches (that ordering is the whole point;
#        it is what separates them from the after-recommendation devil's-advocate pass) ---
pt_line=$(grep -n "Product pressure test" "$SKILL" | head -1 | cut -d: -f1)
ic_line=$(grep -n "Integration check" "$SKILL" | head -1 | cut -d: -f1)
appr_line=$(grep -n "Propose 2" "$SKILL" | head -1 | cut -d: -f1)
da_line=$(grep -n "Devil's advocate" "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$pt_line" ] && [ -n "$ic_line" ] && [ -n "$appr_line" ] && [ -n "$da_line" ] \
   && [ "$pt_line" -lt "$appr_line" ] && [ "$ic_line" -lt "$appr_line" ] && [ "$appr_line" -lt "$da_line" ]; then
  pass "pressure test + integration check precede approaches; devil's advocate follows them"
else
  fail "ordering broken (pt=$pt_line ic=$ic_line approaches=$appr_line devil=$da_line)"
fi

# --- 2. integration check is targeted, not a blanket audit ---
if grep -qiE "one open-ended probe per genuine combination" "$SKILL" && grep -qiE "not a blanket audit" "$SKILL"; then
  pass "integration check fires one probe per combination (not a blanket audit)"
else
  fail "integration check must be one-probe-per-combination, not a blanket audit"
fi

# --- 3. verify-before-claiming: BOTH arms, and the template has somewhere to put arm 2 ---
if grep -qiE "Verify-before-claiming" "$SKILL" \
   && grep -qiE "absent" "$SKILL" \
   && grep -qiE "verified against the repo" "$SKILL" \
   && grep -qiE "unverified assumption" "$SKILL" \
   && grep -qE "^## Assumptions & unverified claims" "$TEMPLATE"; then
  pass "absence claim → verified against repo OR labeled unverified assumption (template has the section)"
else
  fail "verify-before-claiming needs both arms AND the template's assumptions section"
fi

report
