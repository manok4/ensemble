#!/usr/bin/env bash
# Drift guards for en-ship's LOCAL watch-and-fix loop (EN04 D38) + en-resolve-pr pagination (FR01 U8).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-ship watch loop"

EN_SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
GETPR="$REPO_ROOT/skills/en-resolve-pr/scripts/get-pr-comments"

# --- default is a LOCAL watch-and-fix loop ---
if grep -qiE "Local watch-and-fix loop \(default ON\)" "$EN_SHIP"; then
  pass "en-ship default is a local watch-and-fix loop"
else
  fail "en-ship must default to a local watch-and-fix loop"
fi

# --- fixing is LOCAL, not in CI ---
if grep -qiE "fix.*locally|on this machine, not in CI|the fixing happens on this machine" "$EN_SHIP"; then
  pass "en-ship fixes findings locally (not in CI)"
else
  fail "en-ship must fix findings locally, not in CI"
fi

# --- the CI-hosted fix engine is GONE (no en-ship-watch workflow/label) ---
if grep -qF "en-ship-watch" "$EN_SHIP"; then
  fail "en-ship must NOT reference the removed CI-hosted en-ship-watch engine"
else
  pass "en-ship no longer references a CI-hosted self-heal engine"
fi

# --- invokes en-resolve-pr to fix locally ---
if grep -qF "/en-resolve-pr" "$EN_SHIP"; then
  pass "local loop invokes /en-resolve-pr"
else
  fail "local loop must invoke /en-resolve-pr"
fi

# --- loops until clean, bounded, then escalate needs-human ---
if grep -qiE "Loop until clean|loop until|until all checks are green" "$EN_SHIP" && grep -qiE "escalat|needs-human" "$EN_SHIP"; then
  pass "local loop repeats until clean, bounded, then escalates"
else
  fail "local loop must repeat until clean (bounded) then escalate"
fi

# --- default never auto-merges (stop at mergeable PR) ---
if grep -qiE "never auto-merg|Default OFF" "$EN_SHIP"; then
  pass "default stops at a mergeable PR (no auto-merge)"
else
  fail "default must not auto-merge"
fi

# --- --auto-merge arms native gh auto-merge ---
if grep -qF -- "--auto-merge" "$EN_SHIP" && grep -qF "gh pr merge --auto --squash" "$EN_SHIP"; then
  pass "--auto-merge arms gh pr merge --auto --squash"
else
  fail "--auto-merge must arm gh pr merge --auto --squash"
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
