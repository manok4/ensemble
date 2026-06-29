#!/usr/bin/env bash
# Drift guards for en-review adversarial reconciliation (EN02 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review adversarial reconciliation"

EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
RECON="$REPO_ROOT/references/adversarial-reconciliation.md"

# --- reconciliation reference exists + wired ---
if [ -f "$RECON" ] && grep -qF "adversarial-reconciliation.md" "$EN_REVIEW"; then
  pass "reconciliation reference exists and is wired into en-review"
else
  fail "reconciliation reference must exist and be wired into en-review"
fi

# --- en-review has the reconciliation step (adversarial only) ---
if grep -qiE "Adversarial reconciliation \(Adversarial tier only\)" "$EN_REVIEW"; then
  pass "en-review has the adversarial-only reconciliation step"
else
  fail "en-review must have an Adversarial-only reconciliation step"
fi

# --- independence stated (peer never sees H) ---
if grep -qiE "without seeing H|never with H|never sees H|independent" "$RECON"; then
  pass "reconciliation requires independent peer (peer never sees H)"
else
  fail "reconciliation must require an independent peer"
fi

# --- agreement promotes + marks worth_fixing ---
if grep -qiE "promote one .*anchor" "$RECON" && grep -qF "worth_fixing" "$RECON"; then
  pass "agreement promotes an anchor and marks worth_fixing"
else
  fail "agreement must promote an anchor and mark worth_fixing"
fi

# --- single-source needs evidence to survive ---
if grep -qiE "single-source" "$RECON" && grep -qiE "quote-the-line|first_evidence" "$RECON"; then
  pass "single-source findings need quote-the-line evidence to survive"
else
  fail "single-source findings must need evidence to survive"
fi

# --- fingerprint dedup ---
if grep -qiE "line_bucket|line.?.3|±3" "$RECON"; then
  pass "reconciliation fingerprints with line proximity"
else
  fail "reconciliation must fingerprint with line proximity"
fi

# --- cross-model agreement = strongest signal ---
if grep -qiE "cross-model agreement|strongest signal" "$RECON"; then
  pass "cross-model agreement noted as strongest signal"
else
  fail "cross-model agreement must be the strongest signal"
fi
