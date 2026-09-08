#!/usr/bin/env bash
# Guards the two-pass finalize loop, its severity gate, and the shared peer invocation.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan finalize loop"

PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- 1. cap is 1 at every depth (two passes max); no depth-scaled cap survives ---
if grep -qiE "Iteration cap: 1 at every depth" "$PLAN" \
   && grep -qiE "at most \*\*two\*\* peer passes" "$PLAN" \
   && ! grep -qE "Lightweight = 1, Standard = 2, Deep = 2" "$PLAN"; then
  pass "finalize loop caps at one re-review (two peer passes max) at every depth"
else
  fail "cap must be 1 at every depth; the old depth-scaled cap must be gone"
fi

# --- 2. the re-loop is severity-gated: advisory-only results exit instead of re-reviewing ---
if grep -qiE "Severity gate on the re-loop" "$PLAN" \
   && grep -qiE "only if at least one finding this pass was .P0. or .P1." "$PLAN" \
   && grep -qF "reloop_skipped: advisory-only" "$PLAN"; then
  pass "re-loop fires only on P0/P1; advisory-only passes exit auditably"
else
  fail "re-loop must be severity-gated with an auditable advisory-only exit"
fi

# --- 3. the escape hatch survives (a cap change must not remove the override) ---
if grep -qF -- "--max-iterations" "$PLAN" && grep -qF -- "--no-reloop" "$PLAN"; then
  pass "--max-iterations and --no-reloop escape hatches retained"
else
  fail "capping the loop must not remove the manual overrides"
fi

# --- 4. the brief defines severity for a plan, with no quota (EN16 U8) ---------
# Twenty findings across two passes on a 17-unit plan were all P1 at confidence
# >= 7, the auto-apply band, and several were wording fixes. The gate did no
# work because nothing said what a P1 on a plan is. A first draft of the fix
# added a per-unit quota; the peer rejected it (a quota demotes real P1s and
# biases the counts U12 reads), so the definition ships and the quota does not.
BRIEF="$REPO_ROOT/skills/en-plan/references/peer-brief.md"
grep -qF "### Severity on a plan" "$BRIEF" \
  && pass "the brief has a severity-on-a-plan block" \
  || fail "the brief must define severity for a plan" "no '## Severity on a plan' heading"
grep -qE '^\- \*\*P1\*\* is a defect that changes what gets built or fails a phase check' "$BRIEF" \
  && pass "P1 is defined by build impact, naming /en-build's phase check" \
  || fail "P1 must be defined by build impact"
grep -qF "Deduplicate overlapping findings into one" "$BRIEF" \
  && pass "the peer is told to deduplicate" \
  || fail "the brief must ask for deduplication"
grep -qF "batches its apply edits per unit" "$BRIEF" \
  && pass "the host batches apply edits per unit" \
  || fail "the brief must tell the host to batch per unit"
if grep -qiE "one (P1 )?per (three|[0-9]+) units|at most [0-9]+ P1" "$BRIEF"; then
  fail "no numeric P1 quota in the brief" "$(grep -niE 'per (three|[0-9]+) units|at most [0-9]+ P1' "$BRIEF" | head -1)"
else
  pass "no numeric P1 quota in the brief"
fi
# The builder sends the peer ONLY the span from '## What the peer is asked' to
# '## Where a finding points' (ensemble-build-peer-prompt, PLAN_REVIEW_DIMENSIONS).
# The first draft of this block sat below that span, above the routing table,
# where it read well and reached nobody. It must sit inside the span.
sev_line=$(grep -n "### Severity on a plan" "$BRIEF" | head -1 | cut -d: -f1)
asked_line=$(grep -n "^## What the peer is asked" "$BRIEF" | head -1 | cut -d: -f1)
where_line=$(grep -n "^## Where a finding points" "$BRIEF" | head -1 | cut -d: -f1)
[ -n "$sev_line" ] && [ -n "$asked_line" ] && [ -n "$where_line" ] \
  && [ "$asked_line" -lt "$sev_line" ] && [ "$sev_line" -lt "$where_line" ] \
  && pass "severity definitions sit inside the span the builder sends the peer" \
  || fail "severity definitions must sit between 'What the peer is asked' and 'Where a finding points'" "asked=$asked_line sev=$sev_line where=$where_line"
# And the built prompt proves it, rather than the line numbers implying it.
if out=$(printf 'x' | bash "$REPO_ROOT/skills/en-plan/scripts/ensemble-build-peer-prompt" --brief "$BRIEF" --project-context c --goal g --artifact-stdin 2>/dev/null) \
   && printf "%s" "$out" | grep -qF "Severity on a plan"; then
  pass "the built peer prompt carries the severity block"
else
  fail "the built peer prompt must carry the severity block"
fi

report
