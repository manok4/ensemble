#!/usr/bin/env bash
# Behavior guards for the three D47 mechanisms: resume, blindspot pass, divergent approaches.
# Each guards the part that makes the mechanism safe, not its wording.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm adopted mechanisms"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
BLIND="$REPO_ROOT/shared/references/brainstorm-blindspot.md"
APPR="$REPO_ROOT/shared/references/brainstorm-approaches.md"

# --- 1. RESUME: confirmed, never silent; updates in place rather than duplicating ---
if grep -qiE "Resume or start fresh" "$SKILL" \
   && grep -qiE "confirm before resuming" "$SKILL" \
   && grep -qiE "never auto-resume silently" "$SKILL" \
   && grep -qiE "rather than minting a duplicate" "$SKILL"; then
  pass "resume is confirmed (never silent) and updates in place instead of duplicating"
else
  fail "resume must be confirmed and must update the existing doc, not mint a duplicate"
fi

# --- 2. BOTH heavy mechanisms stay GATED behind their own reference files.
#        Inlining them would undo the cost pass on every run that never triggers them. ---
if [ -f "$BLIND" ] && [ -f "$APPR" ] \
   && grep -qF 'references/brainstorm-blindspot.md' "$SKILL" \
   && grep -qF 'references/brainstorm-approaches.md' "$SKILL" \
   && grep -qiE "read only when their step.s gate fires, never up front" "$SKILL"; then
  pass "blindspot + divergent-approaches live in gated references, not inline"
else
  fail "heavy mechanisms must stay behind gates in reference files (protects the cost pass)"
fi

# --- 3. BLINDSPOT: the over-firing guard and the headless carve-out are what keep it cheap ---
b_ok=1
grep -qiE "cannot evaluate" "$SKILL" || b_ok=0
grep -qiE "understands the options" "$SKILL" || b_ok=0   # the actual discriminator, not just the label
grep -qiE "undecided\*?, not blindsided" "$SKILL" || b_ok=0
grep -qiE "Never fire in a non-interactive run" "$SKILL" || b_ok=0
grep -qiE "Can.t-evaluate vs hasn.t-decided" "$BLIND" || b_ok=0
grep -qiE "understands the options but hasn.t picked one" "$BLIND" || b_ok=0
grep -qiE "territory-scoped, not conversation-wide" "$BLIND" || b_ok=0
grep -qiE "explicit assumptions" "$BLIND" || b_ok=0
if [ "$b_ok" -eq 1 ]; then
  pass "blindspot pass is over-fire guarded, territory-scoped, and headless-safe"
else
  fail "blindspot pass must guard over-firing, stay territory-scoped, and skip non-interactive runs"
fi

# --- 4. BLINDSPOT budget: walk-throughs are budgeted, not a free extra question path ---
if grep -qiE "count toward the depth question budget" "$BLIND" \
   && grep -qiE "add no separate quota" "$BLIND" \
   && grep -qiE "blindspot walk-through" "$SKILL"; then
  pass "blindspot walk-throughs draw on the depth budget (no separate quota)"
else
  fail "blindspot walk-throughs must be budgeted like rigor probes"
fi

# --- 5. DIVERGENT APPROACHES: divergence comes from DIFFERENT constraints, and there is a fallback ---
a_ok=1
grep -qiE "different.*constraint|a \*\*different\*\* constraint" "$APPR" || a_ok=0
for c in "Smallest thing that works" "Invert the default" "Optimize the common case" "Remove the binding constraint"; do
  grep -qF "$c" "$APPR" || a_ok=0
done
grep -qiE "Fallback — no sub-agent capability" "$APPR" || a_ok=0
grep -qiE "read-only idea generators" "$APPR" || a_ok=0
if [ "$a_ok" -eq 1 ]; then
  pass "approach divergence is constraint-driven, read-only bounded, with a no-sub-agent fallback"
else
  fail "divergent generation needs its distinct constraints, read-only bound, and serial fallback"
fi

# --- 6. DIVERGENT APPROACHES: the anti-genericness bar and convergence handling ---
if grep -qiE "Anti-genericness" "$APPR" \
   && grep -qiE "generic listicle" "$APPR" \
   && grep -qiE "yield \*\*one\*\* approach, not two" "$APPR"; then
  pass "returned approaches clear an anti-genericness bar; convergence yields one approach"
else
  fail "must hold approaches to an anti-genericness bar and collapse convergent ones"
fi

report
