#!/usr/bin/env bash
# Drift guards for en-ship watch loop + en-resolve-pr pagination (FR01 U8).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-ship watch loop"

EN_SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
GETPR="$REPO_ROOT/skills/en-resolve-pr/scripts/get-pr-comments"

# --- watch loop documented, default on ---
if grep -qiE "Watch loop \(default ON\)" "$EN_SHIP"; then
  pass "en-ship has a default-on watch loop"
else
  fail "en-ship must have a default-on watch loop"
fi

# --- invokes en-resolve-pr ---
if grep -qF "/en-resolve-pr" "$EN_SHIP"; then
  pass "watch loop invokes /en-resolve-pr"
else
  fail "watch loop must invoke /en-resolve-pr"
fi

# --- bounded to 2 cycles + escalate ---
if grep -qiE "2 cycles|2nd resolve cycle|two cycles" "$EN_SHIP" && grep -qiE "escalate|needs-human" "$EN_SHIP"; then
  pass "watch loop bounded to 2 cycles then escalates"
else
  fail "watch loop must be bounded to 2 cycles then escalate"
fi

# --- never auto-merges in the watch loop ---
if grep -qiE "[Nn]ever auto-merge|never runs .gh pr merge.|No auto-merge" "$EN_SHIP"; then
  pass "watch loop never auto-merges"
else
  fail "watch loop must never auto-merge"
fi

# --- --no-watch flag ---
if grep -qF -- "--no-watch" "$EN_SHIP"; then
  pass "--no-watch flag documented"
else
  fail "--no-watch flag missing"
fi

# --- get-pr-comments paginates all three connections ---
if grep -qF -- "--paginate" "$GETPR"; then
  pass "get-pr-comments uses --paginate"
else
  fail "get-pr-comments must use --paginate"
fi
pageinfo_count=$(grep -c "pageInfo" "$GETPR")
if [ "$pageinfo_count" -ge 3 ]; then
  pass "get-pr-comments paginates all three connections (pageInfo x$pageinfo_count)"
else
  fail "get-pr-comments must paginate reviewThreads + comments + reviews (found $pageinfo_count pageInfo)"
fi

# --- correct gh --paginate contract: each connection uses after:$endCursor + pageInfo{hasNextPage endCursor} ---
after_count=$(grep -c 'after:\$endCursor\|after: \$endCursor' "$GETPR")
if [ "$after_count" -ge 3 ]; then
  pass "each connection wires after:\$endCursor (gh --paginate contract)"
else
  fail "each connection must use after:\$endCursor for gh --paginate (found $after_count)"
fi
hasnext_count=$(grep -c "hasNextPage endCursor\|hasNextPage" "$GETPR")
if [ "$hasnext_count" -ge 3 ]; then
  pass "each connection exposes pageInfo{hasNextPage endCursor}"
else
  fail "each connection must expose pageInfo{hasNextPage endCursor} (found $hasnext_count)"
fi

# --- merge logic: jq -s combines multiple pages into one array (FR01 review finding 1) ---
PAGE1='{"data":{"repository":{"pullRequest":{"reviewThreads":{"edges":[{"node":{"id":"t1"}}]}}}}}'
PAGE2='{"data":{"repository":{"pullRequest":{"reviewThreads":{"edges":[{"node":{"id":"t2"}}]}}}}}'
merged=$(printf '%s\n%s\n' "$PAGE1" "$PAGE2" | jq -s 'map(.data.repository.pullRequest.reviewThreads.edges) | add // []')
n=$(echo "$merged" | jq 'length')
assert_eq "2" "$n" "jq -s merges multiple pages (page1 + page2 edges combined)"

# --- syntax valid ---
if bash -n "$GETPR" 2>/dev/null; then
  pass "get-pr-comments is syntactically valid"
else
  fail "get-pr-comments has a syntax error"
fi

report
