#!/usr/bin/env bash
# Drift guards for en-setup surfacing the optional gnhf dependency (EN06 U2).
# gnhf is the loop engine /en-loop wraps: en-setup offers the install (State 2,
# optional/non-blocking) and reports its status (State 3), like the existing
# optional-tool checks.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-loop setup install"

SETUP="$REPO_ROOT/skills/en-setup/SKILL.md"

# --- en-setup mentions gnhf at all ---
if grep -qF "gnhf" "$SETUP"; then
  pass "en-setup references gnhf"
else
  fail "en-setup must reference the gnhf dependency"
  report
fi

# --- Happy path: State 2 offers the gnhf install (npm i -g gnhf, y/n) ---
if grep -qF "npm i -g gnhf" "$SETUP"; then
  pass "en-setup surfaces the install command 'npm i -g gnhf'"
else
  fail "en-setup must surface 'npm i -g gnhf'"
fi
# the offer is a y/n prompt tied to /en-loop
if grep -qiE "gnhf.*/en-loop|/en-loop.*gnhf" "$SETUP"; then
  pass "en-setup ties the gnhf dependency to /en-loop"
else
  fail "en-setup must explain gnhf is for /en-loop"
fi

# --- Edge: optional / non-blocking framing (never a hard gate) ---
gnhf_block=$(grep -niE "gnhf" "$SETUP" | head -40)
if grep -qiE "optional|never a hard gate|non-?blocking|not.*blocking|only needed for" "$SETUP" \
   && printf '%s' "$gnhf_block" | grep -qiE "optional|only needed for /en-loop|never a hard gate|non-?blocking"; then
  pass "gnhf install is framed optional / non-blocking"
else
  fail "gnhf install must be framed optional (only needed for /en-loop, never blocking)"
fi

# --- Edge: State 3 reports gnhf presence/absence with the install hint ---
# A status check uses command -v gnhf and a 🟡 advisory (not 🔴) when absent.
if grep -qE "command -v gnhf" "$SETUP"; then
  pass "en-setup checks gnhf presence with 'command -v gnhf'"
else
  fail "en-setup must check gnhf presence (command -v gnhf) for the status line"
fi
if grep -qiE "🟡.*gnhf|gnhf.*🟡|advisory.*gnhf|gnhf.*advisory" "$SETUP"; then
  pass "State 3 reports gnhf as a 🟡 advisory when absent (not a hard failure)"
else
  fail "State 3 must report gnhf absence as an advisory, not a blocking 🔴"
fi

# --- gnhf described as agent-agnostic (not Claude/Codex specific) ---
if grep -qiE "agent-agnostic|agent agnostic" "$SETUP"; then
  pass "gnhf noted as agent-agnostic"
else
  fail "en-setup should note gnhf is agent-agnostic"
fi

report
