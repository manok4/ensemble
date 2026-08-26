#!/usr/bin/env bash
# Drift guards for /en-plan default-branch auto-branch checkpoint.
# Per the spec at docs/en-plan-default-branch-spec.md (merged via PR #19).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan default-branch checkpoint"

EN_PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
CHECKPOINT_REF="$REPO_ROOT/skills/en-plan/references/plan-default-branch-checkpoint.md"

# The checkpoint contract spans the SKILL trigger table and its gated reference (D48).
# Content assertions search both; step-ordering assertions stay on SKILL.md.
CONTRACT="$(mktemp)"
trap 'rm -f "$CONTRACT"' EXIT
cat "$EN_PLAN" "$CHECKPOINT_REF" > "$CONTRACT" 2>/dev/null || cp "$EN_PLAN" "$CONTRACT"

if [ -f "$CHECKPOINT_REF" ]; then
  pass "gated checkpoint reference exists"
else
  fail "skills/en-plan/references/plan-default-branch-checkpoint.md must exist (checkpoint body lives there)"
fi
CONFIG_EXAMPLE="$REPO_ROOT/shared/references/templates/config-local-example.yaml"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- Default-branch checkpoint heading exists ---
if grep -qF "Default-branch checkpoint" "$EN_PLAN"; then
  pass "en-plan has Default-branch checkpoint section"
else
  fail "en-plan missing Default-branch checkpoint section"
fi

# --- Checkpoint runs BEFORE the plan-file write step (so resume can checkout cleanly) ---
checkpoint_line=$(grep -n "Default-branch checkpoint" "$EN_PLAN" | head -1 | cut -d: -f1)
write_step_line=$(grep -nE "^[0-9]+\. \*\*Write to" "$EN_PLAN" | head -1 | cut -d: -f1)
if [ -n "$checkpoint_line" ] && [ -n "$write_step_line" ] && [ "$checkpoint_line" -lt "$write_step_line" ]; then
  pass "checkpoint runs BEFORE plan-file write (per resume safety)"
else
  fail "checkpoint must run BEFORE 'Write to docs/plans/...' step" "checkpoint=$checkpoint_line write=$write_step_line"
fi

# --- All four response options documented ---
for option in "(recommended) — create the branch + commit" "no-commit              — leave the plan uncommitted" "current                — commit on" "details                — show diagnostic info"; do
  if grep -qF "$option" "$CONTRACT"; then
    pass "checkpoint documents response option: $(echo "$option" | head -c 50)..."
  else
    fail "checkpoint missing response option: $(echo "$option" | head -c 50)..."
  fi
done

# --- Three canonical terminal outcome values present (details is non-terminal) ---
for outcome in "auto_branched" "no_commit_requested" "committed_to_default_branch"; do
  if grep -qF "default_branch_checkpoint: $outcome" "$CONTRACT"; then
    pass "checkpoint documents terminal outcome: $outcome"
  else
    fail "checkpoint missing terminal outcome: $outcome"
  fi
done

# --- Bare words MUST NOT appear as outcome values (canonical enum protection) ---
for bare in "branched$" "kept_on_main" "skipped$"; do
  if grep -qE "default_branch_checkpoint:[[:space:]]+$bare" "$CONTRACT"; then
    fail "checkpoint uses non-canonical outcome value: $bare"
  else
    pass "checkpoint doesn't use non-canonical outcome: $bare"
  fi
done

# --- Three-source detection documented ---
for source in "gh repo view --json defaultBranchRef" "git symbolic-ref refs/remotes/origin/HEAD" '`main`, `master`, `develop`, `trunk`'; do
  if grep -qF "$source" "$CONTRACT"; then
    pass "detection source documented: $(echo "$source" | head -c 50)..."
  else
    fail "detection source missing: $(echo "$source" | head -c 50)..."
  fi
done

# --- Hardcoded fallback list is exactly main|master|develop|trunk ---
if grep -qE "main.*master.*develop.*trunk" "$CONTRACT"; then
  pass "hardcoded fallback list matches spec (main, master, develop, trunk)"
else
  fail "hardcoded fallback list should be exactly: main, master, develop, trunk"
fi

# --- Branch name convention is <plan_id>-<slug> ---
if grep -qF "<plan_id>-<slug>" "$CONTRACT"; then
  pass "branch name convention is <plan_id>-<slug> (matches /en-build)"
else
  fail "branch name should be <plan_id>-<slug> to match /en-build convention"
fi

# --- --branch-on-default flag documented ---
if grep -qF -- "--branch-on-default" "$CONTRACT"; then
  pass "--branch-on-default flag documented"
else
  fail "--branch-on-default flag missing"
fi
if grep -qE -- "--branch-on-default <y\|current\|no-commit>" "$CONTRACT"; then
  pass "--branch-on-default values documented (y|current|no-commit)"
else
  fail "--branch-on-default should accept y|current|no-commit"
fi

# --- Existing-branch handler documented (resume path) ---
if grep -qF "Existing branch" "$CONTRACT" && grep -qF "resuming" "$CONTRACT"; then
  pass "existing-branch resume handler documented"
else
  fail "existing-branch handler (resume on plan-only commits) should be documented"
fi
if grep -qiE "build commits|non-plan commits|refuse the auto-resume" "$CONTRACT"; then
  pass "existing-branch refuse-and-ask handler documented"
else
  fail "existing-branch refuse-and-ask path (branch has build commits) should be documented"
fi

# --- "current" opt-out is framed as explicit opt-in to commit on default branch, not hidden ---
if grep -qE "opt-out|opt out" "$CONTRACT"; then
  pass "current opt-out is documented as discoverable in the prompt"
else
  fail "current option should be framed as explicit opt-out"
fi

# --- Future extension (protected_branches) documented in config example ---
if grep -qF "protected_branches" "$CONFIG_EXAMPLE"; then
  pass "config-local-example documents protected_branches future extension"
else
  fail "config-local-example.yaml should document protected_branches as future extension"
fi
if grep -qF "not yet implemented" "$CONFIG_EXAMPLE"; then
  pass "protected_branches clearly marked as not yet implemented"
else
  fail "protected_branches should be marked as 'not yet implemented' in v1"
fi

# --- Foundation §D32 added ---
if grep -E "^- \*\*D32\." "$FOUNDATION" >/dev/null; then
  pass "foundation §D32 exists (auto-branch decision entry)"
else
  fail "foundation should have a D32 entry for the auto-branch behavior"
fi
d32_line=$(grep -E "^- \*\*D32\." "$FOUNDATION")
if echo "$d32_line" | grep -qF "default branch"; then
  pass "foundation §D32 references default branch"
else
  fail "foundation §D32 should mention default-branch auto-branching"
fi
if echo "$d32_line" | grep -qF "auto_branched"; then
  pass "foundation §D32 uses canonical outcome enum spelling"
else
  fail "foundation §D32 should include canonical outcome 'auto_branched'"
fi

report
