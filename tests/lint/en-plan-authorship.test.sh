#!/usr/bin/env bash
# tests/lint/en-plan-authorship.test.sh
#
# The host authors the plan; the peer only reviews it. D30 states this in the
# shared outside-voice.md, but en-plan never said it in its own flow — so
# nothing in the skill stopped a future edit from having the peer draft units,
# and the reason the rule exists (a peer that edits races the host on the same
# paths) lived one file away from the step that dispatches one.
#
# The distinction this guards is PEER vs WORKER. /en-build dispatches the other
# agent as a worker that implements and edits files; /en-plan has no worker.
# Conflating the two is exactly how a reviewer starts writing code, so the skill
# names the difference rather than leaving it to be inferred from role prompts
# in another skill's references.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan authorship"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
OV="$REPO_ROOT/skills/en-plan/references/outside-voice.md"

# --- 1. the invariant is stated in the skill's own flow ---
if grep -qiE 'The host authors; the peer only reviews' "$SKILL" \
   && grep -qiE 'does not draft units, edit the plan file' "$SKILL"; then
  pass "en-plan states that the host authors and the peer only reviews"
else
  fail "en-plan must state the authorship invariant in its own flow" \
       "leaving it only in the shared reference is what let it go unsaid here"
fi

# --- 2. it sits with the step that dispatches the peer ---
# Stated anywhere else it is trivia; stated here it is a precondition.
inv=$(grep -n 'The host authors; the peer only reviews' "$SKILL" | head -1 | cut -d: -f1)
peer=$(grep -n 'Outside Voice review with finalize loop' "$SKILL" | head -1 | cut -d: -f1)
invoke=$(grep -n 'Invoke via' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$inv" ] && [ -n "$peer" ] && [ -n "$invoke" ] \
   && [ "$inv" -gt "$peer" ] && [ "$inv" -lt "$invoke" ]; then
  pass "the invariant sits inside the peer step, before the invocation"
else
  fail "the invariant must sit in the peer step, before the peer is invoked" \
       "step=$peer invariant=$inv invoke=$invoke"
fi

# --- 3. peer and worker are distinguished ---
if grep -qiE 'Do not confuse a peer with a \*\*worker\*\*' "$SKILL" \
   && grep -qiE 'en-plan. has no worker' "$SKILL"; then
  pass "the peer/worker distinction is named, and en-plan disclaims a worker"
else
  fail "peer and worker must be distinguished" \
       "conflating them is how a reviewer starts writing code"
fi

# --- 4. the contract it cites still says what it claims ---
# Citing D30 is only worth anything while D30 still forbids peer edits.
if grep -qiE 'Peer reports, host applies' "$OV" \
   && grep -qiE 'does \*\*not\*\* edit files' "$OV"; then
  pass "the cited contract still forbids peer edits"
else
  fail "the cited contract no longer says what en-plan claims it says" \
       "outside-voice.md must still carry 'peer reports, host applies'"
fi

report
