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
if grep -qE 'Never \`git add \.\` or \`git add -A\`' "$S"; then
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

# --- targeted-test selection (EN15 U8) ---------------------------------------
# The old heuristic assumed tests sit beside sources. In a layout where they do
# not, it matched nothing, ran nothing, and reported a pass — the silent case.
has "$S" "resolve the set in this fixed order" "test selection has a fixed resolution order"
has "$S" "test_changed_command:" "a project command wins outright"
has "$S" "test_impact:" "the prefix map is the second tier"
has "$S" "sibling-filename heuristic" "the heuristic remains the fallback"
has "$S" "Report why each test was selected" "the selection is auditable"
has "$S" "An empty selection is reported as empty, never as a pass" \
                                              "zero tests found is not a green check"

# The order is asserted structurally, so a later edit cannot silently promote the
# heuristic above a map the project actually declared.
cmd_line=$(grep -n 'test_changed_command:' "$S" | head -1 | cut -d: -f1)
map_line=$(grep -n 'The `test_impact:` prefix map' "$S" | head -1 | cut -d: -f1)
heur_line=$(grep -n 'sibling-filename heuristic' "$S" | head -1 | cut -d: -f1)
if [ -n "$cmd_line" ] && [ -n "$map_line" ] && [ -n "$heur_line" ] \
   && [ "$cmd_line" -lt "$map_line" ] && [ "$map_line" -lt "$heur_line" ]; then
  pass "command beats map beats heuristic, in that order"
else
  fail "command beats map beats heuristic, in that order" \
       "cmd=$cmd_line map=$map_line heuristic=$heur_line"
fi

# The schema has to exist where a project can actually declare it, in both
# carriers of the template. A rule with nowhere to be written is decorative.
for t in "$REPO_ROOT"/skills/*/references/templates/agents-md-template.md; do
  grep -qF '## Test impact' "$t" \
    && pass "AGENTS.md template offers a Test impact section: $(basename "$(dirname "$(dirname "$(dirname "$t")")")")" \
    || fail "AGENTS.md template offers a Test impact section: $t"
done

# --- receipt consumption (EN15 U3) -------------------------------------------
# The unit that can skip verification. A wrong rule here ships untested code, so
# these clauses are about what en-ship must REFUSE to do, not what it may do.
has "$S" 'verify --requires lint,typecheck,full_suite' "preflight asks the receipt what it covers"
has "$S" "surface the refusal reason verbatim" "a refusal is reported, never silent"
has "$S" "There is no partial credit" "an invalid receipt means run everything"
has "$S" "The secret scan and \`git diff --check\` always run" \
                                              "cheap diff-scoped checks are never skipped"

# Ordering: the receipt is consulted AFTER the base-freshness gate. Consulting it
# first would accept a receipt whose base had silently advanced.
base_line=$(grep -n "Base freshness" "$S" | head -1 | cut -d: -f1)
receipt_line=$(grep -n "already proved this exact tree" "$S" | head -1 | cut -d: -f1)
if [ -n "$base_line" ] && [ -n "$receipt_line" ] && [ "$base_line" -lt "$receipt_line" ]; then
  pass "the receipt is consulted after the base-freshness gate"
else
  fail "the receipt is consulted after the base-freshness gate" "base=$base_line receipt=$receipt_line"
fi

# The reintroduction guard. Codex proposed "run tests covering the incoming base
# delta" as a receipt branch; EN15 rejected it because selecting tests from a
# delta is exactly the analysis the project cannot do reliably. This is what
# stops a later editor adding it back as an obvious-looking optimisation.
if grep -qiE 'tests covering (the )?(incoming )?(base )?delta|only the (tests|suite) affected by' "$S"; then
  fail "no partial-credit path may be reintroduced" \
       "en-ship names a subset-of-tests path; an invalid receipt must mean run everything"
else
  pass "no partial-credit path may be reintroduced"
fi

report
