#!/usr/bin/env bash
# Drift guards for en-plan brainstorm soft-nudge (FR01 U12).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan brainstorm nudge"

EN_PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- soft-nudge present ---
if grep -qiE "Brainstorm soft-nudge" "$EN_PLAN"; then
  pass "en-plan has brainstorm soft-nudge"
else
  fail "en-plan missing brainstorm soft-nudge"
fi

# --- references en-brainstorm ---
if grep -qF "/en-brainstorm" "$EN_PLAN"; then
  pass "nudge references /en-brainstorm"
else
  fail "nudge must reference /en-brainstorm"
fi

# --- explicitly soft, not a hard gate ---
if grep -qiE "never .*hard gate|[Ss]oft nudge only|not.*hard gate" "$EN_PLAN"; then
  pass "nudge is explicitly soft (not a hard gate)"
else
  fail "nudge must be explicitly soft, not a hard gate"
fi

# --- proceeding is the default ---
if grep -qiE "proceeding is always allowed|default on any non-answer|proceed straight" "$EN_PLAN"; then
  pass "proceeding without brainstorm is always allowed"
else
  fail "must state proceeding is always allowed"
fi
