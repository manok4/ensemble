#!/usr/bin/env bash
# tests/lint/plan-lifecycle-drift.test.sh
#
# A plan whose units have all landed on the default branch belongs in
# docs/plans/completed/. Two mechanisms were supposed to enforce that and neither
# fired: /en-learn's lifecycle flip only runs when a capture runs, and en-sweep's
# check D ("catches the case where the user shipped without invoking /en-learn")
# has no runner in this repo — .github/workflows/en-sweep.yml was never installed
# here, along with the three bin scripts en-setup's own verification table
# requires.
#
# Three plans accumulated in active/ before anyone noticed. This runs in the CI
# that DOES exist, so the detection no longer depends on machinery that was never
# switched on.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="plan lifecycle drift"

cd "$REPO_ROOT" || exit 1
ACTIVE="docs/plans/active"

# Resolve the default branch once; fall back to main when there is no remote.
DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|^origin/||')
[ -n "$DEFAULT" ] || DEFAULT=main
git rev-parse --verify --quiet "$DEFAULT" >/dev/null 2>&1 || DEFAULT=HEAD

# A unit counts as shipped only when ONE commit carries both the plan id and the
# U-ID. Matching the U-ID alone is what this check did until 2026-09-02, and every
# plan starts at U1: EN13 and EN14 had already put `(U1)`, `(U3)` and `(U8)` on the
# default branch, so a brand-new plan read as fully shipped the moment it was
# written. `--all-match` turns git's OR of multiple --grep into an AND.
#
# The bug survived because docs/plans/active/ was EMPTY on the default branch, so
# the loop never ran and the check passed vacuously from the day it was written.
# The self-test below is the fix for that: it proves the matcher can still fire.
unit_shipped() {  # $1=plan id  $2=U-ID
  git log "$DEFAULT" --all-match --grep="$1" --grep="($2)" --oneline 2>/dev/null | grep -q .
}

drifted=""
checked=0
for p in "$ACTIVE"/*.md; do
  [ -f "$p" ] || continue
  checked=$((checked + 1))
  id=$(grep -m1 '^plan_id:' "$p" | cut -d: -f2- | tr -d ' ')
  status=$(grep -m1 '^status:' "$p" | cut -d: -f2- | tr -d ' ')
  [ -n "$id" ] || continue

  # A draft or abandoned plan is not expected to have shipped.
  case "$status" in draft|abandoned) continue ;; esac

  # Every U-ID the plan declares, and whether each appears in a commit subject
  # or body on the default branch.
  units=$(grep -oE '^### (U[0-9]+)\.' "$p" | grep -oE 'U[0-9]+' | sort -u)
  [ -n "$units" ] || continue

  unshipped=0
  for u in $units; do
    unit_shipped "$id" "$u" || unshipped=$((unshipped + 1))
  done

  if [ "$unshipped" -eq 0 ]; then
    drifted="$drifted $id"
  fi
done

# --- the matcher must be able to fire -----------------------------------------
# A matcher that never matches makes the loop above pass for any input, which is
# indistinguishable from "nothing has drifted". Probe it against a plan known to
# have shipped: EN14 is in completed/ and its units are on the default branch.
if unit_shipped "EN14" "U1"; then
  pass "the shipped-unit matcher fires on a known-shipped unit (EN14 U1)"
else
  fail "the shipped-unit matcher fires on a known-shipped unit (EN14 U1)" \
       "it matches nothing, so the drift loop below cannot detect anything"
fi

# And it must not fire across plans: EN14's U1 must not satisfy another plan's U1.
if unit_shipped "EN15" "U1"; then
  fail "the matcher is scoped to its own plan" \
       "EN15 U1 matched a commit; another plan's U-ID is satisfying it"
else
  pass "the matcher is scoped to its own plan"
fi

if [ -z "$drifted" ]; then
  pass "no plan in active/ has all its units already on $DEFAULT ($checked checked)"
else
  fail "a plan in active/ has all its units already on $DEFAULT" \
       "move to completed/ with status: completed and a shipped: date —$drifted"
fi

# The location/status pair must agree, in both directions. ensemble-lint already
# rejects status: completed inside active/; this covers the reverse.
mismatch=""
for p in docs/plans/completed/*.md; do
  [ -f "$p" ] || continue
  st=$(grep -m1 '^status:' "$p" | cut -d: -f2- | tr -d ' ')
  case "$st" in completed|abandoned) ;; *) mismatch="$mismatch $(basename "$p"):$st" ;; esac
done
if [ -z "$mismatch" ]; then
  pass "every plan in completed/ carries a terminal status"
else
  fail "every plan in completed/ carries a terminal status" "$mismatch"
fi

# A shipped plan without a date loses the only record of when it landed.
nodate=""
for p in docs/plans/completed/*.md; do
  [ -f "$p" ] || continue
  grep -qE '^shipped: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$p" || nodate="$nodate $(basename "$p")"
done
if [ -z "$nodate" ]; then
  pass "every completed plan records a shipped date"
else
  fail "every completed plan records a shipped date" "$nodate"
fi

report
