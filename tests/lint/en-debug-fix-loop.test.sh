#!/usr/bin/env bash
# Drift guards for en-debug code-mode fix loop (FR01 U9).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-debug fix loop"

EN_DEBUG="$REPO_ROOT/skills/en-debug/SKILL.md"
REF="$REPO_ROOT/shared/references/debug-investigation.md"

# --- two modes documented ---
if grep -qiE "Telemetry mode" "$EN_DEBUG" && grep -qiE "Code mode" "$EN_DEBUG"; then
  pass "en-debug documents telemetry mode + code mode"
else
  fail "en-debug must document both telemetry and code modes"
fi

# --- telemetry mode still read-only ---
if grep -qiE "Never writes code in telemetry mode|read-only" "$EN_DEBUG"; then
  pass "telemetry mode preserved as read-only"
else
  fail "telemetry mode must remain read-only"
fi

# --- causal-chain gate ---
if grep -qiE "[Cc]ausal.chain gate" "$EN_DEBUG"; then
  pass "code mode has causal-chain gate"
else
  fail "code mode must have a causal-chain gate"
fi

# --- test-first fix ---
if grep -qiE "test-first" "$EN_DEBUG"; then
  pass "code-mode fix is test-first"
else
  fail "code-mode fix must be test-first"
fi

# --- fix is opt-in (Fix it now / Diagnosis only) ---
if grep -qiE "Fix it now" "$EN_DEBUG" && grep -qiE "Diagnosis only" "$EN_DEBUG"; then
  pass "fix is opt-in (Fix it now / Diagnosis only choice)"
else
  fail "fix must be opt-in with a diagnosis-only choice"
fi

# --- one change at a time / anti-shotgun ---
if grep -qiE "one change at a time" "$EN_DEBUG"; then
  pass "states one-change-at-a-time principle"
else
  fail "must state one-change-at-a-time principle"
fi

# --- investigation reference exists and is wired ---
if [ -f "$REF" ] && grep -qF "debug-investigation.md" "$EN_DEBUG"; then
  pass "debug-investigation reference exists and is referenced"
else
  fail "debug-investigation reference must exist and be wired into en-debug"
fi

# --- reference has anti-patterns + escalation ---
if grep -qiE "[Aa]nti-pattern" "$REF" && grep -qiE "[Ss]mart escalation" "$REF"; then
  pass "reference documents anti-patterns + smart escalation"
else
  fail "reference must document anti-patterns + smart escalation"
fi
