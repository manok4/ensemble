#!/usr/bin/env bash
# tests/lint/en-learn-taxonomy-retired.test.sh
#
# The bugs|patterns|decisions taxonomy is retired. A sweep like this is easy to
# leave half-done: the directories stop being created but a reference still tells
# an agent to write into them, and the agent believes the reference.
#
# This asserts the sweep is COMPLETE across every file the skills carry, and that
# what replaced it is coherent — the index groups by artifact type, and the
# frontmatter no longer requires a field whose only job was selecting a directory
# that no longer exists.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="retired taxonomy"

# --- no file references a retired directory ----------------------------------
# Written as a character class so this pattern cannot match itself — an earlier
# guard in this repo matched its own pattern string and could never go red.
PAT='learnings/[b]ugs|learnings/[p]atterns|learnings/[d]ecisions|learnings/<[c]ategory>'

# The prefixed form above was the whole pattern until 2026-08-30, and it missed
# the bare one: a retired directory named WITHOUT `learnings/` in front of it,
# identified as a learning by the word that follows. Two files carried
# "files it as a `decisions/` or `patterns/` learning" and "move to `decisions/`
# learnings" through sixteen copies, telling agents to file into directories the
# EN14 sweep had removed. Requiring the trailing "learning" keeps this off the
# legitimate mentions, which are migration and detection code describing the old
# layout as a layout.
BARE_PAT='`([b]ugs|[p]atterns|[d]ecisions)/`[^|]{0,40}learning'

# Repo-wide since U9. Scoped to en-learn during U8, when only its own nine files
# had been swept; widening this line is what proved U9 finished.
SCOPE="${TAXONOMY_SCOPE:-$REPO_ROOT/skills}"

# Two files must name the retired directories, because their job is to DETECT
# them: capture's legacy-layout check, and en-setup's State-3 probe. Anything else
# naming one is a leftover that would send an agent to write into a directory
# nobody creates any more.
#
# layout-migration.md is deliberately NOT here. It refers to the old layout in
# brace form, so it never matched, and listing it would have been an exemption
# masking nothing — which the staleness check below caught on its first run.
#
# The exemption is a fixed list whose size is asserted, and each entry must still
# actually contain what it is exempted for — so the list cannot grow quietly into
# a hole, and a stale entry cannot sit here masking nothing.
EXEMPT='en-learn/SKILL.md|en-setup/SKILL.md'
# wc -l counts newlines, so a list with no trailing newline undercounts by one.
exempt_n=$(printf '%s' "$EXEMPT" | tr '|' '\n' | grep -c .)
assert_eq "$exempt_n" "2" "exactly two files are exempt from the sweep"

for e in $(printf '%s' "$EXEMPT" | tr '|' ' '); do
  if grep -qE "$PAT" "$REPO_ROOT/skills/$e" 2>/dev/null; then
    pass "exempt file still names the layout it detects: $e"
  else
    fail "exemption is dead — $e no longer names a retired layout; remove it"
  fi
done

hits=$(grep -rlE "$PAT" "$SCOPE" 2>/dev/null | grep -vE "$EXEMPT" || true)
if [ -z "$hits" ]; then
  pass "no file under $(basename "$SCOPE") references a retired category directory"
else
  fail "no file under $(basename "$SCOPE") references a retired category directory" \
       "$(echo "$hits" | sed "s|$REPO_ROOT/||" | tr '\n' ' ')"
fi

# The bare form takes no exemptions: the legitimate mentions describe the old
# layout as a layout and never call one of its directories a learning.
bare=$(grep -rlE "$BARE_PAT" "$SCOPE" 2>/dev/null || true)
if [ -z "$bare" ]; then
  pass "no file files a capture into a retired category directory"
else
  fail "no file files a capture into a retired category directory" \
       "$(echo "$bare" | sed "s|$REPO_ROOT/||" | tr '\n' ' ')"
fi

# --- the index groups by artifact type ---------------------------------------
IDX="$REPO_ROOT/skills/en-learn/references/learn-index-format.md"
assert_file_exists "$IDX" "the index format exists"

for h in Terms Decisions Solutions; do
  grep -q "^## $h\$" "$IDX" \
    && pass "the index has a $h section" \
    || fail "the index has a $h section"
done

# Bugs and Patterns were sections of the old taxonomy, not artifact types.
for h in Bugs Patterns Sources; do
  if grep -q "^## $h\$" "$IDX"; then
    fail "the index no longer has a $h section"
  else
    pass "the index no longer has a $h section"
  fi
done

# --- category leaves the frontmatter schema ----------------------------------
# Its only job was selecting a directory. With the directory gone, a required
# field nobody reads is bookkeeping that rots.
SCHEMA="$REPO_ROOT/skills/en-learn/references/learning-frontmatter-schema.md"
if grep -qE '^\| `category` \| yes' "$SCHEMA"; then
  fail "category is no longer a required frontmatter field"
else
  pass "category is no longer a required frontmatter field"
fi

# The six that remain, and applies_when still second — it is the field retrieval
# depends on, and burying it was the problem the reduction fixed.
for f in title applies_when date tags related status; do
  grep -qE "^\| \`$f\` \| yes" "$SCHEMA" \
    && pass "required field retained: $f" \
    || fail "required field retained: $f"
done

second=$(grep -oE '^\| `[a-z_]+` \| yes' "$SCHEMA" | sed -n '2p' | grep -oE '`[a-z_]+`' | tr -d '`')
assert_eq "$second" "applies_when" "applies_when is still the second field"

# --- the flat solution path --------------------------------------------------
flat "$SCHEMA" | grep -q 'docs/learnings/<slug>-<date>.md' \
  && pass "the schema names the flat solution path" \
  || fail "the schema names the flat solution path"

# --- the research agent reports artifact types -------------------------------
# It reads index.md first, so its output shape is what every caller of
# learnings-research sees. A "category" field naming a directory that no longer
# exists would be a contract nobody can satisfy.
AGENT="$REPO_ROOT/skills/en-learn/agents/learnings-research.md"
assert_file_exists "$AGENT" "the learnings-research agent exists"

grep -q '"artifact_type"' "$AGENT" \
  && pass "the agent reports artifact_type" \
  || fail "the agent reports artifact_type"

if grep -qE '"category":\s*"(bugs|patterns|decisions)' "$AGENT"; then
  fail "the agent no longer reports a retired category value"
else
  pass "the agent no longer reports a retired category value"
fi

grep -q '"artifact_type": "term | decision | solution | source"' "$AGENT" \
  && pass "the agent's type enum lists all four artifact kinds" \
  || fail "the agent's type enum lists all four artifact kinds"

report
