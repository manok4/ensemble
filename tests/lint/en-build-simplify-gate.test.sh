#!/usr/bin/env bash
# Drift guards for the EN07 post-build simplify+review gate in /en-build.
# The simplify pass is now AUDITABLE evidence (a simplify-verdict: trailer +
# --require-simplify), not a prose-only requirement: a skipped /en-simplify or
# an unrecorded branch review must fail the end-of-build audit and block the
# learning checkpoint / success path.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build simplify gate"

EN_BUILD="$REPO_ROOT/skills/en-build/SKILL.md"

# --- step 10.4: emits the simplify-verdict trailer with the outcome enum ---
if grep -qF "simplify-verdict:" "$EN_BUILD" \
   && grep -qiE "completed .+ not_applicable .+ failed|completed\`? \(|outcome.*completed" "$EN_BUILD"; then
  pass "step 10.4 documents the simplify-verdict trailer + outcome enum"
else
  fail "step 10.4 must document emitting a simplify-verdict trailer (outcome completed|not_applicable|failed)"
fi

# --- reason REQUIRED for not_applicable / failed, with the concrete reasons ---
reason_ok=1
grep -qiE "reason.*REQUIRED|REQUIRED.*reason" "$EN_BUILD" || reason_ok=0
grep -qF "docs-only" "$EN_BUILD" || reason_ok=0
grep -qF "all-destructive-gated" "$EN_BUILD" || reason_ok=0
if [ "$reason_ok" -eq 1 ]; then
  pass "not_applicable / failed require a recorded reason (docs-only, --no-simplify, etc.)"
else
  fail "must require a recorded reason for not_applicable / failed outcomes"
fi

# --- --no-simplify records a VISIBLE not_applicable, never silence ---
if grep -qE '"outcome":"not_applicable","reason":"--no-simplify"' "$EN_BUILD" \
   && grep -qiE "never silence|recorded opt-out|visible.*opt-out" "$EN_BUILD"; then
  pass "--no-simplify records an explicit not_applicable (--no-simplify), never silence"
else
  fail "--no-simplify must record an explicit, visible not_applicable outcome (never a silent skip)"
fi

# --- a MISSING simplify-verdict is not a legitimate skip → audit treats as missing/fails ---
if grep -qiE "missing.*simplify-verdict|simplify-verdict.*trailer is NOT|treats it as .missing.|not a legitimate skip" "$EN_BUILD"; then
  pass "a missing simplify-verdict trailer fails the audit (not a legitimate skip)"
else
  fail "must state a missing simplify-verdict is treated as missing and fails the audit"
fi

# --- step 10.5: audit invokes --require-simplify ---
if grep -qF -- "--require-simplify" "$EN_BUILD"; then
  pass "step 10.5 audit invokes --require-simplify"
else
  fail "step 10.5 must invoke ensemble-verify-peer-evidence with --require-simplify"
fi

# --- step 10.5 surfaces BOTH derived outcome fields ---
if grep -qF "simplify_pass" "$EN_BUILD" && grep -qF "branch_review_pass" "$EN_BUILD"; then
  pass "audit surfaces simplify_pass + branch_review_pass"
else
  fail "must surface simplify_pass and branch_review_pass in the audit output"
fi

# --- the two outcome lines are mandatory in the build summary ---
if grep -qiE "mandatory.*(simplify_pass|two gate lines|two.*lines)|(simplify_pass|two gate lines).*mandatory" "$EN_BUILD"; then
  pass "simplify_pass / branch_review_pass are mandatory summary lines"
else
  fail "the two outcome lines must be mandatory in every build summary"
fi

# --- a missing/failed gate BLOCKS the success path ---
if grep -qiE "success path.*block|block.*success path|blocked.*until the audit passes" "$EN_BUILD" \
   && grep -qiE "missing.*failed|failed.*missing" "$EN_BUILD"; then
  pass "a missing/failed simplify or review blocks the /en-review→/en-qa→/en-ship success path"
else
  fail "a missing/failed simplify_pass/branch_review_pass must block the success path"
fi

# --- learning-checkpoint deferral guard extended to simplify/review gate ---
if grep -qiE "Deferral guard" "$EN_BUILD" \
   && grep -qiE "simplify_pass.*(missing|failed)|(missing|failed).*simplify" "$EN_BUILD" \
   && grep -qiE "branch_review_pass" "$EN_BUILD"; then
  pass "deferral guard defers the learning checkpoint on missing/failed simplify or review"
else
  fail "the learning-checkpoint deferral guard must also defer on missing/failed simplify/review"
fi

# --- fallback review mapping: single-agent path only a fallback, records why ---
if grep -qiE "fallback_completed" "$EN_BUILD" \
   && grep -qiE "ONLY a fallback|only.*fallback.*/en-review|reviewer.*IS the recorded reason|records which fallback" "$EN_BUILD"; then
  pass "fallback review maps to fallback_completed and must record which fallback"
else
  fail "must document the fallback-review mapping (single-agent path is a recorded fallback for /en-review)"
fi

report
