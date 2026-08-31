#!/usr/bin/env bash
# tests/lint/cross-file-step-citations.test.sh
#
# A reference file citing ANOTHER file's step by number cannot tell when that
# number moves. en-brainstorm had six such citations rot, one naming a "step 5a"
# that no longer existed; the two files whose own gate numbers were wrong got
# fixed, because a wrong gate number is visible the moment the gate fires, and
# every backward citation rotted silently.
#
# This sweep found a fifth, already dead: build-handoff.md cited
# "skills/en-build/SKILL.md step 9h.1" and en-build has no 9h.1. Two carriers
# shipped that pointer and nothing noticed.
#
# The rule is narrow on purpose. A file numbering its OWN steps is fine — you
# renumber it and see every reference in the same edit. The hazard is a citation
# that crosses a file boundary, especially in a shared reference whose carriers
# cannot see the target's numbering at all. Those cite the step by NAME.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="cross-file step citations"
cd "$REPO_ROOT"

# A skill name or a SKILL.md, then a numbered step within the same clause.
PAT='(SKILL\.md|/en-[a-z-]+`?)[^.|]{0,45}step [0-9]'

hits=$(grep -rnE "$PAT" skills/*/references/ skills/*/agents/ 2>/dev/null | cut -c1-110 || true)
if [ -z "$hits" ]; then
  pass "no reference or agent file cites another file's step by number"
else
  fail "no reference or agent file cites another file's step by number" \
       "$(echo "$hits" | sed 's|skills/||' | tr '\n' ' ')"
fi

# The anchors that replaced the five citations must still resolve to real steps,
# or the fix traded a stale number for a stale name.
# Anchored to the STEP HEADING, not a mention anywhere in the file. A plain grep
# passed with the step renamed, because en-debug names "surface a hypothesis" in
# its mode table too — the same shape as the decorative clauses this sweep has
# been finding, written into the guard that was meant to prevent them.
missing=""
step_named() {  # $1=skill  $2=heading text
  grep -qiE "^[0-9]+[a-z]?\. \*\*$2" "skills/$1/SKILL.md"
}
step_named en-review 'Resolve the peer decision' || missing="$missing en-review:peer-decision"
step_named en-review 'Outside Voice peer'        || missing="$missing en-review:outside-voice"
step_named en-debug  'Surface a hypothesis'      || missing="$missing en-debug:hypothesis"
step_named en-debug  'Map span'                  || missing="$missing en-debug:map-span"
[ -z "$missing" ] \
  && pass "every named step the references point at still exists" \
  || fail "every named step the references point at still exists" "missing:$missing"

report
