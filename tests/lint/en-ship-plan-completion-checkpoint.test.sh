#!/usr/bin/env bash
# Drift guards for the /en-ship plan-completion checkpoint + /en-learn step 11
# unbundle. Per docs/en-ship-plan-completion-checkpoint-spec.md (merged via PR #22).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-ship plan-completion checkpoint"

EN_SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
EN_LEARN="$REPO_ROOT/skills/en-learn/SKILL.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# === en-ship plan-completion checkpoint ===

# 1. Heading present
if grep -qF "Plan completion checkpoint" "$EN_SHIP"; then
  pass "en-ship has Plan completion checkpoint section"
else
  fail "en-ship missing Plan completion checkpoint section"
fi

# 2. Placement: AFTER lint+typecheck+secret-scan+scope-confirm, BEFORE commit-message
#    Specifically: between step 6 (Confirm scope) and step 8 (Generate commit message)
checkpoint_line=$(grep -n "Plan completion checkpoint" "$EN_SHIP" | head -1 | cut -d: -f1)
scope_line=$(grep -nE "^[0-9]+\. \*\*Confirm scope" "$EN_SHIP" | head -1 | cut -d: -f1)
commit_msg_line=$(grep -nE "^[0-9]+\. \*\*Generate conventional-commit" "$EN_SHIP" | head -1 | cut -d: -f1)
secret_line=$(grep -nE "^[0-9]+\. \*\*Secret scan" "$EN_SHIP" | head -1 | cut -d: -f1)
if [ -n "$checkpoint_line" ] && [ -n "$scope_line" ] && [ -n "$commit_msg_line" ] && [ -n "$secret_line" ]; then
  if [ "$checkpoint_line" -gt "$scope_line" ] && [ "$checkpoint_line" -lt "$commit_msg_line" ] && [ "$checkpoint_line" -gt "$secret_line" ]; then
    pass "checkpoint runs AFTER preflight checks AND BEFORE commit-message generation (PR #22 P2 fix)"
  else
    fail "checkpoint must be between scope-confirm and commit-message gen" "scope=$scope_line secret=$secret_line checkpoint=$checkpoint_line commit_msg=$commit_msg_line"
  fi
else
  fail "couldn't locate one of the ordering anchors" "scope=$scope_line secret=$secret_line checkpoint=$checkpoint_line commit_msg=$commit_msg_line"
fi

# 3. All five terminal outcome values documented
for outcome in "completed_and_moved" "skipped_by_user" "up_to_date" "not_applicable" "incomplete_build"; do
  if grep -qF "plan_completion_checkpoint: $outcome" "$EN_SHIP"; then
    pass "checkpoint documents outcome: $outcome"
  else
    fail "checkpoint missing outcome: $outcome"
  fi
done

# 4. details is non-terminal (re-prompts; doesn't produce a report value)
if grep -qE "details.*(re-prompt|Re-prompt|loop until terminal)" "$EN_SHIP"; then
  pass "details is documented as non-terminal (re-prompts, no report value)"
else
  fail "details option should be non-terminal (re-prompt + loop)"
fi

# 5. Bare 'completed', 'done', 'skipped', 'flipped' MUST NOT appear as report values
for bare in "completed$" "done$" "flipped$"; do
  if grep -qE "plan_completion_checkpoint:[[:space:]]+$bare" "$EN_SHIP"; then
    fail "checkpoint uses non-canonical bare outcome: $bare"
  else
    pass "checkpoint doesn't use non-canonical bare outcome: $bare"
  fi
done

# 6. Status 'open' is handled (PR #22 P2 fix #3 — open recovery path)
if grep -qE "in_progress.* OR .*open|open.* OR .*in_progress" "$EN_SHIP"; then
  pass "status open is handled same as in_progress (recovery path preserved)"
else
  fail "status open should flow through the same path as in_progress"
fi

# 7. Audit scoped to unit commits only (PR #22 P2 fix #2)
if grep -qF "unit commit" "$EN_SHIP" && grep -qiE "U<N>.*subject|subject.*U<N>" "$EN_SHIP"; then
  pass "audit scope discriminator (U<N> in subject) documented"
else
  fail "audit scope should document the unit-commit discriminator (U<N> in subject)"
fi
if grep -qF "docs(plan)" "$EN_SHIP" && grep -qiE "excluded|not a unit commit" "$EN_SHIP"; then
  pass "plan-init commit explicitly excluded from audit scope"
else
  fail "plan-init 'docs(plan): <plan_id>' commit should be explicitly excluded"
fi

# 8. Atomic mutation with ship commit (PR #22 P2 fix #1)
if grep -qiE "atomic.* commit|same commit|atomically with the (commit|ship)" "$EN_SHIP"; then
  pass "lifecycle mutation documented as atomic with the ship commit"
else
  fail "mutation should be atomic with the ship commit (no separate commit)"
fi

# 9. Uses ensemble-verify-peer-evidence
if grep -qF '$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence' "$EN_SHIP"; then
  pass "checkpoint uses ensemble-verify-peer-evidence for completeness check"
else
  fail "checkpoint should reference \$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence"
fi

# 10. Idempotency (re-runs yield up_to_date)
if grep -qE "Idempotency|silently passes|completed.*up_to_date" "$EN_SHIP"; then
  pass "idempotency documented (re-runs yield up_to_date)"
else
  fail "idempotency should be documented"
fi

# 11. --no-plan-completion-checkpoint flag
if grep -qF -- "--no-plan-completion-checkpoint" "$EN_SHIP"; then
  pass "--no-plan-completion-checkpoint flag documented"
else
  fail "--no-plan-completion-checkpoint flag missing"
fi

# 12. Output template includes plan_completion_checkpoint line
if grep -qE "plan_completion_checkpoint:.*completed_and_moved|✓ plan_completion_checkpoint" "$EN_SHIP"; then
  pass "output template includes plan_completion_checkpoint example"
else
  fail "output template should include a plan_completion_checkpoint example"
fi

# === en-learn step 11 unbundle (11a / 11b) ===

# 13. Step 11 documents the 11a/11b split
if grep -qE "11a\.|\*\*11a\." "$EN_LEARN"; then
  pass "en-learn step 11a documented (always-runs lifecycle flip)"
else
  fail "en-learn should split step 11 into 11a and 11b (PR #22 unbundle)"
fi
if grep -qE "11b\.|\*\*11b\." "$EN_LEARN"; then
  pass "en-learn step 11b documented (capture-conditional documentation-tense)"
else
  fail "en-learn should have step 11b for documentation-tense updates"
fi

# 14. 11a is documented as always-running, even on skip-capture
if grep -qiE "always run|regardless of whether|11a always" "$EN_LEARN"; then
  pass "step 11a documented as always-runs (skip-capture still flips status)"
else
  fail "step 11a should explicitly state it runs regardless of capture decision"
fi

# 15. 11b is documented as capture-conditional
if grep -qiE "only.*runs.*when.*learning.*captured|11b is skipped when" "$EN_LEARN"; then
  pass "step 11b documented as capture-conditional"
else
  fail "step 11b should be documented as only-runs-on-actual-capture"
fi

# 16. Open-status recovery preserved (open AND in_progress flow into the flip)
if grep -qE "in_progress.*OR.*open|status: in_progress.*status: open|status: open.*status: in_progress" "$EN_LEARN"; then
  pass "en-learn 11a preserves open-status recovery path"
else
  fail "en-learn 11a should handle both in_progress and open"
fi

# 17. Edge case: no plan_id in context → silent no-op
if grep -qiE "no plan_id in context|outside.*plan context|silent no-op" "$EN_LEARN"; then
  pass "en-learn 11 documents 'no plan context' edge case"
else
  fail "en-learn 11 should document the 'no plan_id in context' silent no-op"
fi

# 18. Documentation-tense / deviation-notes language preserved in 11b
if grep -qiE "documentation-tense|deviation" "$EN_LEARN"; then
  pass "documentation-tense / deviation-notes language preserved in 11b"
else
  fail "11b should retain documentation-tense and deviation-notes behavior"
fi

# === Foundation §D34 ===

# 19. Foundation §D34 added
if grep -E "^- \*\*D34\." "$FOUNDATION" >/dev/null; then
  pass "foundation §D34 exists (plan-completion source-of-truth decision)"
else
  fail "foundation should have D34 entry for the source-of-truth + backstop semantics"
fi
d34_line=$(grep -E "^- \*\*D34\." "$FOUNDATION")
if echo "$d34_line" | grep -qF "11a"; then
  pass "foundation §D34 references step 11a"
else
  fail "foundation §D34 should reference step 11a as primary source of truth"
fi
if echo "$d34_line" | grep -qF "backstop"; then
  pass "foundation §D34 mentions en-ship backstop"
else
  fail "foundation §D34 should mention en-ship as backstop"
fi
if echo "$d34_line" | grep -qF "completed_and_moved"; then
  pass "foundation §D34 uses canonical outcome enum"
else
  fail "foundation §D34 should include canonical outcomes"
fi

report
