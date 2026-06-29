#!/usr/bin/env bash
# Drift guards for en-review tiered peer-default model (EN02 U2).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review tiered model"

EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
SIGNAL="$REPO_ROOT/references/diff-signal-detection.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- is_high_stakes classifier ---
if grep -qF "is_high_stakes" "$SIGNAL"; then
  pass "diff-signal-detection defines is_high_stakes"
else
  fail "diff-signal-detection must define is_high_stakes"
fi
if grep -qiE "EXEC_LINES >= 150|>= 150" "$SIGNAL" && grep -qiE "fail closed to .true.|fail-closed to .true|fail closed" "$SIGNAL"; then
  pass "is_high_stakes uses >=150 lines + fail-closed"
else
  fail "is_high_stakes must use >=150 lines + fail-closed"
fi

# --- tier selection step ---
if grep -qiE "Tier selection" "$EN_REVIEW"; then
  pass "en-review has a tier-selection step"
else
  fail "en-review must have a tier-selection step"
fi

# --- three tiers ---
for tier in "Lite" "Standard" "Adversarial"; do
  if grep -qE "\*\*$tier\*\*" "$EN_REVIEW"; then
    pass "tier documented: $tier"
  else
    fail "tier missing: $tier"
  fi
done

# --- peer is reviewer of record in non-adversarial tiers ---
if grep -qiE "peer is the reviewer of record" "$EN_REVIEW"; then
  pass "peer is reviewer of record in non-adversarial tiers"
else
  fail "peer must be reviewer of record in non-adversarial tiers"
fi

# --- host personas dispatch only in Adversarial ---
if grep -qiE "Adversarial tier only|Skipped in Lite/Standard|dispatch only in the Adversarial" "$EN_REVIEW"; then
  pass "host persona dispatch is Adversarial-only"
else
  fail "host persona dispatch must be Adversarial-only"
fi

# --- flags ---
if grep -qF -- "--adversarial" "$EN_REVIEW" && grep -qF -- "--host-only" "$EN_REVIEW"; then
  pass "--adversarial and --host-only documented"
else
  fail "--adversarial and --host-only must be documented"
fi

# --- foundation D36 ---
if grep -qE "^- \*\*D36\." "$FOUNDATION" && grep -qiE "peer-default" "$FOUNDATION"; then
  pass "foundation D36 records the tiered peer-default model"
else
  fail "foundation D36 must record the tiered peer-default model"
fi
