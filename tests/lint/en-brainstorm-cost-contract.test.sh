#!/usr/bin/env bash
# Guards the cost-pass wins that would otherwise silently regress:
#   1. the foundation.md scan stays bounded (it was ~51K tokens unbounded)
#   2. the design doc is validated before /en-plan consumes it

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm cost contract"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
DISPATCH="$REPO_ROOT/references/research-dispatch.md"

# --- 1. the context scan is bounded: section-index first, never the whole file ---
if grep -qiE "Existing-context scan \(bounded\)" "$SKILL" \
   && grep -qF "grep -n '^#' docs/foundation.md" "$SKILL" \
   && grep -qiE "Never .cat. it whole" "$SKILL" \
   && grep -qiE "index only" "$SKILL"; then
  pass "foundation/learnings scan is bounded (section index; never read whole)"
else
  fail "step 4 must stay bounded — section-index read, never a whole-file read"
fi

# --- 2. the design doc is linted before handoff, and brainstorm dispatches no scouts ---
if grep -qF '$ENSEMBLE_ROOT/bin/ensemble-lint --scope docs/designs' "$SKILL" \
   && grep -qiE "dispatches no scouts" "$DISPATCH"; then
  pass "design doc is lint-validated before handoff; no-scout contract is documented"
else
  fail "must lint the design doc before handoff and document the no-scout contract"
fi

report
