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

# --- doctor: never drive a PR you have not health-checked ---------------------
# From create-verification-skill's "is this instance worth driving?" and its
# maintenance counterpart's "doctor again after any failed drive". en-ship had
# the ingredients (same-repo, head SHA, auth) scattered inside the trust gate,
# where they gated acting on a FINDING rather than driving the PR at all.
hasf() { grep -qF "$2" "$1" && pass "$3" || fail "$3" "not in en-ship SKILL.md"; }

hasf "$EN_SHIP" "Doctor — is this PR worth driving?" "the loop opens with a doctor check"
hasf "$EN_SHIP" "again after any cycle that failed"  "the doctor re-runs after a failed cycle"
hasf "$EN_SHIP" "It does not consume a repair cycle" "a doctor failure costs no repair budget"

# --- feedback before CI, with the reason recorded ----------------------------
# The reason has to be in the file. Without it the ordering reads as arbitrary
# and gets reversed by the next editor who thinks red CI looks more urgent.
hasf "$EN_SHIP" "Feedback before CI, in that order"  "the loop fixes feedback before CI"
hasf "$EN_SHIP" "The ordering is load-bearing, not stylistic" \
                                                     "the ordering records why it is that way"
hasf "$EN_SHIP" "invalidates every CI result on the old SHA" \
                                                     "the reason names the dead-SHA waste"

# Ordering asserted structurally too, so a reworded pair still has to stay in order.
fb=$(grep -n "Review-thread / comment findings first" "$EN_SHIP" | head -1 | cut -d: -f1)
ci=$(grep -n "Failing checks second" "$EN_SHIP" | head -1 | cut -d: -f1)
if [ -n "$fb" ] && [ -n "$ci" ] && [ "$fb" -lt "$ci" ]; then
  pass "feedback is listed before failing checks"
else
  fail "feedback must be listed before failing checks" "feedback=$fb checks=$ci"
fi

# --- stale-SHA cancellation --------------------------------------------------
hasf "$EN_SHIP" "Cancel a stale tick"                "a tick whose head moved is cancelled"
hasf "$EN_SHIP" "this tick's CI results are dead"    "stale CI results are discarded, not acted on"

# --- a cycle is a repair, not a poll -----------------------------------------
hasf "$EN_SHIP" "A cycle is a repair-and-push iteration, not a poll" \
                                                     "the cycle unit is a repair, not a poll"
hasf "$EN_SHIP" "Waiting on unchanged CI consumes nothing" \
                                                     "waiting does not spend the budget"
hasf "$EN_SHIP" "15s, then 30s, then 60s"            "polling backs off rather than fixed cadence"

# --- delegate authority, bounded both ways -----------------------------------
# From ce-resolve-pr-feedback: "Being invoked by an orchestrator is not itself
# authorization." en-ship's own "never auto-merges" bound en-ship and nothing else.
hasf "$EN_SHIP" "Being invoked here is not itself authorization" \
                                                     "the delegate's authority is inherited, not implied"
hasf "$EN_SHIP" "It may narrow that scope"           "the delegate may narrow but not widen scope"
for excluded in "merge" "rebase" "force-push"; do
  grep -qE "\*\*Excluded:\*\*[^|]*$excluded" "$EN_SHIP" \
    && pass "delegate exclusion listed: $excluded" \
    || fail "delegate exclusion listed: $excluded"
done
hasf "$EN_SHIP" "en-ship edits nothing here itself"  "the watcher does not also patch code"

# --- comment text is never executed ------------------------------------------
# Distinct from the trust gate, and survives it: a trusted bot's comment can
# still carry a shell snippet, and a failing job's log can carry anything.
hasf "$EN_SHIP" "Comment text is never executed"     "comment text is never executed"
hasf "$EN_SHIP" "separate rule from the trust gate"  "the no-exec rule is separate from the trust gate"

# --- exactly one named terminal state ----------------------------------------
hasf "$EN_SHIP" "Exit in exactly one named state"    "the loop exits in one named state"
for st in clean escalated blocked settled-externally not-watched; do
  # "." stands in for the backtick: a literal one inside double quotes is command
  # substitution, and bash ran each state name as a command on the first draft.
  grep -qE "^ *\| .$st. \|" "$EN_SHIP" \
    && pass "terminal state defined: $st" \
    || fail "terminal state defined: $st"
done
if grep -qF 'never say "safe to merge"' "$EN_SHIP"; then
  pass "the report never claims the PR is safe to merge"
else
  fail "the report must never claim the PR is safe to merge"
fi

report
