#!/usr/bin/env bash
# tests/parity/research-dispatch-parity.test.sh
#
# The dispatch group: the matrix that says which skill spawns which scout, the
# scout definitions themselves, and the tier table that assigns each a model.
# Every skill that dispatches carries its own byte-identical copy, because a
# skill installs alone and cannot reach a sibling's directory.
#
# Written 2026-09-03, after an en-sweep change edited seven copies of
# research-dispatch.md by hand. Nothing would have caught a missed one. The
# copies were identical then, so this pins a property that already held rather
# than repairing a drift.
#
# The counts are the guard, not the byte-identity. A file's carriers are the
# skills that dispatch it, so a count change means a skill started or stopped
# dispatching, and that belongs in a commit message. Update the number here and
# say why below.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="research dispatch parity"

# agents/learnings-research.md is deliberately absent: tests/parity/learn-
# reference-parity.test.sh already pins it, and two tests asserting one count
# means one of them goes stale silently.
#
# research-dispatch.md 7: en-brainstorm, en-debug, en-foundation, en-learn,
#   en-plan, en-review, en-sweep. en-sweep and en-debug carry it for the
#   evidence-dossier protocol their one scout follows, not for the matrix.
# repo-research.md 4: en-debug, en-foundation, en-plan, en-sweep. en-review
#   is not among them: it dispatches only learnings-research, and carries the
#   matrix for that row and for the dossier protocol.
# web-research.md 2: en-learn, en-plan.
# agent-dispatch.md 8: every skill that dispatches any agent at all.
while IFS='|' read -r rel expected; do
  [ -n "$rel" ] || continue

  present=""
  for skill in "$REPO_ROOT"/skills/*/; do
    [ -f "$skill/$rel" ] && present="$present $(basename "$skill")"
  done
  pn=$(echo $present | wc -w | tr -d ' ')

  assert_eq "$pn" "$expected" "$rel is carried by $expected skill(s)"

  ref=""; skew=0
  for skill in $present; do
    sum=$(shasum "$REPO_ROOT/skills/$skill/$rel" | cut -d' ' -f1)
    [ -z "$ref" ] && ref="$sum"
    [ "$sum" = "$ref" ] || skew=$((skew+1))
  done
  assert_eq "$skew" "0" "$rel: all carried copies are byte-identical"
done <<'CARRIERS'
references/research-dispatch.md|7
references/agent-dispatch.md|8
agents/repo-research.md|4
agents/web-research.md|2
CARRIERS

# Every skill carrying the matrix must appear in it. A skill with no row is how
# a scout stays reachable while nothing dispatches it: en-foundation kept 297
# lines that way, en-setup 439, en-sweep 150. Each was found by reading, not by
# a test, which is what this assertion changes.
MATRIX="$REPO_ROOT/skills/en-plan/references/research-dispatch.md"
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  [ -f "$skill/references/research-dispatch.md" ] || continue
  if grep -qF "\`$name\` |" "$MATRIX"; then
    pass "$name has a row in the dispatch matrix"
  else
    fail "$name has a row in the dispatch matrix" "carries the matrix but is not in it"
  fi
done

report
