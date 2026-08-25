#!/usr/bin/env bash
# Guards the two-pass finalize loop, its severity gate, and the shared peer invocation.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan finalize loop"

PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- 1. cap is 1 at every depth (two passes max); no depth-scaled cap survives ---
if grep -qiE "Iteration cap: 1 at every depth" "$PLAN" \
   && grep -qiE "at most \*\*two\*\* peer passes" "$PLAN" \
   && ! grep -qE "Lightweight = 1, Standard = 2, Deep = 2" "$PLAN"; then
  pass "finalize loop caps at one re-review (two peer passes max) at every depth"
else
  fail "cap must be 1 at every depth; the old depth-scaled cap must be gone"
fi

# --- 2. the re-loop is severity-gated: advisory-only results exit instead of re-reviewing ---
if grep -qiE "Severity gate on the re-loop" "$PLAN" \
   && grep -qiE "only if at least one finding this pass was .P0. or .P1." "$PLAN" \
   && grep -qF "reloop_skipped: advisory-only" "$PLAN"; then
  pass "re-loop fires only on P0/P1; advisory-only passes exit auditably"
else
  fail "re-loop must be severity-gated with an auditable advisory-only exit"
fi

# --- 3. the escape hatch survives (a cap change must not remove the override) ---
if grep -qF -- "--max-iterations" "$PLAN" && grep -qF -- "--no-reloop" "$PLAN"; then
  pass "--max-iterations and --no-reloop escape hatches retained"
else
  fail "capping the loop must not remove the manual overrides"
fi

report
