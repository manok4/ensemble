#!/usr/bin/env bash
# Drift guards for the shared diff-signal-detection reference (FR01 U4).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="diff-signal detection"

REF="$REPO_ROOT/skills/en-build/references/diff-signal-detection.md"

if [ -f "$REF" ]; then
  pass "diff-signal-detection.md exists"
else
  fail "diff-signal-detection.md missing"
fi

# --- fail-closed contract stated ---
if grep -qiE "fail.closed" "$REF"; then
  pass "states fail-closed contract"
else
  fail "must state fail-closed contract"
fi

# --- frontend patterns present ---
if grep -qF ".tsx" "$REF" && grep -qF "components/" "$REF"; then
  pass "documents frontend/UI patterns"
else
  fail "must document frontend/UI patterns"
fi

# --- risk-surface patterns present ---
if grep -qiE "auth" "$REF" && grep -qiE "migrations/" "$REF" && grep -qiE "payment" "$REF"; then
  pass "documents risk-surface patterns (auth/migrations/payments)"
else
  fail "must document risk-surface patterns"
fi

# --- uncounted-file rule (any non-code file → not small) ---
if grep -qiE "UNCOUNTED_FILES" "$REF"; then
  pass "documents uncounted-file rule"
else
  fail "must document the uncounted-file rule"
fi

# --- both classifications defined ---
if grep -qF "is_small_and_safe" "$REF"; then
  pass "defines is_small_and_safe (en-review lite gate)"
else
  fail "must define is_small_and_safe"
fi
if grep -qF "needs_browser" "$REF"; then
  pass "defines needs_browser (en-qa browser gate)"
else
  fail "must define needs_browser"
fi

# --- flag override does not beat the fail-closed gate (lite) ---
if grep -qiE "lite.*does not override|gate wins" "$REF"; then
  pass "lite flag cannot override a false small/safe result"
else
  fail "must state lite flag cannot override the gate"
fi

report
