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

report
