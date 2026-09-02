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

# --- review findings fetched comprehensively (inline threads), not just --json comments ---
if grep -qF "get-pr-comments" "$EN_SHIP" && grep -qiE "inline review threads?" "$EN_SHIP"; then
  pass "loop fetches inline review threads via get-pr-comments (not --json comments alone)"
else
  fail "loop must fetch inline review threads (get-pr-comments), not just gh pr view --json comments"
fi

# --- failing-check logs get a real repair path (not just review comments) ---
if grep -qF "gh run view --log-failed" "$EN_SHIP" && grep -qiE "Failing checks" "$EN_SHIP"; then
  pass "failing checks route their logs into the fix path (not comment-only)"
else
  fail "loop must feed failing-check logs into the fix path"
fi

# --- trusted-source gate before auto-fixing (prompt-injection guard) ---
if grep -qiE "[Tt]rusted-source gate" "$EN_SHIP" && grep -qiE "untrusted|prompt-injection" "$EN_SHIP" && grep -qiE "same-repo|fork" "$EN_SHIP"; then
  pass "loop gates on trusted author + same-repo before auto-fixing"
else
  fail "loop must gate on trusted source (author/bot, same-repo) before auto-fixing"
fi

# --- bounded by repair cycles, default 2, agreeing with en-flow ---
# The key was `watch.max_cycles` default 3 while /en-flow documented 2, and it appeared in no config
# example, so neither number was checkable by a reader. It also counted polls: against a 16-minute CI
# job three polls can expire before the job finishes, escalating a PR that was never in trouble.
if grep -qF "ship.watch_max_cycles" "$EN_SHIP" && grep -qE "default \`?2\`?" "$EN_SHIP" && grep -qiE "needs-human" "$EN_SHIP"; then
  pass "loop bounded by ship.watch_max_cycles (default 2) then escalates needs-human"
else
  fail "loop must be bounded by ship.watch_max_cycles (default 2) then escalate needs-human"
fi

# The cap and /en-flow's description of it must not drift apart again.
if grep -qE 'capped at 2 cycles' "$REPO_ROOT/skills/en-flow/SKILL.md"; then
  pass "en-flow's stated cap agrees with en-ship's default"
else
  fail "en-flow's stated cap must agree with en-ship's default"
fi

# --- CI is read-only (no CI-side writer) ---
if grep -qiE "CI.?s role is (to )?run tests|CI's role is read-only|keeps write access and secrets off CI" "$EN_SHIP"; then
  pass "en-ship documents CI as read-only (fixing is local)"
else
  fail "en-ship must state CI is read-only"
fi

# --- --auto-merge armed ONLY once the loop is clean ---
if grep -qF -- "--auto-merge" "$EN_SHIP" && grep -qF "gh pr merge --auto --squash" "$EN_SHIP" \
   && grep -qiE "only after the watch loop reaches a clean state|arm it only after" "$EN_SHIP"; then
  pass "--auto-merge arms native auto-merge only after the loop is clean"
else
  fail "--auto-merge must be armed only after the loop reaches a clean state"
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
