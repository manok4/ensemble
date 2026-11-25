#!/usr/bin/env bash
# tests/strategy/consumers-agree.test.sh
#
# ensemble-lint is copied into a repo's bin/ and cannot call a skill script, so
# it embeds its own copy of the Strategy-section recognition. This runs both
# over every reader fixture: the section is present in one exactly when it is
# in the other, and the lint's declared IDs equal the reader's --ids.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="strategy consumers agree"

READER="$REPO_ROOT/skills/en-foundation/scripts/ensemble-strategy-section"
LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# The lint's view, read through its own findings: cite ST1..ST9 from a plan and
# see which it reports. Undeclared at P1 means present; at P3, absent; none
# reported means declared.
lint_view() {  # $1 = fixture; prints state then the declared IDs
  rm -rf "$WORK/r"; mkdir -p "$WORK/r/docs/plans/active"
  cp "$1" "$WORK/r/docs/foundation.md"
  printf -- '---\ntype: plan\nplan_type: feature\ntitle: x\nstatus: open\nlocation: active\ncreated: 2026-04-29\ncovers_requirements: []\nrequirements_pending: true\n---\n\n# FR50\n\nST1 ST2 ST3 ST4 ST5 ST6 ST7 ST8 ST9\n' \
    > "$WORK/r/docs/plans/active/FR50-feature_x.md"
  local out; out=$(cd "$WORK/r" && "$LINT" --scope docs/plans/active 2>&1)
  if printf '%s\n' "$out" | grep -q '\[P1\] cross-link.broken-st'; then echo present
  else echo absent; fi
  for n in 1 2 3 4 5 6 7 8 9; do
    printf '%s\n' "$out" | grep -q "cross-link.broken-st .*Citation of ST$n " || echo "ST$n"
  done
}

reader_view() {  # $1 = fixture
  local sec; sec=$("$READER" "$1" 2>/dev/null)
  [ -n "$sec" ] && echo present || echo absent
  "$READER" --ids "$1" 2>/dev/null
}

n=0
for fx in "$SELF_DIR"/fixtures/*.md; do
  n=$((n + 1))
  name=$(basename "$fx")
  assert_eq "$(reader_view "$fx")" "$(lint_view "$fx")" "lint and reader agree on $name"
done
[ "$n" -ge 6 ] && pass "ran over $n fixtures" || fail "expected at least 6 fixtures, found $n"

report
