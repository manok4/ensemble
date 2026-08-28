#!/usr/bin/env bash
# Drift guards for the /en-flow pipeline skill (FR01 U13).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-flow pipeline"

FLOW="$REPO_ROOT/skills/en-flow/SKILL.md"
REF="$REPO_ROOT/skills/en-flow/references/en-flow-pipeline.md"

# --- skill exists + helper header + recursion guard ---
if [ -f "$FLOW" ]; then pass "en-flow SKILL.md exists"; else fail "en-flow SKILL.md missing"; fi
# The $ENSEMBLE_ROOT helper-resolution header was retired by EN13, when skills
# became self-contained and stopped resolving paths through an install root. This
# assertion outlived the convention; it was invisible because the suite had no
# report call and so could never fail.
if grep -qF "ENSEMBLE_PEER_REVIEW=true" "$FLOW"; then pass "en-flow has recursion guard"; else fail "en-flow missing recursion guard"; fi

# --- manual-invoke only ---
if grep -qF "disable-model-invocation: true" "$FLOW"; then
  pass "en-flow is manual-invoke only"
else
  fail "en-flow must be manual-invoke only (disable-model-invocation: true)"
fi

# --- stage order: plan -> build -> learn -> ship ---
plan_l=$(grep -n "Stage 1 — Plan" "$FLOW" | head -1 | cut -d: -f1)
build_l=$(grep -n "Stage 2 — Build" "$FLOW" | head -1 | cut -d: -f1)
learn_l=$(grep -n "Stage 3 — Learn" "$FLOW" | head -1 | cut -d: -f1)
ship_l=$(grep -n "Stage 4 — Ship" "$FLOW" | head -1 | cut -d: -f1)
if [ -n "$plan_l" ] && [ -n "$build_l" ] && [ -n "$learn_l" ] && [ -n "$ship_l" ] \
   && [ "$plan_l" -lt "$build_l" ] && [ "$build_l" -lt "$learn_l" ] && [ "$learn_l" -lt "$ship_l" ]; then
  pass "stages ordered plan → build → learn → ship"
else
  fail "stages must be ordered plan → build → learn → ship"
fi

# --- invokes the lifecycle skills ---
for sk in "/en-plan" "/en-build" "/en-learn" "/en-ship"; do
  if grep -qF "$sk" "$FLOW"; then pass "en-flow invokes $sk"; else fail "en-flow must invoke $sk"; fi
done

# --- learn stage is model-decided + no double-capture ---
if grep -qiE "model decides|model-decided" "$FLOW" && grep -qiE "double-capture|no-op" "$FLOW"; then
  pass "learn stage is model-decided with no double-capture"
else
  fail "learn stage must be model-decided + avoid double-capture"
fi

# --- never auto-merges ---
if grep -qiE "[Nn]ever (auto-merge|merges)|No auto-merge" "$FLOW"; then
  pass "en-flow never auto-merges"
else
  fail "en-flow must never auto-merge"
fi

# --- shipping precondition (local-only when no remote) ---
if grep -qiE "local.only|no remote" "$FLOW"; then
  pass "en-flow handles the no-remote (local-only) precondition"
else
  fail "en-flow must handle the no-remote precondition"
fi

# --- flags documented ---
for fl in "--plan" "--no-ship" "--no-watch"; do
  if grep -qF -- "$fl" "$FLOW"; then pass "flag documented: $fl"; else fail "flag missing: $fl"; fi
done

# --- does NOT re-run simplify/review at top level (delegated to en-build) ---
if grep -qiE "does \*\*not\*\* re-run|never re-run.*simplify|inside en-build" "$FLOW"; then
  pass "en-flow does not re-run simplify/review at top level"
else
  fail "en-flow must delegate simplify/review to en-build"
fi

# --- reference exists ---
if [ -f "$REF" ] && grep -qF "en-flow-pipeline.md" "$FLOW"; then
  pass "en-flow-pipeline reference exists and is wired"
else
  fail "en-flow-pipeline reference must exist and be wired"
fi

report
