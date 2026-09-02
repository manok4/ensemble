#!/usr/bin/env bash
# tests/lint/en-learn-repo-only.test.sh
#
# en-learn captures what THIS repository taught: the constraint someone hit, the
# alternative that was rejected, the word that means something specific here.
# None of that is recoverable by looking anything up, which is exactly why it is
# worth storing.
#
# External material is the opposite: it is lookupable on demand, so a summary in
# the store is a second copy that goes stale and competes with the source. Both
# modes that wrote it — ingest and --pack — shipped and were never used across
# three real projects holding 181 entries.
#
# Removing a mode removes what only it produced. Leaving docs/learnings/sources/
# or docs/references/ behind would leave consumers pointed at directories nothing
# fills, which is worse than removing both.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn repo-only"

LEARN="$REPO_ROOT/skills/en-learn/SKILL.md"

# --- the modes and everything only they produced ------------------------------
# layout-migration.md must name the retired shapes, because migrating away from
# them is its job. Bounded the same way the taxonomy sweep's exemption is: a
# fixed list whose size is asserted, and each entry checked for staleness so it
# cannot outlive what it exempts.
EXEMPT='references/layout-migration.md'
exempt_n=$(printf '%s' "$EXEMPT" | tr '|' '\n' | grep -c .)
assert_eq "$exempt_n" "1" "exactly one file is exempt from the removal sweep"

grep -rqE 'source_uri|learnings/sources' "$REPO_ROOT"/skills/*/"$EXEMPT" 2>/dev/null \
  && pass "the exempt file still names the shapes it migrates away from" \
  || fail "exemption is dead — layout-migration.md no longer names them; remove it"

for token in 'learn-ingest' 'pack-reference' '--pack' 'learnings/sources' 'docs/references/' \
             'source_type' 'source_uri'; do
  hits=$(grep -rl -- "$token" "$REPO_ROOT/skills" 2>/dev/null | grep -vE "$EXEMPT" || true)
  if [ -z "$hits" ]; then
    pass "no skill file references: $token"
  else
    fail "no skill file references: $token" "$(echo "$hits" | sed "s|$REPO_ROOT/||" | tr '\n' ' ')"
  fi
done

# ingest is a common English word; match the mode form only.
if grep -qE 'ingest <path|`ingest`|Mode .: `ingest' "$LEARN"; then
  fail "en-learn no longer offers an ingest mode"
else
  pass "en-learn no longer offers an ingest mode"
fi

# --- files and declarations removed together ---------------------------------
for rel in references/learn-ingest.md references/pack-reference-template.md; do
  nf=$(ls "$REPO_ROOT"/skills/*/"$rel" 2>/dev/null | wc -l | tr -d ' ')
  nd=$(grep -rl "$rel" "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "$nf" "0" "no carrier holds $rel"
  assert_eq "$nd" "0" "no SKILL.md declares $rel"
done

# --- four modes, three artifact types ----------------------------------------
modes=$(grep -c '^## Process — Mode' "$LEARN")
assert_eq "$modes" "4" "en-learn has exactly four modes"

TYPES="$REPO_ROOT/skills/en-learn/references/artifact-types.md"
if grep -qi 'ingested' "$TYPES"; then
  fail "the artifact-type table has no ingested row"
else
  pass "the artifact-type table has no ingested row"
fi

# --- the schema is six fields with no variant --------------------------------
SCHEMA="$REPO_ROOT/skills/en-learn/references/learning-frontmatter-schema.md"
req=$(grep -cE '^\| `[a-z_]+` \| yes' "$SCHEMA")
assert_eq "$req" "6" "the schema has exactly six required fields"

if grep -qE '^\| `(source_type|source_uri|fetched)` \|' "$SCHEMA"; then
  fail "the schema has no ingested-source variant"
else
  pass "the schema has no ingested-source variant"
fi

# --- the index has no Sources section ----------------------------------------
IDX="$REPO_ROOT/skills/en-learn/references/learn-index-format.md"
if grep -q '^## Sources$' "$IDX"; then
  fail "the index format has no Sources section"
else
  pass "the index format has no Sources section"
fi

# --- setup scaffolds neither directory ---------------------------------------
SETUP="$REPO_ROOT/skills/en-setup/SKILL.md"
SKEL=$(awk '/Create directory skeleton/,/^   - Use the platform/' "$SETUP")
for gone in 'sources/' 'references/'; do
  if printf '%s' "$SKEL" | grep -q "$gone"; then
    fail "the skeleton no longer creates docs/$gone"
  else
    pass "the skeleton no longer creates docs/$gone"
  fi
done

# --- no consumer points at a directory nothing fills -------------------------
for tmpl in "$REPO_ROOT"/skills/*/references/templates/agents-md-template.md; do
  [ -f "$tmpl" ] || continue
  if grep -q 'External library references' "$tmpl"; then
    fail "$(basename "$(dirname "$(dirname "$(dirname "$tmpl")")")")'s AGENTS.md template has no dangling references row"
  else
    pass "$(basename "$(dirname "$(dirname "$(dirname "$tmpl")")")")'s AGENTS.md template has no dangling references row"
  fi
done

# --- web-research survives where lookup is the point -------------------------
# It is dispatched during research by plan/brainstorm/foundation. Removing
# en-learn's external modes must not strip the agent from skills that still use it.
wr=$(ls "$REPO_ROOT"/skills/*/agents/web-research.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$wr" "2" "web-research still carried by the two skills that dispatch it"

# --- en-learn scouts the wiki, never the codebase ----------------------------
# It carried a repo-research definition until 2026-09-01, orphaned when the
# one-time pattern-seeding mode that justified it was retired. Nothing in the
# flow dispatched it: the two carried files naming the agent describe what
# en-sweep and en-foundation do with it, and step 12's architecture sync is
# "surgical edits only — never regenerate", which reads no codebase.
#
# The distinction is the skill's whole premise. It captures what reading the
# code CANNOT recover, so an agent whose job is reading the code answers a
# question en-learn is not asking.
[ -e "$REPO_ROOT/skills/en-learn/agents/repo-research.md" ] \
  && fail "en-learn carries no codebase scout" \
  || pass "en-learn carries no codebase scout"

# The half that proves the cut was scoped rather than a blanket removal.
rr=$(ls "$REPO_ROOT"/skills/*/agents/repo-research.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$rr" "5" "repo-research still carried by the five skills that scan a codebase"

# The dispatch site must name the agent it dispatches. It read "dispatch a
# sub-agent" with no name, which is what let the carried definitions drift out
# of any relationship with the flow.
grep -q 'Dispatch the `learnings-research` agent only when the search is genuinely broad' \
  "$REPO_ROOT/skills/en-learn/SKILL.md" \
  && pass "the broad-search escape names the agent it dispatches" \
  || fail "the broad-search escape names the agent it dispatches"

grep -q 'That agent is the only one this skill dispatches' "$REPO_ROOT/skills/en-learn/SKILL.md" \
  && pass "the flow states that it dispatches exactly one agent" \
  || fail "the flow states that it dispatches exactly one agent"

# en-learn had no row in the shared matrix at all, which is the silence that let
# the contradiction sit. A row that says "never" is what a future reader checks.
grep -qE '^\| .en-learn. \| \(any\) \| never \|' \
  "$REPO_ROOT/skills/en-learn/references/research-dispatch.md" \
  && pass "the dispatch matrix carries en-learn's row, and it says never" \
  || fail "the dispatch matrix carries en-learn's row, and it says never"

report
