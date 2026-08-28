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
    git log "$DEFAULT" --grep="($u)" --grep="$u)" --oneline 2>/dev/null | grep -q . || unshipped=$((unshipped + 1))
  done

  if [ "$unshipped" -eq 0 ]; then
    drifted="$drifted $id"
  fi
done

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
