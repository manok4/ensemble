#!/usr/bin/env bash
# Drift guards for en-brainstorm integration check + verify-before-claiming (EN05 U2).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm integration + verify"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
TEMPLATE="$REPO_ROOT/references/templates/design-doc-template.md"

# --- integration check exists, before approaches ---
ic_line=$(grep -n "Integration check" "$SKILL" | head -1 | cut -d: -f1)
appr_line=$(grep -n "Propose.*approaches" "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$ic_line" ] && [ -n "$appr_line" ] && [ "$ic_line" -lt "$appr_line" ]; then
  pass "en-brainstorm has an integration check before approaches"
else
  fail "integration check must precede approaches (ic=$ic_line appr=$appr_line)"
fi

# --- one probe per combination effect, not a blanket audit ---
if grep -qiE "one open-ended probe per genuine combination|per genuine combination effect" "$SKILL" && grep -qiE "not a blanket audit" "$SKILL"; then
  pass "integration check fires one probe per combination (not a blanket audit)"
else
  fail "integration check must be one-probe-per-combination, not a blanket audit"
fi

# --- distinguished from the devil's-advocate pass (before-approaches vs after-recommendation) ---
if grep -qiE "distinguishes it from the devil.s-advocate|before approaches.*devil|devil.s-advocate pass \(step 9" "$SKILL"; then
  pass "integration check is distinguished from the devil's-advocate pass"
else
  fail "integration check must be distinguished from the devil's-advocate pass"
fi

# --- verify-before-claiming rule present ---
if grep -qiE "Verify-before-claiming" "$SKILL" && grep -qiE "absent.*codebase|verified against the repo|unverified assumption" "$SKILL"; then
  pass "verify-before-claiming rule present (absence claims verified or labeled)"
else
  fail "verify-before-claiming rule must require verifying/labeling absence claims"
fi

# --- verify-before-claiming is lightweight (NOT a verifier sub-agent) ---
if grep -qiE "not a verifier sub-agent|lightweight rule" "$SKILL"; then
  pass "verify-before-claiming is a lightweight rule (no sub-agent)"
else
  fail "verify-before-claiming must be documented as lightweight (no sub-agent)"
fi

# --- design-doc-template has an assumptions / unverified-claims section ---
if grep -qE "^## Assumptions & unverified claims" "$TEMPLATE" && grep -qiE "unverified assumption|labeled as" "$TEMPLATE"; then
  pass "design-doc-template has an Assumptions & unverified claims section"
else
  fail "design-doc-template must carry the assumptions/unverified-claims section"
fi

report
