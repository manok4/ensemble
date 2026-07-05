#!/usr/bin/env bash
# Drift guards for en-brainstorm AskUserQuestion default + open-vs-closed discipline (EN05 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm elicitation"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
SOCRATIC="$REPO_ROOT/references/socratic-questions.md"

# --- Q&A loop defaults to the HOST-NEUTRAL blocking question tool (QUESTION_TOOL), not hardcoded ---
if grep -qF 'QUESTION_TOOL' "$SKILL" && grep -qiE "request_user_input" "$SKILL" && grep -qF 'QUESTION_TOOL' "$SOCRATIC"; then
  pass "Q&A loop defaults to host-neutral \$QUESTION_TOOL (AskUserQuestion / request_user_input)"
else
  fail "Q&A loop must default to host-neutral \$QUESTION_TOOL, not a hardcoded tool"
fi
# guard against re-hardcoding: the SKILL must NOT say "default to AskUserQuestion" as the contract
if grep -qiE "Default to .?AskUserQuestion" "$SKILL"; then
  fail "must not hardcode 'default to AskUserQuestion' (breaks Codex host portability)"
else
  pass "does not hardcode AskUserQuestion as the default (host-portable)"
fi

# --- open-vs-closed discipline (reserve open-ended for genuinely-open) ---
if grep -qiE "Open-vs-closed discipline" "$SKILL" && grep -qiE "3.4 distinct|3-4 distinct|straining to fill|strain to fill" "$SKILL"; then
  pass "SKILL documents the open-vs-closed discipline"
else
  fail "SKILL must document the open-vs-closed discipline"
fi
if grep -qiE "Open-vs-closed discipline|reserve open-ended|can.t write 3" "$SOCRATIC"; then
  pass "socratic-questions documents the open-vs-closed discipline"
else
  fail "socratic-questions must document the open-vs-closed discipline"
fi

# --- harness fallback to numbered chat options (never silently skip) ---
if grep -qiE "no blocking question tool exists|no blocking tool exists" "$SKILL" && grep -qiE "never silently skip" "$SKILL"; then
  pass "harness fallback documented (numbered options; never silently skip)"
else
  fail "SKILL must document the harness fallback (never silently skip)"
fi

# --- one-question-per-turn preserved ---
if grep -qiE "One question per turn|One per turn" "$SKILL"; then
  pass "one-question-per-turn preserved"
else
  fail "one-question-per-turn rule must survive"
fi

report
