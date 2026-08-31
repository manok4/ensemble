#!/usr/bin/env bash
# tests/lint/en-plan-unit-contracts.test.sh
#
# /en-build dispatches a worker per unit with `{UNIT_BLOCK}` — that unit's block
# verbatim — plus an AGENTS.md excerpt. Nothing else. The U7 worker never sees
# U3's block, so when the plan names `clearLayers()` in U3 and
# `clearFullLayers()` in U7, the U7 worker faithfully implements a call to a
# function that does not exist. The plan authored the bug; the worker only
# transcribed it.
#
# Two defenses, and they are a pair. The Interfaces block gives a unit the names
# its neighbours expose. The consistency check is what makes those names agree
# in the first place — an Interfaces block full of mismatched names is worse
# than none, because it reads authoritative.
#
# Both are self-gating. Most units share no surface with a neighbour, and an
# Interfaces block invented for one of those is noise a worker has to read past.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan unit contracts"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
TMPL="$REPO_ROOT/skills/en-plan/references/templates/plan-template.md"

# --- 1. the Interfaces block exists in both the metadata list and the template ---
if grep -qF '**Interfaces:**' "$SKILL" && grep -qF '**Interfaces:**' "$TMPL" \
   && grep -qiE 'Produces' "$TMPL" && grep -qiE 'Consumes' "$TMPL"; then
  pass "units can declare Produces/Consumes, in both the skill and the template"
else
  fail "the Interfaces block must appear in the per-unit metadata AND the template"
fi

# --- 2. it is self-gating, and says why it exists ---
# Without the omit clause every unit grows a block; without the reason, the next
# editor cannot tell whether it is decoration.
if grep -qiE 'omit (it entirely )?(unless|when)' "$SKILL" \
   && grep -qiE 'never sees U3|worker never sees' "$SKILL"; then
  pass "the block is self-gating and states the dispatch fact that motivates it"
else
  fail "the Interfaces block must be self-gating and explain the per-unit dispatch"
fi

# --- 3. the consistency check runs before the plan is written ---
# After the write it would be a review comment; before it, it is a fix.
cons=$(grep -n 'Name and signature consistency' "$SKILL" | head -1 | cut -d: -f1)
write=$(grep -nE '^[0-9]+\. \*\*Write the plan\.\*\*' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$cons" ] && [ -n "$write" ] && [ "$cons" -lt "$write" ]; then
  pass "the consistency check runs before the write (check=$cons write=$write)"
else
  fail "the consistency check must run before the plan is written" "check=$cons write=$write"
fi

# --- 4. the placeholder list names the ones a per-unit worker cannot resolve ---
# "similar to U3" is the load-bearing entry: it is harmless for a human reading
# the whole plan and unresolvable for a worker holding one unit.
missing=""
for ph in 'TBD' 'handle edge cases' 'similar to U3' 'write tests for the above'; do
  grep -qiF "$ph" "$SKILL" || missing="$missing '$ph'"
done
[ -z "$missing" ] \
  && pass "the no-placeholder list names the forms a per-unit worker cannot resolve" \
  || fail "the no-placeholder list is incomplete" "missing:$missing"

report
