#!/usr/bin/env bash
# Drift guards for the /en-ship learning checkpoint (en-learn-checkpoint-spec).
# Per the spec at docs/en-learn-checkpoint-spec.md.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn checkpoint"

EN_SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
EN_QA="$REPO_ROOT/skills/en-qa/SKILL.md"
EN_LEARN="$REPO_ROOT/skills/en-learn/SKILL.md"
LOG_FORMAT="$REPO_ROOT/references/learn-log-format.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- en-ship preflight has a learning checkpoint ---
if grep -qF "Learning checkpoint" "$EN_SHIP"; then
  pass "en-ship has Learning checkpoint heading"
else
  fail "en-ship missing Learning checkpoint heading"
fi

# --- All four canonical outcome values present in en-ship ---
for outcome in "captured" "intentionally_skipped" "up_to_date" "ci_environment"; do
  if grep -qF "learning_checkpoint: $outcome" "$EN_SHIP"; then
    pass "en-ship documents outcome: $outcome"
  else
    fail "en-ship missing outcome: $outcome"
  fi
done

# --- Bare word "skipped" must NOT appear as the outcome value (must be intentionally_skipped) ---
if grep -qE "learning_checkpoint:[[:space:]]+skipped[[:space:]]*$" "$EN_SHIP" \
   || grep -qE "learning_checkpoint:[[:space:]]+skipped[[:space:]]*\(" "$EN_SHIP"; then
  fail "en-ship uses bare 'skipped' as outcome (must be intentionally_skipped per the canonical enum)"
else
  pass "en-ship doesn't use bare 'skipped' as outcome value"
fi

# --- Checkpoint runs BEFORE lint/typecheck/secret-scan (so en-learn writes go through them) ---
checkpoint_line=$(grep -n "Learning checkpoint" "$EN_SHIP" | head -1 | cut -d: -f1)
lint_line=$(grep -n "Lint + typecheck" "$EN_SHIP" | head -1 | cut -d: -f1)
if [ -n "$checkpoint_line" ] && [ -n "$lint_line" ] && [ "$checkpoint_line" -lt "$lint_line" ]; then
  pass "en-ship checkpoint runs BEFORE lint+typecheck (per spec ordering rationale)"
else
  fail "en-ship checkpoint should run BEFORE lint+typecheck" "checkpoint=$checkpoint_line lint=$lint_line"
fi

# --- --no-learning-checkpoint flag is documented ---
if grep -qF -- "--no-learning-checkpoint" "$EN_SHIP"; then
  pass "en-ship documents --no-learning-checkpoint flag"
else
  fail "en-ship missing --no-learning-checkpoint flag"
fi

# --- en-ship report output includes the learning_checkpoint line ---
if grep -qE "learning_checkpoint:.*captured|✓ learning_checkpoint" "$EN_SHIP"; then
  pass "en-ship report output template includes learning_checkpoint line"
else
  fail "en-ship report output template should include a learning_checkpoint example"
fi

# --- en-qa prompt broadened (not anchored on "N bugs" alone) ---
if grep -qF "QA wrapped" "$EN_QA"; then
  pass "en-qa prompt uses broadened 'QA wrapped' framing"
else
  fail "en-qa prompt should use 'QA wrapped' not 'QA found and fixed N bugs'"
fi

# --- en-qa documents the four capture categories ---
for category in "Bugs found" "Tests stabilized" "Patterns discovered" "Library footguns"; do
  if grep -qF "$category" "$EN_QA"; then
    pass "en-qa documents capture category: $category"
  else
    fail "en-qa missing capture category: $category"
  fi
done

# --- learn-log-format documents the <head-sha> field on capture entries ---
if grep -qF "<head-sha>" "$LOG_FORMAT"; then
  pass "learn-log-format documents the <head-sha> field"
else
  fail "learn-log-format should document the | <head-sha> field on capture entries"
fi

# --- learn-log-format clarifies SHA is capture-only (not refresh/ingest/etc.) ---
if grep -qE "only.*capture.*resets|only explicit .capture. does|capture.*resets the baseline" "$LOG_FORMAT"; then
  pass "learn-log-format clarifies SHA is capture-mode-only"
else
  fail "learn-log-format should clarify only 'capture' mode writes SHA"
fi

# --- en-learn step 3 (Log append) writes the SHA on capture ---
if grep -qE "capture.*head-sha|head-sha.*capture|rev-parse --short HEAD" "$EN_LEARN"; then
  pass "en-learn writes SHA on capture mode"
else
  fail "en-learn step 3 should write | <head-sha> on capture mode"
fi

# --- en-ship baseline detection uses git log <sha>..HEAD precisely, with legacy date fallback ---
if grep -qE "git log <baseline-sha>\.\.HEAD|git log.*<head-sha>\.\.HEAD" "$EN_SHIP"; then
  pass "en-ship baseline uses precise sha..HEAD scan"
else
  fail "en-ship checkpoint should use 'git log <baseline-sha>..HEAD' for precise scan"
fi
if grep -qE "imprecise baseline|legacy.*fallback|fall back to.*git log --since" "$EN_SHIP"; then
  pass "en-ship documents legacy date-based fallback"
else
  fail "en-ship should document the legacy date-based fallback for SHA-less entries"
fi

# --- foundation §D26 updated to mention en-ship as backstop ---
if grep -E "^- \*\*D26\." "$FOUNDATION" | grep -qF "en-ship"; then
  pass "foundation §D26 mentions en-ship backstop"
else
  fail "foundation §D26 should mention en-ship as the checkpoint backstop"
fi
if grep -E "^- \*\*D26\." "$FOUNDATION" | grep -qF "structured checkpoint"; then
  pass "foundation §D26 calls it a 'structured checkpoint' (not soft prompt)"
else
  fail "foundation §D26 should use 'structured checkpoint' language"
fi

# --- foundation §D26 uses canonical enum spelling (intentionally_skipped, NOT bare 'skipped') ---
d26_line=$(grep -E "^- \*\*D26\." "$FOUNDATION")
if echo "$d26_line" | grep -qF "intentionally_skipped"; then
  pass "foundation §D26 uses 'intentionally_skipped' (canonical enum)"
else
  fail "foundation §D26 should use 'intentionally_skipped' not bare 'skipped'"
fi

# --- Idempotency rule documented: re-runs yield up_to_date, not double-prompt ---
if grep -qiE "(up_to_date.*proceed|re-prompt|don't re-prompt|runs twice on the same branch)" "$EN_SHIP"; then
  pass "en-ship documents idempotency (re-runs yield up_to_date)"
else
  fail "en-ship should document idempotency for re-runs"
fi

report
