#!/usr/bin/env bash
# tests/parity/learn-reference-parity.test.sh
#
# Post-EN13 each skill owns its files outright, so the learn references live as
# byte-identical copies across several skills. Copies drift silently: a fix
# applied to one carrier leaves the others describing a system that no longer
# exists, and the skill reading the stale copy believes it.
#
# Carriership is the file being on disk. It was read from the requires: block
# until 2026-09-01, when the manifest was deleted in favour of deriving payload
# from each skill's body; the pinned counts below are what keeps a new carrier
# deliberate, and they do that job wherever the count is read from.
#
# Superseded note, kept because it explains the counts: carriership was read
# from the DECLARATION, not from the file being
# on disk. EN13's guard discovered carriers by looking for the file, so deleting
# a file and its declaration together left it with nothing to check and nothing
# to say — a guard that stops having an opinion rather than going red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="learn reference parity"

# Expected carrier counts. A drop here is a deletion nobody meant; a rise is a
# new carrier that must be added deliberately, with its declaration.
#
# learnings-research went 4 -> 12 on 2026-08-29: every skill that DISPATCHES an
# agent must carry it, since a skill installs alone and cannot reach another
# skill's directory. See TD9.
#
# 12 -> 11 on 2026-08-30, 11 -> 8 on 2026-08-31: en-brainstorm never
# dispatched it, and neither do en-cross-review, en-ship or en-simplify —
# none of the three mentions research anywhere in its own flow.
# 8 -> 7 on 2026-08-31: D52 removed en-build's, which arrived through a
# persona-dispatch citation in its peer-brief rather than any dispatch it ran. That skill's own
# research-dispatch.md says so outright ("en-brainstorm dispatches no scouts",
# matrix reading "never" at all three depths), so the copy was 150 lines of
# payload that nothing could reach. The sweep that set 12 counted carriers that
# COULD dispatch rather than ones that do.
while IFS='|' read -r rel expected; do
  [ -n "$rel" ] || continue

  present=""
  for skill in "$REPO_ROOT"/skills/*/; do
    [ -f "$skill/$rel" ] && present="$present $(basename "$skill")"
  done
  pn=$(echo $present | wc -w | tr -d ' ')

  assert_eq "$pn" "$expected" "$rel is carried by $expected skill(s)"

  # Byte-identity across the carriers that exist.
  ref=""; skew=0
  for skill in $present; do
    sum=$(shasum "$REPO_ROOT/skills/$skill/$rel" | cut -d' ' -f1)
    [ -z "$ref" ] && ref="$sum"
    [ "$sum" = "$ref" ] || skew=$((skew+1))
  done
  assert_eq "$skew" "0" "$rel: all carried copies are byte-identical"
done <<'CARRIERS'
references/learn-lint.md|2
references/learning-frontmatter-schema.md|2
references/learn-index-format.md|2
agents/learnings-research.md|6
CARRIERS

# The retired taxonomy must not creep back in through any carrier. Character
# classes so the pattern cannot match itself.
PAT='learnings/[b]ugs|learnings/[p]atterns|learnings/[d]ecisions|learnings/<[c]ategory>'
for rel in references/learn-lint.md references/learning-frontmatter-schema.md \
           references/learn-index-format.md agents/learnings-research.md; do
  hits=$(grep -rlE "$PAT" "$REPO_ROOT"/skills/*/"$rel" 2>/dev/null || true)
  if [ -z "$hits" ]; then
    pass "no carrier of $rel references a retired directory"
  else
    fail "no carrier of $rel references a retired directory" "$hits"
  fi
done

report
