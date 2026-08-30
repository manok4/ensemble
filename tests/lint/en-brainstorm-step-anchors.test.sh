#!/usr/bin/env bash
# tests/lint/en-brainstorm-step-anchors.test.sh
#
# en-brainstorm's references pointed at step numbers that had shifted under
# them. Six sites were stale, and one named a "step 5a" that no longer existed
# at all. Nothing caught it because a reference file cannot tell from inside
# itself that the number it cites has moved.
#
# The tell is which sites drifted. The two GATED files carried correct numbers
# in their own headings — a wrong gate number is visible the moment the gate
# fires, so those got fixed. Every backward reference into the flow had no such
# pressure and rotted quietly.
#
# The fix is structural, not clerical: cross-file references name the step
# ("the frontier rounds", "the bounded existing-context scan") instead of
# numbering it, so inserting or folding a step cannot invalidate them. This
# guard holds that line.
#
# SCOPE. en-brainstorm only. The same drift exists across roughly a dozen other
# skills (~55 sites); widening this rule belongs to each skill's own refinement
# pass, not to a guard that would land red on main.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm step anchors"

SKILL_DIR="$REPO_ROOT/skills/en-brainstorm"

# `research-dispatch.md` is library text carried byte-identically by twelve
# skills; it is checked here too, because en-brainstorm is what its no-scout
# paragraph talks about.
hits=$(grep -rnoE 'step[ -][0-9]+[a-z]?' "$SKILL_DIR" 2>/dev/null || true)

if [ -z "$hits" ]; then
  pass "no cross-file reference cites a step by number"
else
  fail "no cross-file reference cites a step by number" \
       "$(echo "$hits" | sed "s|$REPO_ROOT/||" | tr '\n' ' ')"
fi

# The anchors that replaced them must be defined in SKILL.md, where the flow
# lives. Searching the whole directory would let a sibling reference satisfy the
# check for a step SKILL.md no longer has — the anchor would dangle and this
# guard would still be green.
missing=""
for anchor in "Existing-context scan" "frontier"; do
  grep -qF "$anchor" "$SKILL_DIR/SKILL.md" || missing="$missing '$anchor'"
done
[ -z "$missing" ] && pass "SKILL.md defines the anchors its references point at" \
                  || fail "SKILL.md defines the anchors its references point at" "missing:$missing"

report
