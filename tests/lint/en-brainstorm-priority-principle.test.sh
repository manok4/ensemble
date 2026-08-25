#!/usr/bin/env bash
# Consistency guard for the D39 priority principle across the two skills that state it.
# Guards that the two skills AGREE, not that any particular paragraph exists.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm priority principle"

BRAINSTORM="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
PRINCIPLE="performance > speed ≥ cost"

if grep -qF "$PRINCIPLE" "$BRAINSTORM" && grep -qF "$PRINCIPLE" "$PLAN" \
   && grep -qF "D39" "$BRAINSTORM" && grep -qF "D39" "$PLAN"; then
  pass "en-brainstorm and en-plan state the same D39 ordering ($PRINCIPLE)"
else
  fail "en-brainstorm and en-plan must both state '$PRINCIPLE' and cite D39"
fi

report
