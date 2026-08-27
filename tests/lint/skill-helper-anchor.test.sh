#!/usr/bin/env bash
# tests/lint/skill-helper-anchor.test.sh
#
# EN12 U8. This guard is INVERTED from what it used to enforce.
#
# It previously required every skill to resolve helpers through
# $ENSEMBLE_ROOT — an install root two levels above the skill directory. That
# convention is what made a skill folder unusable on its own, and what let
# copy-mode installs ship skills whose helpers were not installed at all.
#
# It now enforces the opposite: nothing inside a skill may climb above the skill
# directory, and everything a skill names must resolve inside it. The guard kept
# working throughout the migration by being keyed on per-file state; this
# version is the terminal one, so it is absolute.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skills are self-contained"
cd "$REPO_ROOT"

SKILLS=$(ls -1d skills/*/ | sed 's|skills/||;s|/||')

# --- 1. no skill resolves anything through the old install root ---
for skill in $SKILLS; do
  hits=$(grep -rn 'ENSEMBLE_ROOT' "skills/$skill" 2>/dev/null | head -3 || true)
  if [ -n "$hits" ]; then
    fail "[$skill] still resolves through \$ENSEMBLE_ROOT" "$hits"
  else
    pass "[$skill] no \$ENSEMBLE_ROOT"
  fi
done

# --- 2. no skill reaches into a sibling skill ---
for skill in $SKILLS; do
  hits=$(grep -rn 'skills/en-' "skills/$skill" 2>/dev/null | grep -v "skills/$skill" | head -3 || true)
  if [ -n "$hits" ]; then
    fail "[$skill] names a path inside another skill" "$hits"
  else
    pass "[$skill] no cross-skill paths"
  fi
done

# --- 3. no parent-directory traversal in a helper path ---
# `../` appears legitimately in prose: en-build's worktree location, and
# en-guardrail's documented counter-examples of what its allowlist REFUSES.
# Those describe paths in the user's project, not helper lookups, so the rule
# targets traversal used to reach a file this skill needs.
for skill in $SKILLS; do
  # Any backticked path containing ../ that ends up naming a helper directory,
  # whether the traversal is adjacent (`../references/x`) or goes through a
  # sibling skill first (`../en-plan/references/x`).
  hits=$(grep -rnE '`[^`]*\.\./[^`]*(references|scripts|agents|templates|bin)/' "skills/$skill" 2>/dev/null | head -3 || true)
  if [ -n "$hits" ]; then
    fail "[$skill] traverses upward to reach a helper" "$hits"
  else
    pass "[$skill] no upward helper traversal"
  fi
done

# --- 4. everything a skill names resolves inside it ---
for skill in $SKILLS; do
  missing=""
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    [ -e "skills/$skill/$ref" ] || missing="$missing $ref"
  done < <(grep -rhoE '`(references|templates|agents)/[A-Za-z0-9._/-]+`' "skills/$skill" 2>/dev/null \
             | tr -d '`' | sort -u)
  assert_eq "" "$(echo $missing)" "[$skill] every asset it names resolves locally"
done

# --- 5. executed-shell calls stay anchored (U6's rule, enforced here too) ---
for skill in $SKILLS; do
  bare=$(grep -rnE '(^|[^/"$])(bash|sh) +scripts/[a-z-]+' "skills/$skill/SKILL.md" 2>/dev/null | head -2 || true)
  if [ -n "$bare" ]; then
    fail "[$skill] unanchored executed-shell path" "$bare"
  else
    pass "[$skill] executed-shell calls are anchored"
  fi
done

# --- 6. the old preamble is gone ---
left=$(grep -rl 'Helper resolution' skills/ 2>/dev/null || true)
assert_eq "" "$left" "no skill still carries the \$ENSEMBLE_ROOT helper-resolution preamble"

report
