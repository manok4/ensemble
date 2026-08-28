#!/usr/bin/env bash
# Drift guards for en-review --lite roster (FR01 U5).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review --lite"

EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
PERSONA="$REPO_ROOT/skills/en-build/references/persona-dispatch.md"

# --- flag documented ---
if grep -qF -- "--lite" "$EN_REVIEW"; then
  pass "--lite documented in en-review"
else
  fail "--lite missing from en-review"
fi

# --- references the shared signal detector ---
if grep -qF "diff-signal-detection.md" "$EN_REVIEW"; then
  pass "en-review --lite uses diff-signal-detection reference"
else
  fail "en-review --lite must use diff-signal-detection reference"
fi

# --- lite roster persona set ---
if grep -qiE "correctness.*standards|standards.*correctness" "$EN_REVIEW" && grep -qF "fast-pass" "$EN_REVIEW"; then
  pass "lite roster = correctness + standards + fast-pass"
else
  fail "lite roster must be correctness + standards + fast-pass"
fi

# --- fail-closed override stated in skill ---
if grep -qiE "fail closed|full roster regardless|gate wins" "$EN_REVIEW"; then
  pass "en-review --lite states fail-closed override"
else
  fail "en-review --lite must state fail-closed override"
fi

# --- persona-dispatch documents the lite roster ---
if grep -qiE "Lite roster" "$PERSONA"; then
  pass "persona-dispatch documents the lite roster"
else
  fail "persona-dispatch must document the lite roster"
fi

# --- fast-pass confidence cap documented ---
if grep -qiE "anchor 50|cap.*fast-pass|fast-pass.*cap" "$PERSONA"; then
  pass "persona-dispatch documents fast-pass confidence cap"
else
  fail "persona-dispatch must document fast-pass confidence cap"
fi
