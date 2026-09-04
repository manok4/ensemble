#!/usr/bin/env bash
# tests/parity/reference-parity.test.sh
#
# Every skill carries its own copies of the references it reads (EN12/EN13).
# Several shared references have their own parity guard; most did not, and on
# 2026-09-04 en-foundation's copy of the plan template was found two features
# and one decision behind en-plan's: a bootstrap plan written from it would lack
# the Test seams section and the per-unit Interfaces block en-build reads.
#
# The rule: a reference basename carried by more than one skill is byte-identical
# across its carriers, unless listed here with the reason its copies differ. A
# listed name must still have more than one copy, or its row is stale.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="reference parity across carriers"
cd "$REPO_ROOT"

EXCEPTIONS='
peer-brief.md  each peer skill asks its peer something different (plan, code, foundation); D50
'
is_exception() { printf '%s\n' "$EXCEPTIONS" | grep -qE "^$1 "; }

files() { ls skills/*/references/"$1" skills/*/references/templates/"$1" 2>/dev/null; }
names=$( (ls skills/*/references/*.md skills/*/references/templates/*.md 2>/dev/null) | xargs -n1 basename | sort | uniq -d)
[ -n "$names" ] && pass "there are references carried by more than one skill" || fail "there are references carried by more than one skill"

for n in $names; do
  copies=$(files "$n")
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

printf '%s\n' "$EXCEPTIONS" | grep -E '^[a-z]' | while read -r n _; do
  c=$(files "$n" | wc -l | tr -d ' ')
  [ "$c" -gt 1 ] && pass "exception $n still has $c copies" || fail "exception $n is stale" "$c copies"
done

report
