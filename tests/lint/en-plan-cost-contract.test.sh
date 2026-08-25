#!/usr/bin/env bash
# Guards en-plan's bounded reads, gated checkpoint, frontier cadence, and design-doc reuse.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan cost contract"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
CHECKPOINT="$REPO_ROOT/references/plan-default-branch-checkpoint.md"

# --- 1. foundation.md is read by section index, never whole ---
if grep -qiE "Bounded foundation read" "$SKILL" \
   && grep -qF "grep -n '^#' docs/foundation.md" "$SKILL" \
   && grep -qiE "Never read .docs/foundation.md. whole" "$SKILL"; then
  pass "foundation read is bounded (section index, never whole-file)"
else
  fail "the foundation read must stay bounded"
fi

# --- 2. the default-branch checkpoint body lives in a gated reference, not inline ---
if [ -f "$CHECKPOINT" ] \
   && grep -qF 'references/plan-default-branch-checkpoint.md' "$SKILL" \
   && grep -qiE "read only when its step.s gate fires" "$SKILL" \
   && ! grep -qF "(recommended) — create the branch + commit" "$SKILL" \
   && ! grep -qF "show diagnostic info" "$SKILL"; then
  pass "default-branch checkpoint is gated behind a reference (prompt body not inline)"
else
  fail "checkpoint prompt/handlers must live in the gated reference, not in SKILL.md"
fi

# --- 3. planning questions batch by frontier, with the dependency rule and a Lightweight carve-out ---
f_ok=1
grep -qiE "frontier rounds" "$SKILL" || f_ok=0
grep -qiE "one numbered round" "$SKILL" || f_ok=0
grep -qiE "recommended answer" "$SKILL" || f_ok=0
grep -qiE "waits for the next round" "$SKILL" || f_ok=0          # the dependency rule
grep -qiE "On \*\*Lightweight\*\*, ask one question per turn" "$SKILL" || f_ok=0
if [ "$f_ok" -eq 1 ]; then
  pass "planning questions use frontier rounds with the dependency rule and Lightweight carve-out"
else
  fail "frontier cadence incomplete (batching without the dependency rule is unsafe)"
fi

# --- 4. an existing design doc is consumed, not re-interviewed across ---
if grep -qiE "Consume the design doc" "$SKILL" \
   && grep -qiE "already answered" "$SKILL" \
   && grep -qiE "only what the doc left open" "$SKILL" \
   && grep -qiE "Assumptions & unverified claims" "$SKILL"; then
  pass "settled design-doc decisions are carried, not re-asked; assumptions carved out"
else
  fail "must consume a matching design doc instead of re-interviewing across the seam"
fi

report
