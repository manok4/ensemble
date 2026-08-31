#!/usr/bin/env bash
# tests/lint/en-plan-test-seams.test.sh
#
# en-plan specified test SCENARIOS in detail — four categories, concrete inputs
# and outcomes, a lint rule, a pre-write check — and said nothing about WHERE
# those tests observe the system.
#
# The consequence is per-unit and invisible at review time: each unit picks its
# own boundary, so the suite ends up with three ways to fake the same dependency
# and no way to run the feature end to end. Nothing in the plan is wrong; the
# tests just do not compose.
#
# From to-spec, whose whole file is 75 lines and whose best idea is this one.
# Three rules in priority order, because they conflict: an existing low seam
# beats a new high one, and "highest" without "existing first" pushes every plan
# toward a new end-to-end harness.
#
# Plan-level on purpose. A per-unit seam decision is the defect, not the fix.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan test seams"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
TMPL="$REPO_ROOT/skills/en-plan/references/templates/plan-template.md"

# --- 1. the decision is asked, and it is asked once at plan level ---
if grep -qiE 'which \*\*seams\*\* do we test at' "$SKILL" \
   && grep -qiE 'plan-level decision, made once' "$SKILL"; then
  pass "seams are asked in the planning round and decided once for the plan"
else
  fail "seams must be a plan-level question, not a per-unit one" \
       "a per-unit seam decision is the defect this fixes"
fi

# --- 2. all three rules, and their ordering ---
# Ordering is load-bearing: "highest" without "existing first" pushes every plan
# toward building a new end-to-end harness it did not need.
missing=""
grep -qiE 'prefer a seam that already exists' "$SKILL" || missing="$missing existing-first"
grep -qiE 'highest seam that can still observe' "$SKILL" || missing="$missing highest"
grep -qiE 'keep the set small' "$SKILL" || missing="$missing few"
grep -qiE 'Three rules, in order' "$SKILL" || missing="$missing ordering"
[ -z "$missing" ] \
  && pass "the three seam rules are present and explicitly ordered" \
  || fail "the seam rules are incomplete or unordered" "missing:$missing"

# --- 3. the reason, so the next editor cannot read it as ceremony ---
if grep -qiE 'inventing its own mock boundary' "$SKILL"; then
  pass "the section states what it prevents"
else
  fail "the seam rules must say what they prevent, or they read as ceremony"
fi

# --- 4. the plan carries the decision forward ---
# Asked but not recorded is worse than not asked: the answer dies in the
# conversation and every unit re-decides anyway.
if grep -qE '^## Test seams' "$TMPL" && grep -qiE 'inherited by every unit' "$TMPL"; then
  pass "the template records the seam decision for the units to inherit"
else
  fail "the template must carry the seam decision" \
       "asked but unrecorded is worse than unasked — every unit re-decides"
fi

# --- 5. it is omittable ---
if grep -qiE 'Omit this section when the plan adds no tests' "$TMPL"; then
  pass "the section is omittable on plans that add no tests"
else
  fail "a mandatory seams section becomes boilerplate on doc-only plans"
fi

report
