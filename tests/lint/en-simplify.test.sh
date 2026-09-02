#!/usr/bin/env bash
# Drift guards for the /en-simplify skill (FR01 U1).
# Per docs/plans/active/FR01-improvement_skill-suite-optimization.md.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-simplify skill"

EN_SIMPLIFY="$REPO_ROOT/skills/en-simplify/SKILL.md"

# --- skill exists ---
if [ -f "$EN_SIMPLIFY" ]; then
  pass "en-simplify SKILL.md exists"
else
  fail "en-simplify SKILL.md missing"
fi

# --- helper-resolution header ---
# The $ENSEMBLE_ROOT helper-resolution header was retired by EN13, when skills
# became self-contained and stopped resolving paths through an install root. This
# assertion outlived the convention; it was invisible because the suite had no
# report call and so could never fail.

# --- recursion guard ---
if grep -qF "ENSEMBLE_PEER_REVIEW=true" "$EN_SIMPLIFY"; then
  pass "en-simplify has recursion guard"
else
  fail "en-simplify missing recursion guard"
fi

# --- three review dimensions ---
for dim in "Reuse" "Quality" "Efficiency"; do
  if grep -qE "Dimension [0-9] — $dim" "$EN_SIMPLIFY"; then
    pass "en-simplify declares dimension: $dim"
  else
    fail "en-simplify missing dimension: $dim"
  fi
done

# --- behavior-preserving contract ---
if grep -qiE "behavior-preserving|preserves behavior|preserve.*behavior" "$EN_SIMPLIFY"; then
  pass "en-simplify states behavior-preserving contract"
else
  fail "en-simplify missing behavior-preserving contract"
fi

# --- never removes safety checks ---
if grep -qiE "never simplif.*safety|safety check" "$EN_SIMPLIFY"; then
  pass "en-simplify forbids removing safety checks"
else
  fail "en-simplify should forbid removing safety checks"
fi

# --- default scope = branch diff vs base ---
if grep -qiE "current branch and its base|branch diff vs base|diff between the current branch" "$EN_SIMPLIFY"; then
  pass "en-simplify default scope = branch diff vs base"
else
  fail "en-simplify should default scope to branch diff vs base"
fi

# --- does not commit ---
if grep -qiE "[Dd]oes not commit|[Nn]ever commits" "$EN_SIMPLIFY"; then
  pass "en-simplify documents no-commit policy"
else
  fail "en-simplify should document no-commit policy"
fi

# --- reuses the code-simplifier agent ---
if grep -qF "agents/code-simplifier.md" "$EN_SIMPLIFY"; then
  pass "en-simplify reuses the code-simplifier agent"
else
  fail "en-simplify should reuse the code-simplifier agent"
fi

# --- what the pass carries, and what it stopped carrying (2026-09-02) --------
S="$REPO_ROOT/skills/en-simplify/SKILL.md"
D="$REPO_ROOT/skills/en-simplify/references/code-simplifier-dispatch.md"

hasf() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$1")"; }

# 390 lines of peer-detection machinery for one row of a translation table, in a
# skill that invokes no peer. Its return would be the same mistake, not a fix.
for gone in references/host-detect.md scripts/ensemble-detect-host references/recursion-guard.md; do
  [ -e "$REPO_ROOT/skills/en-simplify/$gone" ] \
    && fail "en-simplify does not carry $gone" \
    || pass "en-simplify does not carry $gone"
done
hasf "$S" "it invokes no peer" "the skill says why it carries no peer machinery"

# --- read-only reviewers: the race this prevents is silent -------------------
hasf "$S" "read-only in this skill"        "the reviewers are declared read-only"
hasf "$S" "concurrently on one working tree" "the reason names the concurrent tree"
hasf "$D" "State the read-only constraint in each dispatch prompt" \
                                            "the constraint goes in the prompt, not just the doc"
hasf "$D" "losing edits vanish"             "the dispatch doc names the failure mode"

# --- the orchestrated seam ---------------------------------------------------
hasf "$S" "When a caller passed an explicit scope, never ask" \
                                            "a caller-supplied scope never triggers a question"
hasf "$S" "result to return"                "an empty caller scope is returned, not asked about"

# --- adopted mechanisms ------------------------------------------------------
hasf "$S" "kind gate, never a size gate"    "the preflight is a kind gate"
hasf "$S" "Do not dispatch"                 "the preflight stops before dispatching"
hasf "$S" "backpressure, not failure"       "a concurrency limit is backpressure"
hasf "$S" "inline in the parent"            "an undispatchable reviewer runs inline"
hasf "$S" "all three dimensions have an outcome" "a partial roster is not reported as a pass"
hasf "$S" "Inspect widely, edit narrowly"   "the inspect boundary is wider than the edit boundary"
hasf "$S" "mutation boundary"               "the edit boundary is named"
hasf "$S" "is not behavior"                 "an unshipped-only interface is not protected"

# --- the dispatch doc must match the model en-build actually runs ------------
# It described a per-unit pass that D52 abolished, with the real one appended as a
# footnote. This is the third D52 desync found in this campaign, so it is asserted
# from both sides rather than trusted.
if grep -qE 'per unit|per-unit dispatch|verify gate 2|Verification gate 2' "$D"; then
  fail "the dispatch doc describes the branch-level pass, not the retired per-unit one"
else
  pass "the dispatch doc describes the branch-level pass, not the retired per-unit one"
fi
grep -qF "branch level, not per-unit" "$REPO_ROOT/skills/en-build/SKILL.md" \
  && pass "en-build still describes the pass as branch-level" \
  || fail "en-build still describes the pass as branch-level" \
         "if this changed, the dispatch doc above is describing the wrong model again"

report
