#!/usr/bin/env bash
# tests/parity/script-parity.test.sh
#
# Every skill carries its own copy of the scripts it runs (EN12/EN13). A copy
# that drifts is the D44 hazard in a new coat: one fix lands in the carrier
# someone was looking at and the others keep the bug. Individual guards already
# pinned ensemble-peer-invoke; nothing pinned the rest. On 2026-09-04 this guard
# found /en-setup still installing the pre-D65 ensemble-sweep-activity-check
# (the chore(docs) collision D65 removed from /en-sweep's copy, which is the
# copy that runs in every consuming repo's CI) and a comment drift in
# ensemble-plan-hash (D84).
#
# Exceptions are deliberate per-skill variants, listed with the reason. A name
# on the list must still have more than one copy, or the row is stale.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="script parity across carriers"
cd "$REPO_ROOT"

# name  reason
EXCEPTIONS='
ensemble-build-peer-prompt  three per-artifact variants: plan (u_id field), code, foundation (dimension fallback)
'

is_exception() { printf '%s\n' "$EXCEPTIONS" | grep -qE "^$1 "; }

names=$(ls skills/*/scripts/* 2>/dev/null | xargs -n1 basename | sort | uniq -d)
[ -n "$names" ] && pass "there are scripts carried by more than one skill" || fail "there are scripts carried by more than one skill"

for n in $names; do
  copies=$(ls skills/*/scripts/"$n")
  distinct=$(for f in $copies; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
  if is_exception "$n"; then
    [ "$distinct" -gt 1 ] && pass "$n: deliberate variants ($distinct), listed with a reason" \
                          || fail "$n: listed as an exception but its copies are identical" "delete the row"
  elif [ "$distinct" -eq 1 ]; then
    pass "$n: byte-identical across $(echo "$copies" | wc -l | tr -d ' ') carriers"
  else
    fail "$n: copies differ across carriers" "$(echo "$copies" | tr '\n' ' ') — sync them, or list the name with a reason"
  fi
done

# Every exception names a script that still exists in more than one skill.
printf '%s\n' "$EXCEPTIONS" | grep -E '^[a-z]' | while read -r n _; do
  c=$(ls skills/*/scripts/"$n" 2>/dev/null | wc -l | tr -d ' ')
  [ "$c" -gt 1 ] && pass "exception $n still has $c copies" || fail "exception $n is stale" "$c copies"
done

report
