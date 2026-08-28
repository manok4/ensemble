#!/usr/bin/env bash
# tests/lint/layout-migration.test.sh
#
# This repo has zero learning entries. Other repos, where these skills are
# installed, may have hundreds under the retired directories. Without a migration
# they become invisible: the validator stops matching those paths and research
# stops finding them, and nobody is told.
#
# The peer flagged this as a P0 across two review iterations. The failure mode is
# not a crash — it is a knowledge base that quietly stops being read.
#
# SCOPE (TD7): running the migration is model behaviour driven by a reference.
# These assertions check that the procedure specifies every safeguard, and drive
# the deterministic parts (collision detection, cross-ref rewriting) against a
# populated fixture store.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="layout migration"

REF="$REPO_ROOT/skills/en-learn/references/layout-migration.md"
SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"
FIX="$REPO_ROOT/tests/fixtures/legacy-store"

flat() { tr '\n' ' ' < "$1" | sed 's/[*_`]//g; s/  */ /g'; }

assert_file_exists "$REF" "the migration reference exists"

# --- the fixture store is genuinely adversarial ------------------------------
# A migration fixture with no collision proves nothing about collisions.
assert_file_exists "$FIX/docs/learnings/patterns/single-flight-2026-03-20.md" "fixture: patterns entry"
assert_file_exists "$FIX/docs/learnings/bugs/single-flight-2026-03-20.md"     "fixture: colliding basename"
assert_file_exists "$FIX/docs/learnings/decisions/drizzle-over-prisma-2026-02-10.md" "fixture: legacy decision"
assert_file_exists "$FIX/docs/learnings/sources/openai-harness-2026-04-20.md" "fixture: ingested source"

n=$(find "$FIX/docs/learnings" -name '*.md' | wc -l | tr -d ' ')
assert_eq "$n" "5" "the fixture store holds five entries"

# --- collisions are found BEFORE anything moves ------------------------------
# Flattening three directories onto one is where entries get silently overwritten.
flat "$REF" | grep -qi 'preflight\|before anything moves' \
  && pass "collisions are inventoried before the first move" \
  || fail "collisions are inventoried before the first move"

flat "$REF" | grep -qi 'never permitted\|never overwrite\|no overwrite' \
  && pass "an overwrite is never permitted" \
  || fail "an overwrite is never permitted"

# The deterministic half: the fixture collision is detectable by basename.
dupes=$(find "$FIX/docs/learnings" -mindepth 2 -name '*.md' -not -path '*/sources/*' \
        -exec basename {} \; | sort | uniq -d | wc -l | tr -d ' ')
assert_eq "$dupes" "1" "the fixture's basename collision is detectable before moving"

# --- legacy decisions become ADRs, not flat solutions ------------------------
# Moving them to docs/learnings/ preserves the file and destroys the artifact
# semantics this whole plan exists to draw.
# Matching "decisions ... ADR" also hit the section heading, so deleting the rule
# and the mapping row left this green. Match the mapping's consequence instead.
flat "$REF" | grep -qi 'destroy their artifact semantics\|docs/decisions/NNNN-<slug>.md | Decisions' \
  && pass "legacy decisions convert to ADRs" \
  || fail "legacy decisions convert to ADRs"

flat "$REF" | grep -qi 'surfaced.*rather than guessed\|cannot be.*confidently' \
  && pass "an unconvertible decision is surfaced, not guessed" \
  || fail "an unconvertible decision is surfaced, not guessed"

# --- sources are untouched ---------------------------------------------------
flat "$REF" | grep -qi 'sources.*untouched\|untouched.*sources' \
  && pass "ingested sources keep their path" \
  || fail "ingested sources keep their path"

# --- cross-references are rewritten -----------------------------------------
# related: paths embed the category segment; a move without a rewrite leaves
# every cross-reference dangling.
crossrefs=$(grep -rh 'docs/learnings/\(bugs\|patterns\|decisions\)/' "$FIX" | wc -l | tr -d ' ')
[ "$crossrefs" -ge 2 ] \
  && pass "the fixture has category-bearing cross-references to rewrite ($crossrefs)" \
  || fail "the fixture has category-bearing cross-references to rewrite"

flat "$REF" | grep -qi 'related:.*rewritten\|rewrite every related' \
  && pass "related: paths are rewritten" \
  || fail "related: paths are rewritten"

# --- restartable, and reversible --------------------------------------------
flat "$REF" | grep -qi 'restartable\|interrupt' \
  && pass "an interrupted migration leaves every entry readable" \
  || fail "an interrupted migration leaves every entry readable"

flat "$REF" | grep -qi 'dirty working tree\|refuses to start' \
  && pass "it refuses to start on a dirty tree, so rollback is git checkout" \
  || fail "it refuses to start on a dirty tree, so rollback is git checkout"

flat "$REF" | grep -qi 'idempotent\|second run reports nothing' \
  && pass "running it twice is a no-op" \
  || fail "running it twice is a no-op"

# --- legacy entries stay VALIDATED until migration completes -----------------
# The other half of the P0: dropping legacy-path validation before a repo has
# migrated makes un-migrated entries invisible to lint and research.
flat "$REF" | grep -qi 'until migration completes\|still validated' \
  && pass "legacy paths keep their validation until migration completes" \
  || fail "legacy paths keep their validation until migration completes"

# --- non-interactive refusal -------------------------------------------------
flat "$REF" | grep -qi 'non-interactive\|refuses.*without.*flag' \
  && pass "a non-interactive run refuses rather than guessing" \
  || fail "a non-interactive run refuses rather than guessing"

grep -q 'references/layout-migration.md' "$SKILL" \
  && pass "the migration reference is declared in en-learn's requires:" \
  || fail "the migration reference is declared in en-learn's requires:"

# --- the migration is reachable from capture ---------------------------------
# A procedure nothing invokes is documentation. The check must fire before
# capture writes anything, or the first write lands in a half-migrated store.
flat "$SKILL" | grep -qi 'Legacy-layout check' \
  && pass "capture checks for a legacy layout" \
  || fail "capture checks for a legacy layout"

legacy_ln=$(grep -n 'Legacy-layout check' "$SKILL" | head -1 | cut -d: -f1)
gate_ln=$(grep -n 'Apply the capture gate' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$legacy_ln" ] && [ -n "$gate_ln" ] && [ "$legacy_ln" -lt "$gate_ln" ]; then
  pass "the legacy check runs before anything is written"
else
  fail "the legacy check runs before anything is written" "legacy=$legacy_ln gate=$gate_ln"
fi

flat "$SKILL" | grep -qi 'half-migrated' \
  && pass "capture refuses to write into a half-migrated store" \
  || fail "capture refuses to write into a half-migrated store"

# --- U14: the migration has an entry point someone would find ----------------
# U13 wired one trigger, inside capture. That is backwards for the case the
# procedure exists for: a project with a hundred existing entries would have to
# start writing a NEW learning to be told the old ones are about to go unread.

SETUP="$REPO_ROOT/skills/en-setup/SKILL.md"

grep -q '`--migrate`' "$SKILL" \
  && pass "en-learn has a --migrate mode" \
  || fail "en-learn has a --migrate mode"

# In the modes table, so it is discoverable rather than buried in capture's steps.
sed -n '/^## Modes/,/^## Always-on/p' "$SKILL" | grep -q '`--migrate`' \
  && pass "--migrate appears in the modes table" \
  || fail "--migrate appears in the modes table"

# One procedure, two entry points. Two descriptions would drift.
sed -n '/^## Process — Mode F: `--migrate`/,$p' "$SKILL" | grep -q 'references/layout-migration.md' \
  && pass "the mode reads the same reference capture reads" \
  || fail "the mode reads the same reference capture reads"

# --- en-setup surfaces it on upgrade -----------------------------------------
# The run someone performs when upgrading must not scaffold around a store that
# is about to stop being read.
flat "$SETUP" | grep -qi 'retired.*director\|legacy learning store\|layout-migration' \
  && pass "en-setup detects a legacy learning store" \
  || fail "en-setup detects a legacy learning store"

flat "$SETUP" | grep -qi 'invisible' \
  && pass "en-setup names what is at stake, not just that it found something" \
  || fail "en-setup names what is at stake, not just that it found something"

# en-setup reports and hands off. The procedure is interactive and needs per-entry
# classification, which is not what a scaffolding run is for.
# 'hand off' alone also matched a pre-existing unrelated line ("Hand off to the
# right skill"), so deleting the rule left this green. Match the rule itself.
flat "$SETUP" | grep -qi 'does not run the migration itself' \
  && pass "en-setup hands off rather than running the migration itself" \
  || fail "en-setup hands off rather than running the migration itself"

# --- the reference is carried by both, byte-identical -------------------------
declared=""; present=""
for skill in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$skill")
  grep -q '^  - references/layout-migration.md$' "$skill/SKILL.md" 2>/dev/null && declared="$declared $name"
  [ -f "$skill/references/layout-migration.md" ] && present="$present $name"
done
dn=$(echo $declared | wc -w | tr -d ' '); pn=$(echo $present | wc -w | tr -d ' ')

assert_eq "$dn" "2" "two skills declare the migration reference"
assert_eq "$pn" "$dn" "every declaring skill carries the migration reference"

ref=""; skew=0
for skill in $present; do
  sum=$(shasum "$REPO_ROOT/skills/$skill/references/layout-migration.md" | cut -d' ' -f1)
  [ -z "$ref" ] && ref="$sum"
  [ "$sum" = "$ref" ] || skew=$((skew+1))
done
assert_eq "$skew" "0" "both copies of the migration reference are byte-identical"

report
