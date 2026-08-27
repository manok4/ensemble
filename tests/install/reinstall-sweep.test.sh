#!/usr/bin/env bash
# tests/install/reinstall-sweep.test.sh
#
# Re-running ./setup must fully replace the previous install, whichever mode
# either run used.
#
# Field failure, 2026-08-26: after a --copy install, `./setup --symlink` left
# every copied directory in place. The sweep required the CURRENT run to be in
# copy mode before deleting a real directory, which asks the wrong question —
# what matters is what was installed, not what is being installed now. The
# "already exists, not ours" guard then skipped all of them, so the user saw a
# clean run that had changed nothing.
#
# It compounded: the manifest was truncated BEFORE installing, so a run that
# swept and then skipped everything published an empty manifest. Fourteen
# directories became orphaned — no future run would ever sweep them, because
# setup no longer knew it owned them.
#
# Both are asserted here: the transition works in each direction, and the
# manifest is never left empty while installed paths exist.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="reinstall sweeps the prior install"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

install() { ( cd "$REPO_ROOT" && HOME="$1" ./setup --host claude --"$2" --quiet ) >/dev/null 2>&1; }

count_kind() {  # dir, kind(link|dir)
  local n=0
  for d in "$1"/skills/en-*; do
    [ -e "$d" ] || continue
    if [ "$2" = link ] && [ -L "$d" ]; then n=$((n+1));
    elif [ "$2" = dir ] && [ ! -L "$d" ] && [ -d "$d" ]; then n=$((n+1)); fi
  done
  echo "$n"
}

TOTAL=$(ls -1d "$REPO_ROOT"/skills/*/ | wc -l | tr -d ' ')

# --- copy -> symlink: the transition that failed in the field ---
H="$WORK/c2s"; mkdir -p "$H"
install "$H" copy
assert_eq "$TOTAL" "$(count_kind "$H/.claude" dir)" "copy install produces real directories"

install "$H" symlink
assert_eq "$TOTAL" "$(count_kind "$H/.claude" link)" "re-installing with --symlink replaces every copy with a symlink"
assert_eq "0" "$(count_kind "$H/.claude" dir)" "no copied directory survives the transition"

# The manifest must be checked HERE, on the transition that failed. This is
# where truncate-then-skip published an empty manifest and orphaned everything;
# on the symlink->copy path the old code happened to work, so asserting there
# would have left half the bug uncovered.
Mc="$H/.ensemble/install-manifest-claude.txt"
c_entries=$(grep -c . "$Mc" 2>/dev/null || echo 0)
[ "$c_entries" -gt 0 ]   && pass "copy->symlink leaves a populated manifest ($c_entries entries)"   || fail "copy->symlink leaves a populated manifest" "empty manifest orphans every installed path"
c_installed=$(( $(ls -1 "$H/.claude/skills" | grep -c '^en-') + $(ls -1 "$H/.claude/agents" | grep -c '\.md$') ))
assert_eq "$c_installed" "$c_entries" "copy->symlink manifest accounts for every installed path"

# --- symlink -> copy: the other direction ---
H="$WORK/s2c"; mkdir -p "$H"
install "$H" symlink
assert_eq "$TOTAL" "$(count_kind "$H/.claude" link)" "symlink install produces symlinks"
install "$H" copy
assert_eq "$TOTAL" "$(count_kind "$H/.claude" dir)" "re-installing with --copy replaces every symlink with a directory"
assert_eq "0" "$(count_kind "$H/.claude" link)" "no symlink survives the transition"

# --- the manifest keeps tracking what is installed ---
M="$H/.ensemble/install-manifest-claude.txt"
assert_file_exists "$M" "the manifest exists after a re-install"
entries=$(grep -c . "$M" 2>/dev/null || echo 0)
[ "$entries" -gt 0 ] && pass "the manifest is non-empty ($entries entries), so a later run can sweep" \
                     || fail "the manifest is non-empty" "empty manifest orphans every installed path"

installed=$(( $(ls -1 "$H/.claude/skills" | grep -c '^en-') + $(ls -1 "$H/.claude/agents" | grep -c '\.md$') ))
assert_eq "$installed" "$entries" "the manifest accounts for every installed path"

# --- a foreign entry is still left alone ---
H="$WORK/foreign"; mkdir -p "$H/.claude/skills/en-plan"
echo "someone else's file" > "$H/.claude/skills/en-plan/SKILL.md"
install "$H" symlink
[ -L "$H/.claude/skills/en-plan" ] \
  && fail "a pre-existing non-Ensemble directory must not be claimed" \
  || pass "a pre-existing non-Ensemble directory is left alone"
assert_eq "someone else's file" "$(cat "$H/.claude/skills/en-plan/SKILL.md")" "its contents survive untouched"

# --- a manifest naming a path outside the install root is ignored ---
H="$WORK/escape"; mkdir -p "$H/.ensemble" "$H/.claude"
canary="$WORK/canary.txt"; echo "do not delete me" > "$canary"
printf '%s\n' "$canary" > "$H/.ensemble/install-manifest-claude.txt"
install "$H" symlink
assert_file_exists "$canary" "a manifest path outside the install root is ignored, not deleted"

report
