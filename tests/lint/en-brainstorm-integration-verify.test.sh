#!/usr/bin/env bash
# Behavior guards for en-brainstorm integration check + verify-before-claiming (EN05 U2, recalibrated).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm integration + verify"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
TEMPLATE="$REPO_ROOT/skills/en-brainstorm/references/templates/design-doc-template.md"

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

# --- 4. the doc-skip gate is reachable from the numbered flow ---
# It used to live in a trailing "When to skip the design doc" section that no
# step pointed at, so an agent walking the flow wrote a doc every time. A gate
# outside the flow is not a gate. It now sits inside the write step; this checks
# it stays inside the numbered list rather than drifting back out to a section.
proc_line=$(grep -n '^## Process' "$SKILL" | head -1 | cut -d: -f1)
end_line=$(awk -v p="$proc_line" 'NR>p && /^## / {print NR; exit}' "$SKILL")
offer_line=$(grep -n 'Want a design doc, or just talk it through' "$SKILL" | head -1 | cut -d: -f1)

if [ -n "$proc_line" ] && [ -n "$end_line" ] && [ -n "$offer_line" ] \
   && [ "$offer_line" -gt "$proc_line" ] && [ "$offer_line" -lt "$end_line" ]; then
  pass "the doc-skip offer sits inside the numbered flow (line $offer_line, flow $proc_line-$end_line)"
else
  fail "the doc-skip offer must sit inside the numbered flow" \
       "offer=$offer_line flow=$proc_line-$end_line — a gate no step reaches never fires"
fi

report
