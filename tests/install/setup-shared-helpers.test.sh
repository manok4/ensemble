#!/usr/bin/env bash
# tests/install/setup-shared-helpers.test.sh
#
# Guards the invariant every skill's preamble depends on: after ./setup, the
# directory the skill computes as $ENSEMBLE_ROOT must contain references/ and
# bin/.
#
# Before this guard existed, setup installed only skills/ and agents/. In copy
# mode (the forced default on MinGW/MSYS/Cygwin) $ENSEMBLE_ROOT resolved to a
# directory with neither, so all 17 skills failed their own fail-loudly check at
# step 1. Symlink mode masked it, because realpath tunnels through the symlink
# back into the source checkout where both directories still exist.
#
# The preamble specifies `realpath "$(dirname <this-SKILL.md>)/../.."`, but not
# every resolver physicalizes before walking `..` — a plain `cd a/../..` does
# not. Both readings are asserted below, because the install should be
# self-sufficient under either.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
# shellcheck source=../lib/assert.sh
. "$SELF_DIR/../lib/assert.sh"
TEST_NAME="setup installs shared helpers where skills resolve them"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# `realpath <skill dir>/../..`: symlinks resolved before `..` is walked.
root_physical() {
  ( cd -P "$(dirname "$1")" 2>/dev/null && cd ../.. && pwd -P )
}

# `cd <skill dir>/../..`: `..` walked against the path as written.
root_logical() {
  ( cd "$(dirname "$1")/../.." 2>/dev/null && pwd -P )
}

run_setup() {
  local home="$1"; shift
  mkdir -p "$home"
  ( cd "$REPO_ROOT" && HOME="$home" ./setup --host claude --quiet "$@" ) >/dev/null 2>&1
}

assert_root_is_complete() {
  local root="$1" label="$2"
  assert_file_exists "$root/references/host-detect.md" "$label: references/host-detect.md resolves"
  assert_file_exists "$root/bin/ensemble-lint" "$label: bin/ensemble-lint resolves"
}

# --- copy mode: the mode that was broken -----------------------------------
COPY_HOME="$WORK/copy"
run_setup "$COPY_HOME" --copy
assert_exit_code 0 $? "copy-mode setup exits 0"

COPY_SKILL="$COPY_HOME/.claude/skills/en-plan/SKILL.md"
assert_file_exists "$COPY_SKILL" "copy mode installed en-plan"
assert_root_is_complete "$(root_physical "$COPY_SKILL")" "copy mode (realpath)"
assert_root_is_complete "$(root_logical  "$COPY_SKILL")" "copy mode (logical)"

# Every skill, not just en-plan: the preamble is byte-identical in all of them.
missing=""
for skill_md in "$COPY_HOME/.claude/skills"/*/SKILL.md; do
  [ -f "$(root_physical "$skill_md")/references/host-detect.md" ] \
    || missing="$missing $(basename "$(dirname "$skill_md")")"
done
assert_eq "" "$missing" "copy mode: every installed skill resolves its shared helpers"

# --- symlink mode -----------------------------------------------------------
# Under realpath this passed even before the fix (it lands on the source
# checkout), which is why the bug survived. The logical reading is the one that
# needs the installed copy, and it also stands in for the hidden cost of the
# realpath path: it makes the source checkout a permanent runtime dependency.
LINK_HOME="$WORK/link"
run_setup "$LINK_HOME" --symlink
assert_exit_code 0 $? "symlink-mode setup exits 0"

LINK_SKILL="$LINK_HOME/.claude/skills/en-plan/SKILL.md"
assert_eq "$REPO_ROOT" "$(root_physical "$LINK_SKILL")" \
  "symlink mode (realpath) lands on the source checkout, as documented"
assert_root_is_complete "$(root_logical "$LINK_SKILL")" "symlink mode (logical)"

# --- negative control -------------------------------------------------------
# A guard that cannot go red is decorative. Occupy the destination with a
# foreign directory: setup must refuse to claim it AND must not report success.
BLOCKED_HOME="$WORK/blocked"
mkdir -p "$BLOCKED_HOME/.claude/references"
echo "not ours" > "$BLOCKED_HOME/.claude/references/README.md"
run_setup "$BLOCKED_HOME" --copy
assert_ne 0 $? "setup exits non-zero when shared helpers cannot be installed"
assert_file_missing "$BLOCKED_HOME/.claude/references/host-detect.md" \
  "setup does not overwrite a foreign references/ directory"
assert_eq "not ours" "$(cat "$BLOCKED_HOME/.claude/references/README.md")" \
  "the foreign directory's contents survive untouched"

report
