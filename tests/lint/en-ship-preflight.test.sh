#!/usr/bin/env bash
# tests/lint/en-ship-preflight.test.sh
#
# What /en-ship does before it commits: base freshness, deterministic staging,
# and evidence-backed claims in the PR body.
#
# Both mechanisms here are evidenced by a real incident, not by inspection. On
# PR #240 origin/main had advanced with no gate to notice, the rebase was manual,
# and an untracked file disappeared and had to be restored. The staging rules
# exist because the failure protocol used to offer "stage all" on a dirty tree.
#
# Every clause is scoped to en-ship's SKILL.md and anchored on wording only that
# file carries. Widening a grep to the skill directory re-opens the decorative-
# guard hole this campaign hit about ten times.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-ship preflight"
cd "$REPO_ROOT"

S=skills/en-ship/SKILL.md

has() { grep -qF "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$1")"; }

# --- step 1 exists, and resolves the things later steps read -----------------
grep -qE '^1\. \*\*Resolve context' "$S" \
  && pass "the process has a step 1" \
  || fail "the process has a step 1" "it opened at step 2 until 2026-09-01"

# Re-running on a branch that already has a PR must update it, not open a second.
has "$S" "this run updates it" "an existing PR is updated, not re-created"

# --- base freshness ----------------------------------------------------------
has "$S" "git fetch origin <base>"        "preflight fetches the base"
has "$S" "ahead/behind"                   "preflight reports ahead/behind"
has "$S" "git merge-tree"                 "conflicts are predicted before integrating"
has "$S" "Never rewrite a published branch automatically" \
                                          "a published branch is not silently rebased"
has "$S" "force-with-lease"               "force is gated behind explicit approval"

# The untracked-file inventory. This is the clause that maps to the lost file.
has "$S" "Inventory untracked and unstaged files first" \
                                          "untracked files are inventoried before integration"
has "$S" "verify that inventory after"    "the inventory is checked again afterwards"

# --- deterministic staging ---------------------------------------------------
has "$S" "Resolve one case explicitly"    "staging resolves exactly one case"

# All five cases, each asserted on its own: a count would pass on five copies of one.
has "$S" "Push the existing commits. Create no new commit." \
                                          "case: clean branch already ahead of base"
has "$S" "Stage that computed allowlist"  "case: in-scope tracked changes"
has "$S" "Preserve and exclude"           "case: unrelated files are preserved"
has "$S" "Stop as a no-op"                "case: nothing to ship is not a failure"
has "$S" "do not call \`gh pr create\` again" \
                                          "case: an existing PR is updated"

# The specific commands that caused the incident class.
# Fixed-string, not a regex. As an ERE this read `Never \`git add ...` — and in
# GNU grep (which is what CI runs) \` is the "beginning of buffer" anchor, so the
# pattern could never match mid-line. BSD grep on macOS treats it as a literal
# backtick, so it passed locally and failed only in CI.
if grep -qF 'Never `git add .` or `git add -A`' "$S"; then
  pass "bare staging is forbidden by name"
else
  fail "bare staging must be forbidden by name (git add . / git add -A)"
fi

# The failure protocol used to offer the thing the state machine forbids.
if grep -qE '\| Unstaged dirty tree at start \|.*stage all, stage nothing' "$S"; then
  fail "the failure protocol no longer offers \"stage all\""
else
  pass "the failure protocol no longer offers \"stage all\""
fi

# --- the PR body claims only what ran ----------------------------------------
has "$S" "what was **actually run**"      "the test plan reports what actually ran"
has "$S" "No test run recorded for this branch" \
                                          "an absent test run is stated, not filled in"
if grep -qF "otherwise generated from changed files" "$S"; then
  fail "the test plan is never synthesised from the changed files"
else
  pass "the test plan is never synthesised from the changed files"
fi

report
