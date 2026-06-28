#!/usr/bin/env bash
# Drift guards for en-qa browser-phase detector (FR01 U6).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-qa browser detector"

EN_QA="$REPO_ROOT/skills/en-qa/SKILL.md"

# --- detector step present ---
if grep -qiE "Browser-phase detector" "$EN_QA"; then
  pass "en-qa has a browser-phase detector step"
else
  fail "en-qa missing browser-phase detector step"
fi

# --- uses the shared signal reference ---
if grep -qF "diff-signal-detection.md" "$EN_QA"; then
  pass "detector uses diff-signal-detection reference"
else
  fail "detector must use diff-signal-detection reference"
fi

# --- needs_browser gating ---
if grep -qF "needs_browser" "$EN_QA"; then
  pass "detector gates on needs_browser"
else
  fail "detector must gate on needs_browser"
fi

# --- --browser flag documented ---
if grep -qF -- "--browser" "$EN_QA"; then
  pass "--browser flag documented"
else
  fail "--browser flag missing"
fi

# --- fail-closed (unclassifiable diff → run browser) ---
if grep -qiE "fail closed" "$EN_QA"; then
  pass "detector states fail-closed (run browser when unclassifiable)"
else
  fail "detector must state fail-closed behavior"
fi

# --- system-only still skips and wins over --browser ---
if grep -qiE "system-only.*win|wins over .*browser|--system-only.* always skip" "$EN_QA"; then
  pass "--system-only wins over --browser"
else
  fail "--system-only must win over --browser"
fi

# --- auto-skip reason listed in skip section ---
if grep -qiE "[Nn]o frontend files changed" "$EN_QA"; then
  pass "no-frontend auto-skip reason documented"
else
  fail "no-frontend auto-skip reason must be documented"
fi
