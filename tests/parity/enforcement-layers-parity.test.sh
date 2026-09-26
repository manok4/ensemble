#!/usr/bin/env bash
# tests/parity/enforcement-layers-parity.test.sh
#
# EN22 U1. references/enforcement-layers.md is the rubric the correction router
# classifies against. /en-learn (capture, --enforce-audit) and /en-sweep (the
# recurrence scan) must pick the same layer for the same correction, or the
# tracker fills with entries two skills disagree about.
#
# The carriers are pinned, not discovered. A discovered list lets a skill delete
# its copy and drop off the list while every remaining copy still agrees, which
# is the silent failure this guard exists for. Adding a third carrier is a
# deliberate act that edits this list.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="enforcement layers parity"

RUBRIC="references/enforcement-layers.md"
PINNED="en-learn en-sweep"

# --- every pinned carrier holds a copy ---
missing=""
for s in $PINNED; do
  [ -f "$REPO_ROOT/skills/$s/$RUBRIC" ] || missing="$missing $s"
done
assert_eq "" "$(echo $missing)" "every pinned carrier holds the rubric"

# --- no unpinned skill carries one ---
extra=""
for d in "$REPO_ROOT"/skills/*/; do
  s="$(basename "${d%/}")"
  [ -f "$d$RUBRIC" ] || continue
  case " $PINNED " in *" $s "*) ;; *) extra="$extra $s" ;; esac
done
assert_eq "" "$(echo $extra)" "no skill outside the pinned list carries the rubric"

# --- every copy byte-identical to the first pinned carrier ---
first="${PINNED%% *}"
drifted=""
for s in $PINNED; do
  [ -f "$REPO_ROOT/skills/$s/$RUBRIC" ] || continue
  cmp -s "$REPO_ROOT/skills/$first/$RUBRIC" "$REPO_ROOT/skills/$s/$RUBRIC" || drifted="$drifted $s"
done
assert_eq "" "$(echo $drifted)" "every copy of the rubric is byte-identical"

report
