#!/usr/bin/env bash
# Drift guards for the structured learning checkpoint relocated to en-build (EN04 U1).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build learning checkpoint"

EN_BUILD="$REPO_ROOT/skills/en-build/SKILL.md"

# --- structured checkpoint present in en-build ---
if grep -qE "Learning checkpoint\*\* \(structured" "$EN_BUILD"; then
  pass "en-build has a structured (non-droppable) learning checkpoint"
else
  fail "en-build must have a structured learning checkpoint at completion"
fi

# --- emits the outcome line ---
if grep -qE "learning_checkpoint:" "$EN_BUILD"; then
  pass "en-build emits a learning_checkpoint: outcome line"
else
  fail "en-build must emit a learning_checkpoint: outcome line"
fi

# --- idempotency (up_to_date) documented ---
if grep -qE "up_to_date" "$EN_BUILD" && grep -qiE "zero commits|idempotency" "$EN_BUILD"; then
  pass "en-build documents the up_to_date idempotency branch"
else
  fail "en-build must document the up_to_date idempotency branch"
fi

# --- CI short-circuit (ci_environment) ---
if grep -qE "ci_environment" "$EN_BUILD" && grep -qE "CI=true" "$EN_BUILD"; then
  pass "en-build documents the ci_environment short-circuit"
else
  fail "en-build must document the CI=true → ci_environment short-circuit"
fi

# --- deferral when peer-evidence audit failed ---
if grep -qiE "defer" "$EN_BUILD" && grep -qiE "peer-evidence audit failed" "$EN_BUILD"; then
  pass "en-build defers the checkpoint when the peer-evidence audit failed"
else
  fail "en-build must defer the checkpoint on a failed peer-evidence audit"
fi

# --- four canonical outcome values present ---
canon_ok=1
for v in "captured (N learnings)" "intentionally_skipped" "up_to_date" "ci_environment"; do
  grep -qF "$v" "$EN_BUILD" || canon_ok=0
done
if [ "$canon_ok" -eq 1 ]; then
  pass "en-build spells all four canonical outcome values"
else
  fail "en-build must spell all four canonical outcome values exactly"
fi

# --- bare 'skipped' is not used as an outcome value ---
if grep -qE "learning_checkpoint: skipped([^_]|$)" "$EN_BUILD"; then
  fail "bare 'skipped' must not be used as an outcome value (use intentionally_skipped)"
else
  pass "no bare 'skipped' outcome value in en-build"
fi

# The relocation used to be asserted against a design spec in docs/. That spec
# has been retired, and the assertion went with it: it checked that a DOCUMENT
# described the move, not that the behaviour was where it belonged. The
# assertions above already pin the checkpoint to en-build, which is the thing
# that matters.

report
