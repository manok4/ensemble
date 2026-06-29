#!/usr/bin/env bash
# Drift guards for en-review opt-in validator sweep (EN02 U6).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review validator"

EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
REF="$REPO_ROOT/references/validator-dispatch.md"

# --- reference exists + wired ---
if [ -f "$REF" ] && grep -qF "validator-dispatch.md" "$EN_REVIEW"; then
  pass "validator reference exists and is wired into en-review"
else
  fail "validator reference must exist and be wired into en-review"
fi

# --- --validate / --no-validate flags ---
if grep -qF -- "--validate" "$EN_REVIEW" && grep -qF -- "--no-validate" "$EN_REVIEW"; then
  pass "--validate / --no-validate documented"
else
  fail "--validate / --no-validate must be documented"
fi

# --- off the hot path: auto only for P0/P1, capped ---
if grep -qiE "P0/P1 .*only|P0 and P1 .*only|auto.*P0/P1" "$REF" && grep -qiE "capped|cap" "$REF"; then
  pass "auto-run limited to P0/P1, capped"
else
  fail "auto-run must be limited to P0/P1 and capped"
fi

# --- three validator questions ---
if grep -qiE "[Rr]eal\?" "$REF" && grep -qiE "[Ii]ntroduced by THIS diff" "$REF" && grep -qiE "[Nn]ot handled elsewhere" "$REF"; then
  pass "validator re-checks real / introduced-by-diff / not-handled-elsewhere"
else
  fail "validator must re-check the three questions"
fi

# --- drops only P2/P3 on false; NEVER auto-drops P0/P1 (single invariant) ---
if grep -qiE "severity is \*\*P2/P3\*\* . \*\*drop\*\*|P2/P3.* drop" "$REF" && grep -qiE "never auto-drop|NEVER auto-drop" "$REF"; then
  pass "drops only P2/P3 on validated:false; never auto-drops P0/P1"
else
  fail "must drop only P2/P3 and never auto-drop P0/P1"
fi

# --- infra failure keeps finding ---
if grep -qiE "[Ii]nfra failure" "$REF" && grep -qiE "keep the finding|never let a transient" "$REF"; then
  pass "infra failure keeps the finding (no silent removal)"
else
  fail "infra failure must keep the finding"
fi

# --- off the hot path stated ---
if grep -qiE "[Oo]ff the hot path" "$EN_REVIEW"; then
  pass "validator documented as off the hot path"
else
  fail "validator must be documented as off the hot path"
fi

report
