#!/usr/bin/env bash
# tests/lint/en-plan-warranted-gate.test.sh
#
# en-plan always wrote a file. A one-line dependency bump got U-IDs, a peer
# pass, a plan hash and a commit — ceremony that costs more than it returns and
# leaves a plan in docs/plans/active/ that someone has to close out.
#
# This is the same defect fixed in en-brainstorm, where the doc-skip offer sat
# in a trailing section no numbered step reached. Here there was no offer at all.
#
# Two properties make the gate safe rather than a hole:
#
#   It is reachable. Inside the write step, as its first precondition. A gate in
#   a section the flow never enters is not a gate — that was en-brainstorm's bug.
#
#   It is honest about the consequence. /en-build consumes a plan file. Decline
#   the file and there is nothing to build, so the offer says so instead of
#   implying a handoff that cannot happen.
#
# And risk surfaces are carved out, because "one small unit touching auth" is
# exactly the shape that most wants a written plan and a peer pass.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan warranted gate"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- 1. the gate is inside the numbered flow ---
proc=$(grep -n '^## Process' "$SKILL" | head -1 | cut -d: -f1)
endp=$(awk -v p="$proc" 'NR>p && /^## / {print NR; exit}' "$SKILL")
gate=$(grep -n 'Is a plan file warranted' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$gate" ] && [ "$gate" -gt "$proc" ] && [ "$gate" -lt "$endp" ]; then
  pass "the gate sits inside the numbered flow (line $gate, flow $proc-$endp)"
else
  fail "the gate must sit inside the numbered flow" "gate=$gate flow=$proc-$endp"
fi

# --- 2. it fires before the write, not after ---
write=$(grep -n 'Then write to .docs/plans/active' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$gate" ] && [ -n "$write" ] && [ "$gate" -lt "$write" ]; then
  pass "the gate precedes the write (gate=$gate write=$write)"
else
  fail "the gate must precede the write" "gate=$gate write=$write"
fi

# --- 3. every skip condition is present; losing one widens the hole ---
missing=""
for c in 'Lightweight' 'one unit' 'risk:' 'gated: true' 'resume' 'did not ask'; do
  grep -qiF "$c" "$SKILL" || missing="$missing '$c'"
done
[ -z "$missing" ] \
  && pass "the skip requires every condition (depth, size, risk, gating, resume, user intent)" \
  || fail "a skip condition went missing" "missing:$missing"

# --- 4. risk surfaces are never offered the skip ---
if grep -qiE 'Never offer the skip' "$SKILL" \
   && grep -qiE 'authentication, payments, migrations' "$SKILL"; then
  pass "risk surfaces are carved out of the skip"
else
  fail "risk surfaces must never be offered the skip"
fi

# --- 5. the no-file consequence is stated, not implied ---
if grep -qiE '/en-build. is not available|no file, no U-IDs' "$SKILL" \
   && grep -qiE 'consumes a plan file' "$SKILL"; then
  pass "declining the file names its consequence for /en-build"
else
  fail "the no-file path must state that /en-build cannot run" \
       "implying a handoff that cannot happen is worse than writing the file"
fi

report
