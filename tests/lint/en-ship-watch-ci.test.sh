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

# --- fork guard uses isCrossRepository (not owner comparison) ---
if call is_cross_repository "true"; then
  pass "is_cross_repository detects a fork/cross-repo PR"
else
  fail "is_cross_repository must detect a cross-repository PR"
fi
if call is_cross_repository "false"; then
  fail "is_cross_repository must treat a same-repo PR as not-cross"
else
  pass "is_cross_repository allows a same-repo PR"
fi

# --- attempt cap actually advances: stamp_attempt writes the counted trailer ---
if grep -qE "stamp_attempt" "$CI" && grep -qE "trailer \"\\\$\{ATTEMPT_TRAILER\}|--trailer \"\\\$\{ATTEMPT_TRAILER\}" "$CI"; then
  pass "wrapper stamps the attempt trailer that count_attempts reads (cap advances)"
else
  fail "wrapper must stamp the en-ship-watch-attempt trailer so the cap advances"
fi

# --- trigger-token gate: escalate when GITHUB_TOKEN can't retrigger CI ---
if grep -qE "EN_SHIP_WATCH_HAS_TRIGGER_TOKEN" "$CI"; then
  pass "wrapper gates on a workflow-triggering token (GITHUB_TOKEN won't retrigger CI)"
else
  fail "wrapper must escalate when no workflow-triggering token is present"
fi

# --- push failure escalates instead of exiting with the label armed ---
if grep -qE 'if ! git push origin' "$CI"; then
  pass "wrapper wraps the push and escalates on failure"
else
  fail "wrapper must escalate on push failure (not exit under set -e with label armed)"
fi

# --- SECURITY: fork rejected BEFORE any PR branch is fetched/checked out ---
reject_line=$(grep -n "is_cross_repository" "$CI" | head -1 | cut -d: -f1)
fetch_line=$(grep -n "git fetch origin" "$CI" | head -1 | cut -d: -f1)
if [ -n "$reject_line" ] && [ -n "$fetch_line" ] && [ "$reject_line" -lt "$fetch_line" ]; then
  pass "fork gate runs BEFORE any PR-branch fetch/checkout (no untrusted code run)"
else
  fail "fork rejection must precede fetching PR code (reject=$reject_line fetch=$fetch_line)"
fi

# --- guarded stamp + bot identity (no set -e exit with label armed) ---
if grep -qE 'if ! stamp_attempt' "$CI" && grep -qF "configure_git_identity" "$CI"; then
  pass "wrapper sets a bot git identity and guards stamp_attempt"
else
  fail "wrapper must configure a git identity and guard stamp_attempt"
fi

# --- CLI-missing escalates (not a silent job death with label armed) ---
if grep -qiE "no claude or codex CLI" "$CI"; then
  pass "wrapper escalates when no agent CLI is available"
else
  fail "wrapper must escalate when no agent CLI is present"
fi

# --- skill-resolution guard: unregistered skill escalates (not green-but-inert) ---
if call skill_resolved "some normal output"; then
  pass "skill_resolved passes on normal output"
else
  fail "skill_resolved should pass on normal output"
fi
if call skill_resolved "Unknown command: /en-resolve-pr"; then
  fail "skill_resolved must fail when the skill is unregistered"
else
  pass "skill_resolved detects an unregistered skill (green-but-inert guard)"
fi
if grep -qiE "en-resolve-pr skill is not available" "$CI"; then
  pass "wrapper escalates clearly when the skill isn't registered"
else
  fail "wrapper must escalate with a clear message when the skill isn't registered"
fi

# --- codex path also passes --plugin-dir (regression guard) ---
if grep -qE 'codex exec --json --plugin-dir' "$CI"; then
  pass "codex path passes --plugin-dir when ENSEMBLE_PLUGIN_DIR is set"
else
  fail "codex path must pass --plugin-dir (skill resolution)"
fi

# --- workflow checks out TRUSTED default-branch code, not the PR head ---
if grep -qE 'ref: \$\{\{ github.event.repository.default_branch \}\}' "$WF"; then
  pass "workflow checks out trusted default-branch code (not PR head)"
else
  fail "workflow must check out the default branch (never PR-head code) for the privileged run"
fi
if grep -qE 'ref: \$\{\{ github.event.workflow_run.head_sha \}\}' "$WF"; then
  fail "workflow must NOT check out PR-head SHA as the run ref (pwn-request risk)"
else
  pass "workflow does not run from PR-head SHA (pwn-request avoided)"
fi

# --- workflow really installs a CLI (not just checks PATH) ---
if grep -qE "npm install -g @anthropic-ai/claude-code" "$WF"; then
  pass "workflow has a real CLI install step"
else
  fail "workflow must actually install an agent CLI, not only check PATH"
fi

# --- CLI install is NONFATAL (so a failed install still reaches the wrapper's escalation) ---
if grep -qE "continue-on-error: true" "$WF" && grep -qE "npm install -g @anthropic-ai/claude-code \|\| true" "$WF"; then
  pass "CLI install is nonfatal (wrapper always runs to escalate on missing CLI)"
else
  fail "CLI install must be nonfatal so the wrapper's missing-CLI escalation fires"
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
if grep -qE "workflow_run:" "$WF" && grep -qE "types: \[completed\]" "$WF"; then
  pass "workflow triggers on a CI workflow_run: completed"
else
  fail "workflow must trigger on workflow_run: completed"
fi
if grep -qE "workflow_run.conclusion == 'failure'" "$WF"; then
  pass "workflow job guards on workflow_run.conclusion == failure"
else
  fail "workflow must guard the job on a failure conclusion"
fi
if grep -qF "{{CI_WORKFLOW_NAMES}}" "$WF"; then
  pass "workflow names the CI workflows via a substituted placeholder (no self-trigger)"
else
  fail "workflow must name the CI workflows (workflow_run avoids self-trigger)"
fi
if grep -qF "EN_SHIP_WATCH_TOKEN" "$WF"; then
  pass "workflow wires the workflow-triggering token (retriggers CI)"
else
  fail "workflow must wire EN_SHIP_WATCH_TOKEN so the fix push retriggers CI"
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
