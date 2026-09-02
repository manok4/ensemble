#!/usr/bin/env bash
# tests/lint/en-build-suite-sequencing.test.sh
#
# From a measured 7h10m build (FR78, 2026-08-26). The full backend suite took
# 2h48m across TWELVE launches: three completed, one failed for a real reason,
# and eight were interrupted before producing a result.
#
# Peer review was not the bottleneck. The review agents took 27m of wall time
# and /en-simplify took 11m. The cost was sequencing: after-phase verification
# ran the full suite at every phase boundary, step 10.1 ran it again before
# simplify and review, and applying review findings required another. A
# four-phase build paid five times before review had said anything — on an
# implementation review was about to change.
#
# Three properties keep that from coming back, and each is a separate way the
# old shape wasted time:
#
#   ONE FULL RUN, LAST. After remediation, not before review.
#   TARGETED AT THE BOUNDARIES. Phase verification proves the phase, not the repo.
#   BATCHED REMEDIATION. Fix-verify-fix-verify pays a suite per partial fix.
#
# And the run is never interrupted. Eight discarded launches is where most of
# the 2h48m went; a suite that looks stalled is a finding about the project, not
# a reason to kill it and guess again.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build suite sequencing"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- 1. the full suite runs after review, not before ---
gate=$(grep -n 'Cheap gate: lint + typecheck only' "$SKILL" | head -1 | cut -d: -f1)
rev=$(grep -n 'Branch-level Outside Voice review' "$SKILL" | head -1 | cut -d: -f1)
full=$(grep -n '\*\*The full suite, once\.\*\*' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$gate" ] && [ -n "$rev" ] && [ -n "$full" ] \
   && [ "$gate" -lt "$rev" ] && [ "$rev" -lt "$full" ]; then
  pass "the full suite runs after review (gate=$gate review=$rev suite=$full)"
else
  fail "the full suite must run after review remediation" \
       "gate=$gate review=$rev suite=$full — running it first pays for it three times"
fi

# --- 2. step 10.1 is cheap, and says so ---
if grep -qiE 'The full suite does not run here' "$SKILL"; then
  pass "the pre-review gate is explicitly not the full suite"
else
  fail "the pre-review gate must state that the full suite does not run there"
fi

# --- 3. phase boundaries are targeted ---
if grep -qiE 'the tests covering the files this phase touched.*not the full suite' "$SKILL"; then
  pass "after-phase verification is targeted, not the full suite"
else
  fail "after-phase verification must be targeted" \
       "a four-phase build otherwise pays for the full suite four times before review"
fi

# --- 4. remediation is batched ---
if grep -qiE 'Apply every finding in one batch, then verify once' "$SKILL"; then
  pass "review findings are applied in one batch"
else
  fail "review findings must be applied in one batch" \
       "fix-verify-fix-verify pays a full suite per partial fix"
fi

# --- 5. a running suite is never killed ---
if grep -qiE 'Do not interrupt a running suite' "$SKILL" \
   && grep -qiE 'reported, not killed and retried' "$SKILL"; then
  pass "a slow suite is reported rather than interrupted"
else
  fail "a running suite must never be killed and retried" \
       "eight of twelve FR78 launches were discarded that way"
fi

# --- 6. the trade is recorded, with its cost ---
# A latency change that drops a check without naming what it gives up is one
# nobody can re-litigate on the evidence.
if grep -qE '^- \*\*D53\.' "$FOUNDATION" && grep -qiE 'What this costs' "$FOUNDATION"; then
  pass "D53 records the sequencing change and what it gives up"
else
  fail "foundation must record D53 with its cost"
fi

# --- 7. the layer that paid for the suite records that it did (EN15 U2) ------
# Four layers verified the same tree on a measured PR and none could see the
# others. en-build is the one that pays for the full suite, so it is the one
# that writes the receipt the others read.
EN_BUILD_SKILL="$REPO_ROOT/skills/en-build/SKILL.md"

if grep -qF 'ensemble-verification-receipt" write' "$EN_BUILD_SKILL"; then
  pass "en-build writes a verification receipt"
else
  fail "en-build writes a verification receipt"
fi

# Ordering: the write must come after the suite, not before it. A receipt
# written first would vouch for a run that had not happened.
suite_line=$(grep -n 'The full suite, once' "$EN_BUILD_SKILL" | head -1 | cut -d: -f1)
write_line=$(grep -n 'On success, write a verification receipt' "$EN_BUILD_SKILL" | head -1 | cut -d: -f1)
commit_line=$(grep -n 'Commit the simplify + review changes' "$EN_BUILD_SKILL" | head -1 | cut -d: -f1)
if [ -n "$suite_line" ] && [ -n "$write_line" ] && [ -n "$commit_line" ] \
   && [ "$suite_line" -lt "$write_line" ] && [ "$write_line" -lt "$commit_line" ]; then
  pass "the receipt is written after the suite and before the commit trailers"
else
  fail "the receipt is written after the suite and before the commit trailers" \
       "suite=$suite_line write=$write_line commit=$commit_line"
fi

# Two properties that keep the receipt an optimisation rather than a new way to
# fail a build, and keep "a receipt exists" equivalent to "something passed".
if grep -qF 'Only on a passing suite, and never fatal' "$EN_BUILD_SKILL"; then
  pass "the receipt is written only on a pass, and a failed write is not fatal"
else
  fail "the receipt is written only on a pass, and a failed write is not fatal"
fi

report
