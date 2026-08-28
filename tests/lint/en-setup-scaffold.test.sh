#!/usr/bin/env bash
# tests/lint/en-setup-scaffold.test.sh
#
# What /en-setup creates is the shape every downstream skill assumes. If it still
# creates the retired directories, a fresh repo starts in the layout the rest of
# the system stopped supporting, and nothing announces the mismatch — capture
# writes flat while setup built somewhere else.
#
# The scaffold is executed by a model following SKILL.md, so these assertions
# check the specification and the verification checklist that the run reports
# against. Nothing here runs ./setup: the live install must not be touched.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup scaffold"

SKILL="$REPO_ROOT/skills/en-setup/SKILL.md"

# --- the skeleton creates the new layout -------------------------------------
# Scoped to the fenced skeleton block. Grepping the whole file also matched the
# checklist and the seeding step, so a line removed from the skeleton itself
# left these green.
SKEL=$(awk '/Create directory skeleton/,/^   - Use the platform/' "$SKILL")

for want in 'CONTEXT.md' 'decisions/' 'learnings/'; do
  printf '%s' "$SKEL" | grep -q "$want" \
    && pass "the skeleton block creates $want" \
    || fail "the skeleton block creates $want"
done

# --- and no longer the retired one -------------------------------------------
# The braces form is what the skeleton used, so match it directly.
if printf '%s' "$SKEL" | grep -q 'learnings/{bugs,patterns,decisions,sources}'; then
  fail "the skeleton no longer creates the retired directories"
else
  pass "the skeleton no longer creates the retired directories"
fi

# --- the verification checklist matches what is created ----------------------
# A checklist that asserts the old shape would report a correct run as broken,
# or worse, pass a run that built the wrong tree.
for want in 'docs/decisions/' 'docs/CONTEXT.md'; do
  grep -q "| \`$want\`" "$SKILL" \
    && pass "the verification checklist covers $want" \
    || fail "the verification checklist covers $want"
done

if grep -q '| `docs/learnings/{bugs,patterns,decisions,sources}/`' "$SKILL"; then
  fail "the checklist no longer asserts the four retired directories"
else
  pass "the checklist no longer asserts the four retired directories"
fi

# --- seeding is wired and ordered --------------------------------------------
# CONTEXT.md must be seeded after the skeleton exists, not before.
skel_ln=$(grep -n 'Create directory skeleton' "$SKILL" | head -1 | cut -d: -f1)
seed_ln=$(grep -n 'Seed `docs/CONTEXT.md`' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$skel_ln" ] && [ -n "$seed_ln" ] && [ "$skel_ln" -lt "$seed_ln" ]; then
  pass "CONTEXT.md is seeded after the skeleton exists"
else
  fail "CONTEXT.md is seeded after the skeleton exists" "skeleton=$skel_ln seed=$seed_ln"
fi

# --- State-3 detection still works on the new layout -------------------------
# State 3 means "Ensemble is already here". It probes docs/learnings/, which
# survives the change — asserted so a later edit cannot point it at a directory
# that no longer exists and silently reclassify every existing repo as State 2.
flat "$SKILL" | grep -q 'docs/learnings/ both prese' \
  && pass "State-3 detection probes a directory the new layout still creates" \
  || fail "State-3 detection probes a directory the new layout still creates"

report
