#!/usr/bin/env bash
# tests/lint/decision-log-order.test.sh
#
# Decision numbers in docs/foundation.md must ascend down the file.
#
# D57 through D61 were written in DESCENDING order. Five consecutive passes each
# anchored on the previous decision and inserted before it, so the log read
# D56, D61, D60, D59, D58, D57. Nothing noticed, because nothing looked: the log
# is prose, and prose ordering is exactly what a reader assumes rather than
# checks.
#
# A decision log that runs backwards is worse than untidy. Its whole value is
# that a later entry can amend an earlier one — D46 amends D35, D52 supersedes
# it — and "later" is unreadable when the file disagrees with the numbering.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="decision log order"
cd "$REPO_ROOT"

F=docs/foundation.md
assert_file_exists "$F" "the foundation exists"

nums=$(grep -oE '^- \*\*D[0-9]+\.' "$F" | grep -oE '[0-9]+')
count=$(printf '%s\n' "$nums" | grep -c . || true)
[ "$count" -gt 0 ] \
  && pass "the decision log has entries ($count)" \
  || fail "the decision log has entries" "no '- **D<N>.' lines matched — has the format changed?"

prev=0; out_of_order=""
while IFS= read -r n; do
  [ -n "$n" ] || continue
  [ "$n" -le "$prev" ] && out_of_order="$out_of_order D$n-after-D$prev"
  prev="$n"
done <<< "$nums"

[ -z "$out_of_order" ] \
  && pass "decision numbers ascend down the file" \
  || fail "decision numbers ascend down the file" "$(echo $out_of_order)"

# Duplicates are the other way this breaks: two passes both claiming the next
# number, which the ascend check above catches only because equal fails too.
dupes=$(printf '%s\n' "$nums" | sort -n | uniq -d | tr '\n' ' ')
[ -z "$dupes" ] \
  && pass "no decision number is used twice" \
  || fail "no decision number is used twice" "$dupes"

# --- contiguity, minus declared gaps ----------------------------------------
# The two checks above pass on a sequence with a hole: ascending allows it and
# uniqueness has nothing to say. D36 sat missing for months that way, never
# written rather than retired — absent from every version of this file in git
# history and cited nowhere.
#
# A gap is not filled, it is declared. Renumbering to close one would invalidate
# every citation in the repo, the amendment chains included, so a "Never issued"
# entry is the cheap half of that trade. Declaring it here means a NEW accidental
# gap still fails.
declared=$(grep -oE '^- \*\*D[0-9]+\. Never issued\.' "$F" | grep -oE '[0-9]+' | sort -n | tr '\n' ' ')
lo=$(printf '%s\n' "$nums" | sort -n | head -1)
hi=$(printf '%s\n' "$nums" | sort -n | tail -1)

holes=""
i="$lo"
while [ "$i" -le "$hi" ]; do
  if ! printf '%s\n' "$nums" | grep -qx "$i"; then
    case " $declared " in *" $i "*) ;; *) holes="$holes D$i" ;; esac
  fi
  i=$((i + 1))
done
[ -z "$holes" ] \
  && pass "the decision sequence D$lo..D$hi is contiguous (declared gaps:${declared:+ $declared})" \
  || fail "a decision number is missing and not declared" "$(echo $holes) — add a 'Never issued.' entry or use the number"

# Nothing may cite a number declared never-issued. A citation means either the
# declaration is wrong or the citation is.
#
# The first version of this looped over entries selected BY the phrase "Never
# issued" and then asserted they contained it, so it could not fail. Reusing the
# number is caught anyway: dropping the phrase removes it from `declared`, and
# if no real entry took its place the contiguity check above goes red.
for d in $declared; do
  hits=$(grep -rlE "\bD$d\b" skills/ tests/ 2>/dev/null \
         | grep -vF 'decision-log-order.test.sh' | tr '\n' ' ')
  [ -z "$hits" ] \
    && pass "nothing cites D$d, which is declared never-issued" \
    || fail "D$d is declared never-issued but is cited" "$hits"
done

# --- every cited D<N> resolves ----------------------------------------------
# The log's value is that a later entry amends an earlier one, and a citation
# naming a number nothing defines breaks that silently: the reader looks it up,
# finds nothing, and cannot tell whether the decision was renumbered, retired,
# or never existed.
dangling=""
for c in $(grep -rhoE '\bD[0-9]+\b' skills/ docs/ tests/ 2>/dev/null \
           | grep -oE '[0-9]+' | sort -un); do
  printf '%s\n' "$nums" | grep -qx "$c" || dangling="$dangling D$c"
done
[ -z "$dangling" ] \
  && pass "every D<N> cited in skills/, docs/ or tests/ names a real decision" \
  || fail "these citations name no decision" "$(echo $dangling)"

# --- a number this branch adds must not already exist on main ---------------
# Two branches anchoring on the same last decision both claim the next number.
# It happened on 2026-09-03: PRs #74 and #75 each wrote D65 and D66 while
# neither could see the other, and it surfaced as a merge conflict resolved by
# hand rather than as a check. On a merge that auto-resolves, it would not
# surface at all — it would land as a duplicate.
#
# Skipped, loudly, when there is nothing to compare against: on main itself, or
# in a checkout with no origin/main (a shallow CI clone would silently pass this
# otherwise, which is the failure mode PR #63 already paid for once).
if ! git rev-parse --verify -q origin/main >/dev/null 2>&1; then
  pass "SKIPPED — no origin/main in this checkout; branch-vs-main numbering unchecked"
elif [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
  pass "SKIPPED — HEAD is origin/main; nothing to compare"
else
  base=$(git merge-base HEAD origin/main 2>/dev/null || true)
  if [ -z "$base" ]; then
    pass "SKIPPED — no merge base with origin/main"
  else
    on_main=$(git show origin/main:"$F" 2>/dev/null \
              | grep -oE '^- \*\*D[0-9]+\.' | grep -oE '[0-9]+' | sort -un)
    at_base=$(git show "$base":"$F" 2>/dev/null \
              | grep -oE '^- \*\*D[0-9]+\.' | grep -oE '[0-9]+' | sort -un)

    taken=""
    for n in $nums; do
      # Added on this branch: present now, absent at the fork point.
      printf '%s\n' "$at_base" | grep -qx "$n" && continue
      printf '%s\n' "$on_main" | grep -qx "$n" && taken="$taken D$n"
    done
    [ -z "$taken" ] \
      && pass "no decision number this branch adds is already taken on main" \
      || fail "these numbers are already used on main; renumber before merging" "$(echo $taken)"
  fi
fi

report
