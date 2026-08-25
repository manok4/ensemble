#!/usr/bin/env bash
# Behavior guards for en-brainstorm elicitation (EN05 U3, recalibrated).
# Guards HOW the skill asks, not how the rule is worded.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm elicitation"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"

# --- 1. host-neutral blocking question tool (portability across Claude Code / Codex) ---
if grep -qF 'QUESTION_TOOL' "$SKILL" && grep -qF 'request_user_input' "$SKILL" && grep -qF 'AskUserQuestion' "$SKILL"; then
  pass "elicitation routes through host-neutral \$QUESTION_TOOL (both hosts named)"
else
  fail "elicitation must route through \$QUESTION_TOOL and name both host tools"
fi

# --- 2. NEGATIVE CONTROL: must not re-hardcode one host's tool as the contract ---
if grep -qiE "Default to .?\*{0,2}AskUserQuestion" "$SKILL"; then
  fail "must not hardcode 'default to AskUserQuestion' (breaks Codex host portability)"
else
  pass "does not hardcode AskUserQuestion as the default (host-portable)"
fi

# --- 3. open-vs-closed discipline: open-ended is the exception, with a decidable test ---
if grep -qiE "Open-vs-closed discipline" "$SKILL" && grep -qF "distinct, plausibly-correct" "$SKILL" && grep -qF "straining to fill" "$SKILL"; then
  pass "open-vs-closed discipline carries a decidable test (can you write 3-4 real options?)"
else
  fail "open-vs-closed discipline must carry its decidable test, not just a preference"
fi

# --- 4. a question is never silently dropped when the harness has no blocking tool ---
if grep -qiE "no blocking question tool exists" "$SKILL" && grep -qiE "never silently skip" "$SKILL"; then
  pass "harness fallback documented (numbered options; never silently skip)"
else
  fail "SKILL must document the harness fallback and forbid silently skipping"
fi

report
