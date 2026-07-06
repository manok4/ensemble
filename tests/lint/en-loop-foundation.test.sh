#!/usr/bin/env bash
# Drift guards for foundation D40 + the en-loop skill-catalog entry (EN06 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-loop foundation"

FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- D40 exists and names en-loop ---
d40="$(grep -E "^- \*\*D40\." "$FOUNDATION" || true)"
if [ -n "$d40" ] && printf '%s' "$d40" | grep -qiE "en-loop"; then
  pass "foundation has D40 naming en-loop"
else
  fail "foundation must add D40 for en-loop"
  report
fi

# --- D40 names the wrap-gnhf engine choice ---
if printf '%s' "$d40" | grep -qiE "wrap.*gnhf|gnhf.*wrap"; then
  pass "D40 records the wrap-gnhf engine choice"
else
  fail "D40 must record wrapping gnhf (not native)"
fi

# --- D40 records the test-gate + checkpoint-review cadence ---
if printf '%s' "$d40" | grep -qiE "test-gate" && printf '%s' "$d40" | grep -qiE "checkpoint|--review-every|en-review"; then
  pass "D40 records the test-gate-per-iteration + checkpoint-review cadence"
else
  fail "D40 must record the test-gate + checkpoint-review cadence"
fi

# --- D40 records the two modes ---
if printf '%s' "$d40" | grep -qiE "Hands-Off" && printf '%s' "$d40" | grep -qiE "Companion"; then
  pass "D40 records the two modes (Hands-Off, Companion)"
else
  fail "D40 must record the Hands-Off and Companion modes"
fi

# --- Integration: 'completion is not acceptance' + evidence-based stop appear in D40 ---
if printf '%s' "$d40" | grep -qiE "completion is not acceptance|completion ≠ acceptance"; then
  pass "D40 states 'completion is not acceptance'"
else
  fail "D40 must state the completion-is-not-acceptance rule"
fi
if printf '%s' "$d40" | grep -qiE "evidence-based stop|evidence-based.*stop-when|evidence-based condition"; then
  pass "D40 requires evidence-based stop conditions"
else
  fail "D40 must require evidence-based stop conditions"
fi

# --- D40 notes the external gnhf dependency surfaced by en-setup ---
if printf '%s' "$d40" | grep -qiE "npm i -g gnhf|en-setup"; then
  pass "D40 notes the gnhf dependency surfaced by en-setup"
else
  fail "D40 must note the external gnhf dependency (en-setup surfaces it)"
fi

# --- Catalog §5.1 table has an en-loop row ---
if grep -qE "^\| *[0-9]+ *\| \`en-loop\`" "$FOUNDATION"; then
  pass "§5.1 skill-summary table has an en-loop row"
else
  fail "§5.1 table must add an en-loop row"
fi

# --- Catalog §5.2.x details subsection for en-loop ---
if grep -qE "^#### 5\.2\.[0-9]+ \`en-loop\`" "$FOUNDATION"; then
  pass "§5.2.x has an en-loop details subsection"
else
  fail "§5.2.x must add an en-loop details subsection"
fi

# --- Catalog header count updated (Fifteen) + en-loop in the orthogonal list ---
if grep -qiE "Fifteen skills total" "$FOUNDATION"; then
  pass "§5 header updated to fifteen skills"
else
  fail "§5 header must update the skill count to fifteen"
fi
# en-loop listed among the orthogonal skills in the §5 intro line
if grep -E "Fifteen skills total" "$FOUNDATION" | grep -qF "en-loop"; then
  pass "§5 intro lists en-loop among the orthogonal skills"
else
  fail "§5 intro must list en-loop among the orthogonal skills"
fi

report
