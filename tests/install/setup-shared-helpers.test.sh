#!/usr/bin/env bash
# tests/install/setup-shared-helpers.test.sh
#
# This file used to guard the installer bridge: setup shipped skills and agents
# but not references/ or bin/, so a copy-mode install resolved $ENSEMBLE_ROOT to
# a directory holding neither and every skill failed its own probe at step 1.
#
# EN12 removed the bridge, because a self-contained skill has nothing to install
# separately. The test is repointed rather than deleted: the bug class is the
# same one, and the property that prevents it is now stronger. Instead of
# "setup remembered to carry the second half", it is "there is no second half".
#
# What is asserted now: an installed skill directory is self-sufficient. Nothing
# beside it, above it, or in a sibling is required for it to resolve what it
# names.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="installed skills are self-sufficient"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# Assets a skill names must live inside it. `references/X` is the old preamble
# placeholder and no longer appears anywhere; if it returns, U8's guard fails.
assets_resolve() {
  local dir="$1" label="$2" missing=""
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    [ -e "$dir/$ref" ] || missing="$missing $ref"
  done < <(grep -rhoE '`(references|templates|agents)/[A-Za-z0-9._/-]+`' "$dir" 2>/dev/null \
             | tr -d '`' | sort -u)
  assert_eq "" "$(echo $missing)" "$label"
}

for mode in copy symlink; do
  HOME_DIR="$WORK/$mode"; mkdir -p "$HOME_DIR"
  ( cd "$REPO_ROOT" && HOME="$HOME_DIR" ./setup --host claude --$mode --quiet ) >/dev/null 2>&1
  assert_exit_code 0 $? "[$mode] setup succeeds"

  root="$HOME_DIR/.claude"
  # The bridge is gone: nothing but skills/ and agents/ should be installed.
  assert_file_missing "$root/references" "[$mode] no references/ installed beside the skills"
  assert_file_missing "$root/bin"        "[$mode] no bin/ installed beside the skills"

  broken=""
  for d in "$root"/skills/*/; do
    [ -d "$d" ] || continue
    s=$(basename "$d")
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      [ -e "$d$ref" ] || broken="$broken $s/$ref"
    done < <(grep -rhoE '`(references|templates|agents)/[A-Za-z0-9._/-]+`' "$d" 2>/dev/null \
               | tr -d '`' | sort -u)
  done
  assert_eq "" "$(echo $broken)" "[$mode] every installed skill resolves everything it names"

  assert_eq "4" "$(ls "$root/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')" \
    "[$mode] the 4 remaining agents are published for dispatch (7 reviewers cut in EN13 U11)"
done

# --- the property the whole plan exists to produce ---
# One skill, moved somewhere with no repo, no shared/, no siblings, no install.
LONE="$WORK/somewhere-else"
mkdir -p "$LONE"
cp -R "$WORK/copy/.claude/skills/en-qa" "$LONE/en-qa"
assets_resolve "$LONE/en-qa" "a single skill directory, moved away from everything, still resolves"

escapes=$(grep -rl 'ENSEMBLE_ROOT' "$LONE/en-qa" 2>/dev/null || true)
assert_eq "" "$escapes" "the moved skill resolves nothing through an install root"

# The source checkout is no longer a runtime dependency: a copy-mode install
# keeps working when the checkout it came from is unreachable.
assert_file_exists "$WORK/copy/.claude/skills/en-qa/references/qa-flows.md" \
  "a copied install owns its references outright, not by reference to the checkout"

report
