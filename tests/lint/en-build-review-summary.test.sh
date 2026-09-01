#!/usr/bin/env bash
# tests/lint/en-build-review-summary.test.sh
#
# D52 moved review from per-unit to once at 10.3, which made the build summary
# the only place a reader learns what the review found. It was reporting
# "4 findings applied, 2 deferred" — the addressed half alone.
#
# Found-and-addressed are different facts and only readable together. A review
# that found eleven and addressed six is a different outcome from one that found
# six and addressed six, and a line carrying only the second cannot distinguish
# them. Severity is what makes "addressed" mean anything: six of eleven is
# reassuring if the unaddressed five are P2s and alarming if one is a P0.
#
# The example block is also load-bearing. Its previous version still showed
# per-unit peer results and "code-simplifier: 4 of 5 units" — the pre-D35 model,
# in the one place a reader looks to learn what output to expect.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build review summary"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"

# --- 1. both halves, both broken down by severity ---
if grep -qiE 'Found.*P0:.*P1:.*P2:' "$SKILL" && grep -qiE 'Addressed [0-9]+ \(' "$SKILL"; then
  pass "the summary reports findings and resolutions, both by severity"
else
  fail "the review line must report found AND addressed, by severity" \
       "addressed-only cannot distinguish 6-of-11 from 6-of-6"
fi

# --- 2. it is required, not merely illustrated ---
if grep -qiE 'The .Review:. line is mandatory' "$SKILL"; then
  pass "the review line is mandatory, not just shown in an example"
else
  fail "the review line must be mandatory" "an example alone is a suggestion"
fi

# --- 3. deferred findings stay followable, disagreed ones stay visible ---
if grep -qiE 'deferred .{0,20}name their TD IDs' "$SKILL" \
   && grep -qiE 'disagreed ones are counted' "$SKILL"; then
  pass "deferred findings name TD IDs and disagreed ones are counted"
else
  fail "deferred must name TD IDs and disagreed must be counted" \
       "an uncounted disagreement is a silent drop"
fi

# --- 4. the example shows the post-D52 model, not the one it replaced ---
stale=""
grep -qiE 'peer applied [0-9]' "$SKILL" && stale="$stale per-unit-peer-result"
grep -qiE 'Code-simplifier: [0-9]+ of [0-9]+ units' "$SKILL" && stale="$stale per-unit-simplifier"
[ -z "$stale" ] \
  && pass "the summary example shows branch-level review and simplify" \
  || fail "the summary example still shows the per-unit model" "$stale"

# --- 5. the review-mode passthrough defaults to cross ---
# A build may ask for the cheaper peer-only pass; it must not get it by default,
# because D46's reasoning is about what a build's review is FOR.
if grep -qE '\| `--review peer\\\|cross` \|' "$SKILL" \
   && grep -qiE 'Default `cross`' "$SKILL" \
   && grep -qiE 'peer is mandatory either way' "$SKILL"; then
  pass "--review lets a build pick the cheaper pass, defaulting to cross"
else
  fail "--review must exist and default to cross" \
       "D46 is about the default, not about forbidding the choice"
fi

report
