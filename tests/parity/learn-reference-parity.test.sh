#!/usr/bin/env bash
# tests/parity/learn-reference-parity.test.sh
#
# Post-EN13 each skill owns its files outright, so the learn references live as
# byte-identical copies across several skills. Copies drift silently: a fix
# applied to one carrier leaves the others describing a system that no longer
# exists, and the skill reading the stale copy believes it.
#
# Carriership is derived from the requires: DECLARATION, not from the file being
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
# 12 -> 11 on 2026-08-30: en-brainstorm never dispatched it. That skill's own
# research-dispatch.md says so outright ("en-brainstorm dispatches no scouts",
# matrix reading "never" at all three depths), so the copy was 150 lines of
# payload that nothing could reach. The sweep that set 12 counted carriers that
# COULD dispatch rather than ones that do.
while IFS='|' read -r rel expected; do
  [ -n "$rel" ] || continue

  declared=""; present=""
  for skill in "$REPO_ROOT"/skills/*/; do
    name=$(basename "$skill")
    grep -q "^  - $rel\$" "$skill/SKILL.md" 2>/dev/null && declared="$declared $name"
    [ -f "$skill/$rel" ] && present="$present $name"
  done
  dn=$(echo $declared | wc -w | tr -d ' ')
  pn=$(echo $present  | wc -w | tr -d ' ')

  assert_eq "$dn" "$expected" "$rel is declared by $expected skill(s)"
  assert_eq "$pn" "$dn"       "$rel: every declaring skill carries the file"

  # Byte-identity across the carriers that exist.
  ref=""; skew=0
  for skill in $present; do
    sum=$(shasum "$REPO_ROOT/skills/$skill/$rel" | cut -d' ' -f1)
    [ -z "$ref" ] && ref="$sum"
    [ "$sum" = "$ref" ] || skew=$((skew+1))
  done
  assert_eq "$skew" "0" "$rel: all carried copies are byte-identical"
done <<'CARRIERS'
references/learn-lint.md|3
references/learning-frontmatter-schema.md|2
references/learn-index-format.md|2
agents/learnings-research.md|11
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
