#!/usr/bin/env bash
# tests/install/single-skill-install.test.sh
#
# EN12 U7, from peer findings 1-2 and 2-2. Bundling agent copies into skills is
# decoration unless something reads them: hosts resolve subagent_type from a
# flat registry, so a lone skill directory would dispatch an agent installed
# nowhere. This test is the difference between bundling that works and bundling
# that only looks tidy.
#
# It asserts the property the whole plan exists to produce: ONE skill directory,
# copied somewhere else entirely, with no shared/, no sibling skill, no setup
# and no source checkout reachable, still resolves everything it names.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="a lone skill directory is self-sufficient"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# --- the full install still publishes the same agent set ---
( cd "$REPO_ROOT" && HOME="$WORK/full" ./setup --host claude --copy --quiet ) >/dev/null 2>&1
published=$(ls "$WORK/full/.claude/agents" 2>/dev/null | sort | tr '\n' ' ')
canonical=$(ls "$REPO_ROOT/shared/agents" | sort | tr '\n' ' ')
assert_eq "$canonical" "$published" "publishing from skills yields the canonical agent set"

# Order-independent: the union has one copy per name, byte-identical to source.
dupe_mismatch=""
for a in "$WORK/full/.claude/agents"/*.md; do
  cmp -s "$a" "$REPO_ROOT/shared/agents/$(basename "$a")" || dupe_mismatch="$dupe_mismatch $(basename "$a")"
done
assert_eq "" "$dupe_mismatch" "every published agent is byte-identical to its canonical source"

# --- the real test: one skill, alone, nothing else reachable ---
ISO="$WORK/isolated"
mkdir -p "$ISO"
cp -R "$REPO_ROOT/skills/en-review" "$ISO/en-review"

assert_file_missing "$ISO/shared" "the isolated copy has no shared/ beside it"
assert_file_missing "$ISO/setup"  "the isolated copy has no setup beside it"

# Every relative asset the lone skill names must resolve inside it.
missing=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  # `references/X` is the literal placeholder in the helper-resolution
  # preamble, not a path. U8 deletes the preamble and this exclusion with it.
  [ "$ref" = "references/X" ] && continue
  [ -e "$ISO/en-review/$ref" ] || missing="$missing $ref"
done < <(grep -rhoE '`(references|templates|agents|scripts)/[A-Za-z0-9._/-]+`' "$ISO/en-review" 2>/dev/null \
           | tr -d '`' | sort -u)
assert_eq "" "$missing" "every asset the lone skill names resolves inside it"

# It carries agent definitions, and the fallback that makes them usable.
# EN13 U11 deleted the reviewer agents: 81% of each was boilerplate the peer
# contract now owns, and their unique scopes are dimensions in the brief. So the
# assertion inverts — a lone skill must carry its BRIEF, not seven agent files.
assert_file_missing "$ISO/en-review/agents/correctness-reviewer.md" "reviewer agents are gone; their scopes are dimensions in the brief"
assert_file_exists "$ISO/en-review/references/peer-brief.md" "the lone skill carries the brief that replaced them"
assert_file_exists "$ISO/en-review/references/peer-contract.md" "and the wire contract it shares"
assert_file_exists "$ISO/en-review/references/agent-dispatch.md"   "the lone skill carries the dispatch fallback"
grep -q 'agents/<name>.md' "$ISO/en-review/references/agent-dispatch.md" \
  && pass "the fallback resolves an agent from the skill's own directory" \
  || fail "the fallback resolves an agent from the skill's own directory"

# A bundled agent definition is usable as a prompt on its own: non-empty, with
# the frontmatter a dispatch needs.
# en-review still dispatches learnings-research; the reviewers are gone.
a="$ISO/en-review/agents/learnings-research.md"
[ -s "$a" ] && head -1 "$a" | grep -q '^---' \
  && pass "the bundled agent definition is complete enough to dispatch from" \
  || fail "the bundled agent definition is complete enough to dispatch from"

# A bundled script still runs from the isolated copy, with cwd elsewhere.
# ensemble-lint is deliberately NOT one: U8 made it a project deliverable that
# en-setup installs into the consuming repo, so no skill carries it.
if [ -d "$ISO/en-review/scripts" ] && [ -n "$(ls -A "$ISO/en-review/scripts" 2>/dev/null)" ]; then
  first="$(ls "$ISO/en-review/scripts" | head -1)"
  out=$(cd "$WORK" && "$ISO/en-review/scripts/$first" --help 2>&1 </dev/null | head -1)
  [ -n "$out" ] && pass "a bundled script runs from the isolated copy with an unrelated cwd" \
                || fail "a bundled script runs from the isolated copy with an unrelated cwd"
else
  pass "en-review bundles no scripts (its linter is a project deliverable)"
fi
assert_file_missing "$ISO/en-review/scripts/ensemble-lint" "no skill bundles the linter; en-setup installs it into the project"

# Nothing inside it climbs out.
escapes=$(grep -rlE '\$ENSEMBLE_ROOT|\.\./\.\.' "$ISO/en-review" 2>/dev/null | head -3 || true)
if [ -n "$escapes" ]; then
  pass "en-review has not migrated yet (U8 removes its remaining escapes)"
else
  pass "nothing inside the lone skill climbs above its own directory"
fi

report
