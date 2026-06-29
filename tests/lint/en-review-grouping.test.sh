#!/usr/bin/env bash
# Drift guards for en-review thematic triage grouping (EN02 U5).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review grouping"

EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
PERSONA="$REPO_ROOT/references/persona-dispatch.md"

# --- grouping step present ---
if grep -qiE "Thematic triage grouping" "$EN_REVIEW"; then
  pass "en-review has a thematic grouping step"
else
  fail "en-review must have a thematic grouping step"
fi

# --- grouping never merges / alters findings ---
if grep -qiE "never merges findings into a synthetic finding" "$EN_REVIEW" && grep -qiE "at most one" "$EN_REVIEW"; then
  pass "grouping never merges/alters; a finding is in at most one group"
else
  fail "grouping must never merge/alter findings; at most one group per finding"
fi

# --- grouping tokens ---
if grep -qiE "grouping:auto" "$EN_REVIEW" && grep -qiE "grouping:off" "$EN_REVIEW" && grep -qiE "grouping:always" "$EN_REVIEW"; then
  pass "grouping:auto/off/always tokens documented"
else
  fail "grouping:auto/off/always tokens must be documented"
fi

# --- pruning post-gate / post-apply ---
if grep -qiE "[Pp]rune.*dropped|prune.*applied|dropped \(post-gate\)|applied \(post-apply\)" "$EN_REVIEW"; then
  pass "group pruning post-gate / post-apply documented"
else
  fail "group pruning post-gate / post-apply must be documented"
fi

# --- triage_groups in output (markdown + JSON envelope) ---
if grep -qF "triage_groups" "$EN_REVIEW"; then
  pass "triage_groups in output envelope"
else
  fail "triage_groups must be in the output envelope"
fi

# --- persona-dispatch documents grouping ---
if grep -qiE "Thematic grouping" "$PERSONA"; then
  pass "persona-dispatch documents thematic grouping"
else
  fail "persona-dispatch must document thematic grouping"
fi

report
