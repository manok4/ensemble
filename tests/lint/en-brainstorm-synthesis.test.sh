#!/usr/bin/env bash
# tests/lint/en-brainstorm-synthesis.test.sh
#
# The synthesis is the user's last chance to correct scope before the design doc
# lands, and it was the thinnest step in the skill: "Show synthesis to the user.
# Confirm or iterate. One round usually suffices." One line, after seventeen
# steps of carefully specified interview.
#
# Two failure modes it now defends against, both from ce-brainstorm's version:
#
#   The comprehensive audit. Everything the dialogue settled, presented back in
#   full. Too much for a user to actually weigh in on, so they say "looks good"
#   without reading, and the checkpoint stops being one.
#
#   The unconfirmed write. A user revises, the change feels small, the agent
#   writes the file. The synthesis was never confirmed — the last thing the user
#   saw was their own correction, not the corrected whole.
#
# The bullet budget is the load-bearing part of the first, and "a revision is
# not a confirmation" of the second.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm synthesis"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"

# --- 1. the four sections, and the rule that empty ones are dropped ---
missing=""
for sec in "What we're building" "Key trade-offs" "Not in scope" "Call-outs"; do
  grep -qF "$sec" "$SKILL" || missing="$missing '$sec'"
done
grep -qiE 'never pad one to fill it' "$SKILL" || missing="$missing no-padding-rule"
[ -z "$missing" ] \
  && pass "the synthesis names its four sections and forbids padding an empty one" \
  || fail "the synthesis must name its four sections and forbid padding" "missing:$missing"

# --- 2. the budget exists, covers every depth, and refuses to be raised ---
# Coupled to the canonical depth table: a depth that exists there but carries no
# budget row is a tier with no ceiling, which is the same as no budget at all.
# Scoped to the budget table's own rows. SKILL.md has a second table keyed by
# the same three depths (Depth scaling), and a whole-file grep for "| Deep |"
# was satisfied by that one with the budget row deleted.
bud_hdr=$(grep -nE '^ *\| Depth \| Typical \| Ceiling \|$' "$SKILL" | head -1 | cut -d: -f1)
bud_end=$(awk -v p="${bud_hdr:-0}" 'NR>p+1 && $0 !~ /^ *\|/ {print NR; exit}' "$SKILL")
depth_missing=""
if [ -z "$bud_hdr" ]; then
  depth_missing=" budget-table"
else
  for d in Lightweight Standard Deep; do
    awk -v a="$bud_hdr" -v b="$bud_end" 'NR>a && NR<b' "$SKILL" \
      | grep -qE "^ *\| $d \| [0-9]" || depth_missing="$depth_missing $d"
  done
fi
grep -qiE 'do not raise the cap, re-cut' "$SKILL" || depth_missing="$depth_missing re-cut-rule"

[ -z "$depth_missing" ] \
  && pass "every depth carries a bullet ceiling, and the cap is re-cut rather than raised" \
  || fail "every depth needs a bullet ceiling and the no-raise rule" "missing:$depth_missing"

# --- 3. a revision is not a confirmation ---
if grep -qiE 'A revision is not a confirmation' "$SKILL" \
   && grep -qiE 're-present the revised synthesis' "$SKILL"; then
  pass "a revision re-presents and waits rather than writing"
else
  fail "a revision must re-present and wait" \
       "writing after a revision means the synthesis the user confirmed was never shown"
fi

# --- 4. the soft-cut counts items, not rounds ---
# Counting rounds would cut off a user productively revising different things,
# which is the mechanism working rather than failing.
if grep -qiE 'not on round count' "$SKILL" \
   && grep -qiE 'same decision.{0,30}revised twice' "$SKILL" \
   && grep -qiE 'not by wording or section' "$SKILL"; then
  pass "the soft-cut fires on a repeated decision, tracked by decision rather than wording"
else
  fail "the soft-cut must fire on item circularity, not round count"
fi

# --- 5. the affirmability test keeps doc-body content out of the call-outs ---
if grep -qiE 'affirmability test' "$SKILL" && grep -qiE 'read code to judge it' "$SKILL"; then
  pass "call-outs are filtered by the affirmability test"
else
  fail "call-outs need the affirmability test, or they fill with doc-body detail"
fi

# --- 6. the synthesis still precedes the write ---
syn=$(grep -n 'Show synthesis to the user' "$SKILL" | head -1 | cut -d: -f1)
wri=$(grep -n 'Write the design doc' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$syn" ] && [ -n "$wri" ] && [ "$syn" -lt "$wri" ]; then
  pass "the synthesis precedes the write (synthesis=$syn write=$wri)"
else
  fail "the synthesis must precede the write" "synthesis=$syn write=$wri"
fi

report
