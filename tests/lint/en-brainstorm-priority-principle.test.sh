#!/usr/bin/env bash
# Drift guards for the performance > speed >= cost priority principle + D39 (EN05 U4).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm priority principle"

BRAINSTORM="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# exact ordering to assert everywhere
PRINCIPLE="performance > speed ≥ cost"

# --- en-brainstorm states the principle with the exact ordering ---
if grep -qF "$PRINCIPLE" "$BRAINSTORM"; then
  pass "en-brainstorm states performance > speed ≥ cost"
else
  fail "en-brainstorm must state '$PRINCIPLE'"
fi

# --- en-plan states the principle with the exact ordering ---
if grep -qF "$PRINCIPLE" "$PLAN"; then
  pass "en-plan states performance > speed ≥ cost"
else
  fail "en-plan must state '$PRINCIPLE'"
fi

# --- both tie it to D39 ---
if grep -qF "D39" "$BRAINSTORM" && grep -qF "D39" "$PLAN"; then
  pass "both skills reference D39"
else
  fail "both skills must reference the D39 principle"
fi

# --- foundation D39 exists and names the principle + the rigor upgrades ---
d39="$(grep -E "^- \*\*D39\." "$FOUNDATION" || true)"
if [ -n "$d39" ] && printf '%s' "$d39" | grep -qF "$PRINCIPLE"; then
  pass "foundation D39 states the priority principle"
else
  fail "foundation D39 must state performance > speed ≥ cost"
fi
if [ -n "$d39" ] && printf '%s' "$d39" | grep -qiE "Product pressure test" && printf '%s' "$d39" | grep -qiE "integration check" && printf '%s' "$d39" | grep -qiE "verify-before-claiming"; then
  pass "foundation D39 records the brainstorm rigor upgrades"
else
  fail "foundation D39 must record the brainstorm rigor upgrades"
fi

# --- D39 records the deliberately-NOT-adopted list (lean guard) ---
if [ -n "$d39" ] && printf '%s' "$d39" | grep -qiE "NOT adopted|visual probes"; then
  pass "foundation D39 records what was deliberately not adopted"
else
  fail "foundation D39 should record the deliberately-not-adopted scope"
fi

report
