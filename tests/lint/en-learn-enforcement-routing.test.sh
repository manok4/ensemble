#!/usr/bin/env bash
# tests/lint/en-learn-enforcement-routing.test.sh
#
# EN22 U3. Capture routes a correction to the strongest enforcement layer before
# it writes an artifact. Each clause is scoped to one file and anchored on
# wording only that file carries.
#
# SCOPE (TD7): which layer a candidate gets is a model judgment. These assert the
# specification is wired in, not that a candidate routes correctly.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn enforcement routing"

SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"
GATE="$REPO_ROOT/skills/en-learn/references/capture-gate.md"
TYPES="$REPO_ROOT/skills/en-learn/references/artifact-types.md"

# --- the gate no longer discards an enforceable correction ---
grep -qF 'Already enforced at the strongest feasible layer' "$GATE" \
  && pass "the gate discards only what is already enforced at the strongest layer" \
  || fail "the gate discards only what is already enforced at the strongest layer"
grep -qF 'does not count as enforcement' "$GATE" \
  && pass "the gate says a prose-only rule is not enforcement" \
  || fail "the gate says a prose-only rule is not enforcement"
grep -qF 'If `AGENTS.md`, `CLAUDE.md` or' "$GATE" \
  && fail "the old rule treating a map-file line as enforcement is gone" \
  || pass "the old rule treating a map-file line as enforcement is gone"

# --- artifact types: enforcement is decided before term, decision, solution ---
enf_ln=$(grep -n '^## Enforcement comes first' "$TYPES" | head -1 | cut -d: -f1)
route_ln=$(grep -n '^## Routing' "$TYPES" | head -1 | cut -d: -f1)
if [ -n "$enf_ln" ] && [ -n "$route_ln" ] && [ "$enf_ln" -lt "$route_ln" ]; then
  pass "enforcement is decided before artifact routing ($enf_ln < $route_ln)"
else
  fail "enforcement is decided before artifact routing" "enforcement=$enf_ln routing=$route_ln"
fi
enforcement=$(sed -n '/^## Enforcement comes first/,/^## Routing/p' "$TYPES")
printf '%s' "$enforcement" | grep -qF '`$SKILL_DIR/scripts/ensemble-td-append`' \
  && pass "L1 to L4 file through the appender" || fail "L1 to L4 file through the appender"
printf '%s' "$enforcement" | grep -qiF 'writes no learning file' \
  && pass "an enforcement outcome writes no learning file" || fail "an enforcement outcome writes no learning file"
printf '%s' "$enforcement" | grep -qiF 'filed first' \
  && pass "the entry is filed before the add-now question" || fail "the entry is filed before the add-now question"
printf '%s' "$enforcement" | grep -qF 'CI=true' \
  && pass "unattended callers skip the question" || fail "unattended callers skip the question"
printf '%s' "$enforcement" | grep -qiE '(edit|update|append to|write to) `?(AGENTS|CLAUDE|REVIEW)\.md' \
  && fail "routing never instructs an edit to a map file" \
  || pass "routing never instructs an edit to a map file"

# Worked examples pair an input with its outcome on one table row; assert the
# pairing, not just the input, so a changed outcome fails.
printf '%s' "$enforcement" | grep -qE 'useAuthFetch.*\| L2:' \
  && pass "worked example: useAuthFetch routes to L2" || fail "worked example: useAuthFetch routes to L2"
printf '%s' "$enforcement" | grep -qE 'simplify pass.*\| L4:' \
  && pass "worked example: a skipped simplify pass routes to L4" || fail "worked example: a skipped simplify pass routes to L4"
printf '%s' "$enforcement" | grep -qiF 'invoked capture directly' \
  && pass "only a person-invoked capture is asked the add-now question" \
  || fail "only a person-invoked capture is asked the add-now question"
RUBRIC="$REPO_ROOT/skills/en-learn/references/enforcement-layers.md"
grep -qE 'skill-size\.test\.sh.*' "$RUBRIC" && grep -qF 'no entry' "$RUBRIC" \
  && pass "the rubric carries the already-enforced example" || fail "the rubric carries the already-enforced example"
grep -qF '**L5**, a decision learning' "$RUBRIC" \
  && pass "the rubric carries the L5 example" || fail "the rubric carries the L5 example"

# --- the capture flow names the appender and the L5 fall-through ---
capture_flow=$(sed -n '/^## Process — Mode A/,/^## Process — Mode B/p' "$SKILL")
printf '%s' "$capture_flow" | grep -qF 'references/enforcement-layers.md' \
  && pass "capture reads the rubric" || fail "capture reads the rubric"
printf '%s' "$capture_flow" | grep -qF 'L5' \
  && pass "capture names L5 as the only path to an artifact" \
  || fail "capture names L5 as the only path to an artifact"

report
