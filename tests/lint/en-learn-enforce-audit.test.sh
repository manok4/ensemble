#!/usr/bin/env bash
# tests/lint/en-learn-enforce-audit.test.sh
#
# EN22 U5. --enforce-audit applies the enforcement rubric to a repo's existing
# prose rules. It is a reference, not a script: map files are short, so the model
# reads them whole. Each clause is anchored on one file.
#
# SCOPE (TD7): which layer a rule gets is a model judgment and is not asserted.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn --enforce-audit"

SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"
AUDIT="$REPO_ROOT/skills/en-learn/references/enforce-audit.md"

# --- the mode is listed and reaches its reference ---
modes=$(sed -n '/^## Modes/,/^## /p' "$SKILL")
printf '%s' "$modes" | grep -F '`--enforce-audit`' | grep -qF 'references/enforce-audit.md' \
  && pass "the modes table lists --enforce-audit and points at its reference" \
  || fail "the modes table lists --enforce-audit and points at its reference"

assert_file_exists "$AUDIT" "the audit reference exists"

# --- the reference's procedure ---
for f in 'AGENTS.md' 'CLAUDE.md' 'REVIEW.md'; do
  grep -qF "\`$f\`" "$AUDIT" && pass "the audit reads $f" || fail "the audit reads $f"
done
grep -qiF 'open the cited file' "$AUDIT" \
  && pass "a rule that cites a check is confirmed against the cited file" \
  || fail "a rule that cites a check is confirmed against the cited file"
grep -qF '`$SKILL_DIR/scripts/ensemble-td-append`' "$AUDIT" \
  && pass "entries are filed through the appender" || fail "entries are filed through the appender"
grep -qiF "reusing an open entry's key" "$AUDIT" \
  && pass "keys are reused, so reruns converge" \
  || fail "keys are reused, so reruns converge"
grep -qiF 'not in the canonical layout' "$AUDIT" \
  && pass "an unwritable tracker is reported, not silently skipped" \
  || fail "an unwritable tracker is reported, not silently skipped"
grep -qiF 'writes no learning' "$AUDIT" \
  && pass "the audit writes no learning files" || fail "the audit writes no learning files"
grep -qF 'enforcement-layers.md' "$AUDIT" \
  && pass "the audit classifies with the shared rubric" || fail "the audit classifies with the shared rubric"

report
