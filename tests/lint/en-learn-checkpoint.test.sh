#!/usr/bin/env bash
# Drift guards for the structured learning checkpoint (en-learn-checkpoint-spec).
# Per docs/en-learn-checkpoint-spec.md. Relocated from en-ship preflight to
# en-build completion by EN04 - checkpoint assertions target en-build.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn checkpoint"

EN_BUILD="$REPO_ROOT/skills/en-build/SKILL.md"
EN_QA="$REPO_ROOT/skills/en-qa/SKILL.md"
EN_LEARN="$REPO_ROOT/skills/en-learn/SKILL.md"
LOG_FORMAT="$REPO_ROOT/shared/references/learn-log-format.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- en-build completion has a learning checkpoint ---
if grep -qF "Learning checkpoint" "$EN_BUILD"; then
  pass "en-build has Learning checkpoint heading"
else
  fail "en-build missing Learning checkpoint heading"
fi

# --- All four canonical outcome values present in en-build ---
for outcome in "captured" "intentionally_skipped" "up_to_date" "ci_environment"; do
  if grep -qF "learning_checkpoint: $outcome" "$EN_BUILD"; then
    pass "en-build documents outcome: $outcome"
  else
    fail "en-build missing outcome: $outcome"
  fi
done

# --- Bare word "skipped" must NOT appear as the outcome value (must be intentionally_skipped) ---
if grep -qE "learning_checkpoint:[[:space:]]+skipped[[:space:]]*$" "$EN_BUILD" \
   || grep -qE "learning_checkpoint:[[:space:]]+skipped[[:space:]]*\(" "$EN_BUILD"; then
  fail "en-build uses bare 'skipped' as outcome (must be intentionally_skipped per the canonical enum)"
else
  pass "en-build doesn't use bare 'skipped' as outcome value"
fi

# --- Checkpoint fires at build completion (at the /en-learn hand-off, after the audit) ---
if grep -qiE "hand-off|completion|after step 10" "$EN_BUILD"; then
  pass "en-build checkpoint fires at build completion (en-learn hand-off)"
else
  fail "en-build checkpoint should fire at build completion"
fi

# --- --no-learning-checkpoint flag is documented in en-build ---
if grep -qF -- "--no-learning-checkpoint" "$EN_BUILD"; then
  pass "en-build documents --no-learning-checkpoint flag"
else
  fail "en-build missing --no-learning-checkpoint flag"
fi

# --- en-build summary includes the learning_checkpoint line ---
if grep -qE "learning_checkpoint:" "$EN_BUILD"; then
  pass "en-build summary includes learning_checkpoint outcome"
else
  fail "en-build should include a learning_checkpoint outcome line"
fi

# --- consolidation: en-qa does NOT prompt for learnings (capture is en-build-only) ---
if grep -qiE "does (\*\*)?not(\*\*)? prompt for learnings" "$EN_QA"; then
  pass "en-qa does not prompt for learnings (capture is en-build-only)"
else
  fail "en-qa must not prompt for learnings (consolidated to en-build completion)"
fi

# --- consolidation: en-ship does NOT prompt for learnings ---
EN_SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
if grep -qiE "never handles it|not decided here|no longer prompts for learnings" "$EN_SHIP"; then
  pass "en-ship does not prompt for learnings"
else
  fail "en-ship must not prompt for learnings (consolidated to en-build completion)"
fi

# --- en-build checkpoint is the SOLE capture point, after the branch-level review ---
if grep -qiE "SOLE learning-capture point" "$EN_BUILD" && grep -qiE "after the branch-level" "$EN_BUILD"; then
  pass "en-build checkpoint is the sole capture point, after the branch-level review"
else
  fail "en-build checkpoint must be the sole capture point, fired after the branch-level review"
fi

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

# --- en-build baseline detection uses git log <sha>..HEAD precisely, with legacy date fallback ---
if grep -qE "git log <sha>\.\.HEAD|git log <baseline-sha>\.\.HEAD|<head-sha>.*for scope|<head-sha>.*entry" "$EN_BUILD"; then
  pass "en-build baseline uses precise sha..HEAD scan"
else
  fail "en-build checkpoint should use 'git log <sha>..HEAD' for precise scan"
fi
if grep -qE "imprecise-baseline|legacy.*fallback|since=<date>" "$EN_BUILD"; then
  pass "en-build documents legacy date-based fallback"
else
  fail "en-build should document the legacy date-based fallback for SHA-less entries"
fi

# --- foundation §D26 updated to reference en-build completion ---
if grep -E "^- \*\*D26\." "$FOUNDATION" | grep -qF "en-build"; then
  pass "foundation §D26 references en-build completion checkpoint"
else
  fail "foundation §D26 should reference the en-build completion checkpoint"
fi
if grep -E "^- \*\*D26\." "$FOUNDATION" | grep -qiE "structured (step|checkpoint).*not.*soft prompt|structured and non-droppable"; then
  pass "foundation §D26 describes a structured (non-soft-prompt) checkpoint"
else
  fail "foundation §D26 should describe a structured (not soft-prompt) checkpoint"
fi

# --- foundation §D26 uses canonical enum spelling (intentionally_skipped, NOT bare 'skipped') ---
d26_line=$(grep -E "^- \*\*D26\." "$FOUNDATION")
if echo "$d26_line" | grep -qF "intentionally_skipped"; then
  pass "foundation §D26 uses 'intentionally_skipped' (canonical enum)"
else
  fail "foundation §D26 should use 'intentionally_skipped' not bare 'skipped'"
fi

# --- Idempotency rule documented: re-runs yield up_to_date, not double-prompt ---
if grep -qiE "(up_to_date.*skip|zero commits|skip the prompt silently)" "$EN_BUILD"; then
  pass "en-build documents idempotency (zero commits yield up_to_date)"
else
  fail "en-build should document idempotency for re-runs"
fi

report
