#!/usr/bin/env bash
# Drift guards for the /en-simplify skill (FR01 U1).
# Per docs/plans/active/FR01-improvement_skill-suite-optimization.md.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-simplify skill"

EN_SIMPLIFY="$REPO_ROOT/skills/en-simplify/SKILL.md"

# --- skill exists ---
if [ -f "$EN_SIMPLIFY" ]; then
  pass "en-simplify SKILL.md exists"
else
  fail "en-simplify SKILL.md missing"
fi

# --- helper-resolution header ---
if grep -qF 'Helper resolution.' "$EN_SIMPLIFY"; then
  pass "en-simplify has helper-resolution header"
else
  fail "en-simplify missing helper-resolution header"
fi

# --- recursion guard ---
if grep -qF "ENSEMBLE_PEER_REVIEW=true" "$EN_SIMPLIFY"; then
  pass "en-simplify has recursion guard"
else
  fail "en-simplify missing recursion guard"
fi

# --- three review dimensions ---
for dim in "Reuse" "Quality" "Efficiency"; do
  if grep -qE "Dimension [0-9] — $dim" "$EN_SIMPLIFY"; then
    pass "en-simplify declares dimension: $dim"
  else
    fail "en-simplify missing dimension: $dim"
  fi
done

# --- behavior-preserving contract ---
if grep -qiE "behavior-preserving|preserves behavior|preserve.*behavior" "$EN_SIMPLIFY"; then
  pass "en-simplify states behavior-preserving contract"
else
  fail "en-simplify missing behavior-preserving contract"
fi

# --- never removes safety checks ---
if grep -qiE "never simplif.*safety|safety check" "$EN_SIMPLIFY"; then
  pass "en-simplify forbids removing safety checks"
else
  fail "en-simplify should forbid removing safety checks"
fi

# --- default scope = branch diff vs base ---
if grep -qiE "current branch and its base|branch diff vs base|diff between the current branch" "$EN_SIMPLIFY"; then
  pass "en-simplify default scope = branch diff vs base"
else
  fail "en-simplify should default scope to branch diff vs base"
fi

# --- does not commit ---
if grep -qiE "[Dd]oes not commit|[Nn]ever commits" "$EN_SIMPLIFY"; then
  pass "en-simplify documents no-commit policy"
else
  fail "en-simplify should document no-commit policy"
fi

# --- reuses the code-simplifier agent ---
if grep -qF "agents/code-simplifier.md" "$EN_SIMPLIFY"; then
  pass "en-simplify reuses the code-simplifier agent"
else
  fail "en-simplify should reuse the code-simplifier agent"
fi

report
