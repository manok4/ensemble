#!/usr/bin/env bash
# Drift + behavioral guards for the CI self-heal engine (EN04 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-ship-watch CI"

CI="$REPO_ROOT/bin/en-ship-watch-ci"
WF="$REPO_ROOT/references/templates/github-workflow-en-ship-watch.yml"

# --- syntax valid ---
if bash -n "$CI" 2>/dev/null; then
  pass "en-ship-watch-ci is syntactically valid"
else
  fail "en-ship-watch-ci has a syntax error"
fi

# Helpers that source the wrapper in a subshell (BASH_SOURCE guard prevents main)
# and invoke a single pure function, returning its status.
call() { ( . "$CI" >/dev/null 2>&1; "$@" ); }

# --- sourcing does NOT execute main (no side effects) ---
if out="$( . "$CI" 2>&1 )" && ! printf '%s' "$out" | grep -q "en-ship-watch:"; then
  pass "sourcing the wrapper does not run main (guarded)"
else
  fail "sourcing the wrapper must not execute main"
fi

# --- label gate ---
if call has_watch_label "$(printf 'other\nen-ship-watch\nfoo')"; then
  pass "has_watch_label detects the label when present"
else
  fail "has_watch_label must detect the label when present"
fi
if call has_watch_label "$(printf 'other\nfoo')"; then
  fail "has_watch_label must reject when the label is absent"
else
  pass "has_watch_label rejects when the label is absent (no-op path)"
fi

# --- attempt cap ---
if call under_attempt_cap 2 3; then
  pass "under_attempt_cap allows attempts below the cap (2/3)"
else
  fail "under_attempt_cap should allow 2/3"
fi
if call under_attempt_cap 3 3; then
  fail "under_attempt_cap must stop at the cap (3/3)"
else
  pass "under_attempt_cap stops at the cap (3/3 → escalate)"
fi

# --- branch safety: never write to the default branch ---
if call assert_branch_safe "EN04-hands-off-ship" "main"; then
  pass "assert_branch_safe allows a feature branch"
else
  fail "assert_branch_safe should allow a feature branch"
fi
if call assert_branch_safe "main" "main"; then
  fail "assert_branch_safe must refuse the default branch"
else
  pass "assert_branch_safe refuses the default branch"
fi
if call assert_branch_safe "" "main"; then
  fail "assert_branch_safe must refuse an empty target"
else
  pass "assert_branch_safe refuses an empty target"
fi

# --- drives /en-resolve-pr headless ---
if grep -qF "en-resolve-pr" "$CI"; then
  pass "wrapper drives /en-resolve-pr"
else
  fail "wrapper must drive /en-resolve-pr"
fi

# --- escalation: drops the label + comments ---
if grep -qF -- "--remove-label" "$CI" && grep -qE "gh pr comment" "$CI"; then
  pass "wrapper escalates by dropping the label + commenting"
else
  fail "wrapper must escalate (drop label + comment) on an unfixable failure"
fi

# --- branch-only push (never a bare/default push) ---
if grep -qE 'git push origin "HEAD:\$\{branch\}"' "$CI"; then
  pass "wrapper pushes branch-only (HEAD:<branch>)"
else
  fail "wrapper must push branch-only"
fi

# --- recursion guard ---
if grep -qF "EN_SHIP_WATCH_ACTIVE" "$CI"; then
  pass "wrapper has a recursion guard"
else
  fail "wrapper must guard against self-recursion"
fi

# --- workflow template: name + event + failure guard ---
if grep -qE "^name: en-ship-watch" "$WF"; then
  pass "workflow is named en-ship-watch"
else
  fail "workflow must be named en-ship-watch"
fi
if grep -qE "check_suite:" "$WF" && grep -qE "types: \[completed\]" "$WF"; then
  pass "workflow triggers on check_suite: completed"
else
  fail "workflow must trigger on check_suite: completed"
fi
if grep -qE "conclusion == 'failure'" "$WF"; then
  pass "workflow job guards on conclusion == failure"
else
  fail "workflow must guard the job on a failure conclusion"
fi
if grep -qF "en-ship-watch-ci" "$WF"; then
  pass "workflow invokes the en-ship-watch-ci wrapper"
else
  fail "workflow must invoke en-ship-watch-ci"
fi
if grep -qF "CLAUDE_CODE_OAUTH_TOKEN" "$WF" && grep -qF "GITHUB_TOKEN" "$WF"; then
  pass "workflow reuses en-sweep's auth secrets (no new secret)"
else
  fail "workflow must wire the shared auth secrets"
fi

report
