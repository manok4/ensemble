#!/usr/bin/env bash
# tests/install/unmigrated-skill-resolution.test.sh
#
# EN12 U2, from peer finding 1-1. Moving references/ and bin/ under shared/
# deletes the exact paths every unmigrated skill reads: each one resolves
# $ENSEMBLE_ROOT as realpath(<skill dir>/../..) and then reads
# $ENSEMBLE_ROOT/references/X and $ENSEMBLE_ROOT/bin/Y. The installer bridge
# does not save this — it copies $SOURCE_DIR/references, which after the move
# would not exist either.
#
# U2 therefore leaves repo-root `references` and `bin` as symlinks into shared/.
# They exist only for the U3-to-U8 window and U9 removes them. This test is what
# makes "the intermediate state is green" a checked fact rather than a claim, so
# it must keep passing until U8 migrates the last skill.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="unmigrated skills still resolve their helpers"

# A skill is unmigrated while it still names $ENSEMBLE_ROOT.
unmigrated=""
for d in "$REPO_ROOT"/skills/*/; do
  s="$d/SKILL.md"; [ -f "$s" ] || continue
  grep -qF 'ENSEMBLE_ROOT' "$s" && unmigrated="$unmigrated $(basename "$d")"
done

if [ -z "$unmigrated" ]; then
  pass "every skill has migrated — the root shims are dead and U9 should remove them"
  report
fi

# --- layout 1: a source checkout, which is what a symlink install resolves to ---
for probe in references/host-detect.md bin/ensemble-lint; do
  assert_file_exists "$REPO_ROOT/$probe" "source checkout: \$ENSEMBLE_ROOT/$probe resolves"
done

# The shims must be symlinks into shared/, not copies that could drift.
for shim in references bin; do
  if [ -L "$REPO_ROOT/$shim" ]; then
    target="$(readlink "$REPO_ROOT/$shim")"
    assert_eq "shared/$shim" "$target" "root $shim is a symlink into shared/, not a copy"
  else
    fail "root $shim is a symlink" "expected a symlink into shared/, found a real path"
  fi
done

# --- layout 2: a copied install, where $ENSEMBLE_ROOT is the install target ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
( cd "$REPO_ROOT" && HOME="$WORK" ./setup --host claude --copy --quiet ) >/dev/null 2>&1
rc=$?
assert_exit_code 0 "$rc" "copy-mode install succeeds after the move"

first="$(echo "$unmigrated" | awk '{print $1}')"
skill_md="$WORK/.claude/skills/$first/SKILL.md"
if [ -f "$skill_md" ]; then
  root="$(cd -P "$(dirname "$skill_md")" && cd ../.. && pwd -P)"
  for probe in references/host-detect.md bin/ensemble-lint; do
    assert_file_exists "$root/$probe" "copied install: \$ENSEMBLE_ROOT/$probe resolves for $first"
  done
else
  fail "copy-mode install placed $first" "$skill_md missing"
fi

# Every unmigrated skill, not just the first: the preamble is identical in all.
missing=""
for skill in $unmigrated; do
  s="$WORK/.claude/skills/$skill/SKILL.md"
  [ -f "$s" ] || { missing="$missing $skill(absent)"; continue; }
  r="$(cd -P "$(dirname "$s")" && cd ../.. && pwd -P)"
  [ -f "$r/references/host-detect.md" ] || missing="$missing $skill"
done
assert_eq "" "$missing" "every unmigrated skill resolves its helpers in a copied install"

report
