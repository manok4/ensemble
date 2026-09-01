#!/usr/bin/env bash
# tests/lint/en-build-unit-loop.test.sh
#
# Two things the unit loop must do that it did not, both taken from ce-work's
# implementation loop.
#
# IDEMPOTENCY. --from U<N> and --from-phase P<N> exist precisely to resume into
# a build that already ran, and nothing checked whether the unit's work was
# already there. Reimplementing is not just wasted work: it churns a diff the
# branch-level review at step 10 then has to read, on a branch where the real
# change is somewhere else.
#
# THE SYSTEM-WIDE CHECK. Unit tests prove the unit's logic. They say nothing
# about what the unit sits inside — the callbacks that fire, whether the tests
# run real objects or only mocks, whether a failure strands persisted state.
# The plan specifies WHICH scenarios to test; this is the pass that asks
# whether the tests touch the real chain at all.
#
# Both are self-gating, and the skip rule is guarded alongside the mechanism:
# an unconditional five-question audit on every trivial unit is a tax that gets
# skipped wholesale, which is worse than not having it.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build unit loop"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"

# --- 1. the idempotency check, and the resume flags that motivate it ---
if grep -qiE 'check whether the unit is already done' "$SKILL" \
   && grep -qiE 'Do not silently reimplement' "$SKILL" \
   && grep -qF -- '--from U<N>' "$SKILL"; then
  pass "the loop checks for already-satisfied units before implementing"
else
  fail "the loop must check whether a unit's work already exists" \
       "--from and --from-phase resume into builds that may already have run"
fi

# --- 2. all five system-wide questions, not a subset ---
# Dropping one is how this degrades into a reminder to "think about side
# effects", which is what it replaced.
missing=""
for q in 'What fires when this runs' 'exercise the real chain' 'orphaned state' \
         'other interfaces expose this' 'error strategies agree'; do
  grep -qiF "$q" "$SKILL" || missing="$missing '$q'"
done
[ -z "$missing" ] \
  && pass "the system-wide check asks all five questions" \
  || fail "the system-wide check is incomplete" "missing:$missing"

# --- 3. it is skippable for leaf changes ---
if grep -qiE 'Skip it entirely for a leaf change' "$SKILL"; then
  pass "the check is skippable for leaf changes"
else
  fail "the system-wide check must be skippable" \
       "an unconditional audit on trivial units gets skipped wholesale"
fi

# --- 4. it runs at the verification gate, before the commit ---
# After the commit it is a review finding; before it, it is a fix.
chk=$(grep -n 'System-wide check' "$SKILL" | head -1 | cut -d: -f1)
com=$(grep -n '\*\*9e\. Commit\.\*\*' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$chk" ] && [ -n "$com" ] && [ "$chk" -lt "$com" ]; then
  pass "the system-wide check runs before the commit (check=$chk commit=$com)"
else
  fail "the system-wide check must run before the unit commits" "check=$chk commit=$com"
fi

report
