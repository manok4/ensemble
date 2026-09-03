#!/usr/bin/env bash
# tests/lint/intra-file-step-citations.test.sh
#
# A skill that cites its own steps by number must cite steps that exist, in an
# order that makes sense.
#
# cross-file-step-citations.test.sh forbids one file citing another file's step
# number, because those drift independently. Nothing checked citations WITHIN a
# file — and en-setup, the largest skill, had accumulated a step numbered 13a
# sitting between 14 and 15, plus a step whose text cited itself.
#
# WHAT THIS CAN AND CANNOT CATCH. It catches a citation to a step that does not
# exist, and a step list that goes backwards. It CANNOT catch a citation that
# names a real step which is simply the wrong one — "step 13" where 14 was meant
# resolves fine. That class needs the meaning, not the number, so the en-setup
# suite pins those individually. Do not read a pass here as "the citations are
# correct"; read it as "none of them dangle and the order is sane".

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="intra-file step citations"
cd "$REPO_ROOT"

dangling=""
backwards=""

for f in skills/*/SKILL.md; do
  skill=$(basename "$(dirname "$f")")

  # Steps this file defines. Two spellings, both real: a top-level "13a. **" and
  # a nested sub-step written as "   **9a. Mandatory safety gate.**". Matching
  # only the first reported en-build's own 4a/9a/9d as dangling.
  defined=$( { grep -oE '^[[:space:]]*[0-9]+[a-z]?\. \*\*' "$f" | grep -oE '[0-9]+[a-z]?'
               grep -oE '\*\*[0-9]+[a-z]?\.' "$f" | grep -oE '[0-9]+[a-z]?'
             } | sort -u )
  [ -n "$defined" ] || continue

  # Steps this file cites: "step 12", "step 13a". Skip prose about another
  # skill's steps — that is cross-file-step-citations' job, not this one.
  cited=$(grep -oE '\bstep [0-9]+[a-z]?\b' "$f" | grep -oE '[0-9]+[a-z]?' | sort -u)
  for c in $cited; do
    printf '%s\n' "$defined" | grep -qx -- "$c" || dangling="$dangling $skill:step-$c"
  done

  # Order, within a section. A "## " heading legitimately restarts numbering —
  # en-setup's State 1/2/3 flows each begin at 1 — so the counter resets there.
  # Without the reset every multi-section skill reported a false backwards jump.
  prev=0
  while IFS= read -r line; do
    case "$line" in
      '## '*) prev=0; continue ;;
    esac
    n=$(printf '%s' "$line" | grep -oE '^[0-9]+[a-z]?\. \*\*' | grep -oE '^[0-9]+[a-z]?')
    [ -n "$n" ] || continue
    num=$(printf '%s' "$n" | grep -oE '^[0-9]+')
    [ "$num" -lt "$prev" ] && backwards="$backwards $skill:$n-after-$prev"
    prev="$num"
  done < "$f"
done

[ -z "$dangling" ] \
  && pass "every cited step number is a step the same file defines" \
  || fail "every cited step number is a step the same file defines" "$(echo $dangling)"

[ -z "$backwards" ] \
  && pass "step numbers never go backwards down a file" \
  || fail "step numbers never go backwards down a file" "$(echo $backwards)"

report
