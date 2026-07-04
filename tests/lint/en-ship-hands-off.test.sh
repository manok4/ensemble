#!/usr/bin/env bash
# Drift guards for hands-off en-ship preflight + learning-checkpoint removal (EN04 U2).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-ship hands-off"

EN_SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- hands-off default documented ---
if grep -qiE "hands-off by default" "$EN_SHIP"; then
  pass "en-ship documents the hands-off default"
else
  fail "en-ship must document the hands-off default"
fi

# --- learning checkpoint removed (heading + outcome field gone) ---
if grep -qE "^4\. \*\*Learning checkpoint\*\*|learning_checkpoint:" "$EN_SHIP"; then
  fail "en-ship must NOT carry a learning checkpoint (relocated to en-build)"
else
  pass "en-ship no longer carries a learning checkpoint step or outcome field"
fi

# --- --interactive escape hatch ---
if grep -qE '`--interactive`' "$EN_SHIP" && grep -qiE "stop-and-ask|escape hatch" "$EN_SHIP"; then
  pass "en-ship documents the --interactive escape hatch"
else
  fail "en-ship must document the --interactive escape hatch"
fi

# --- safety floor with all three hard-stops ---
floor_ok=1
grep -qiE "[Ss]afety floor" "$EN_SHIP" || floor_ok=0
grep -qiE "[Ss]ecret-scan" "$EN_SHIP" || floor_ok=0
grep -qiE "default branch" "$EN_SHIP" || floor_ok=0
grep -qiE "guardrail" "$EN_SHIP" || floor_ok=0
grep -qiE "hard-stop" "$EN_SHIP" || floor_ok=0
if [ "$floor_ok" -eq 1 ]; then
  pass "en-ship documents the safety floor (secrets / default-branch / destructive hard-stops)"
else
  fail "en-ship must document the full safety floor as hard-stops"
fi

# --- plan-completion auto-resolve, both branches ---
if grep -qiE "auto-select \`y\`|auto-\`y\`" "$EN_SHIP" && grep -qE "incomplete_build" "$EN_SHIP"; then
  pass "en-ship plan-completion auto-resolves (auto-y complete / informational incomplete)"
else
  fail "en-ship plan-completion must auto-resolve under hands-off"
fi

# --- D38 in foundation names hands-off + relocation ---
d38="$(grep -E "^- \*\*D38\." "$FOUNDATION" || true)"
if [ -n "$d38" ] && printf '%s' "$d38" | grep -qiE "hands-off" && printf '%s' "$d38" | grep -qiE "relocat"; then
  pass "foundation D38 records hands-off + learning-checkpoint relocation"
else
  fail "foundation D38 must record hands-off en-ship + the relocation"
fi

report
