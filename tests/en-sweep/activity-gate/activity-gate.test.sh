#!/usr/bin/env bash
# Test for skills/en-sweep/scripts/ensemble-sweep-activity-check.
#
# The gate decides whether a scheduled sweep runs at all, and until 2026-09-03
# nothing tested it. Its wrong answer is the silent one: should-run=false posts
# no PR, no comment and no log the user reads, so a gate that skips forever is
# indistinguishable from a repo with no drift. That is the same shape as the
# green-but-inert bug SKILL.md already records (FR01 U11), which is what makes
# an untested gate worth a fixture rather than a comment.
#
# Scenario 3 is the one that found a live defect: `docs` was in SWEEP_PATTERN,
# so a human `chore(docs): fix a typo` was read as sweep's own commit twice, and
# the cycle skipped.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-sweep activity gate"

GATE="$REPO_ROOT/skills/en-sweep/scripts/ensemble-sweep-activity-check"

# Every scenario runs against a throwaway repo on a local branch. --branch takes
# a ref, so `main` works and no remote is needed.
new_repo() {
  local tmp; tmp=$(mktemp -d)
  git -C "$tmp" init -q -b main
  git -C "$tmp" config user.email "test@test"
  git -C "$tmp" config user.name "Test"
  printf '%s' "$tmp"
}

commit() { git -C "$1" commit -q --allow-empty -m "$2"; }

# Run the gate inside the repo and return its stdout. The gate reads the working
# directory's git, so cd matters; a subshell keeps the caller's cwd.
gate() ( cd "$1" && shift && bash "$GATE" --branch main "$@" 2>&1 )

# --- 1. No sweep has ever run -> run, and say why -----------------------------
# The install-time case. A gate that skipped here would never fire on a fresh
# repo, because the first sweep is what creates the commit it looks for.
R=$(new_repo); commit "$R" "feat: initial work"
out=$(gate "$R")
assert_contains "$out" "should-run=true" "first run with no prior sweep runs"
assert_contains "$out" "first run after install" "and names the reason"
rm -rf "$R"

# --- 2. Sweep ran, nothing since -> skip --------------------------------------
# The gate's whole purpose: no new work means no LLM calls.
R=$(new_repo)
commit "$R" "feat: initial work"
commit "$R" "chore(sweep): fix 3 lint findings"
out=$(gate "$R")
assert_contains "$out" "should-run=false" "no activity since last sweep skips"
rm -rf "$R"

# --- 3. A human doc commit is activity ----------------------------------------
# The regression. `chore(docs):` is a scope humans reach for constantly, and
# while it was in SWEEP_PATTERN this returned false: the human commit was picked
# as LAST_SWEEP_SHA and subtracted by --invert-grep at the same time.
R=$(new_repo)
commit "$R" "chore(sweep): fix 3 lint findings"
commit "$R" "chore(docs): fix a typo in the README"
out=$(gate "$R")
assert_contains "$out" "should-run=true" "a human chore(docs) commit counts as activity"
rm -rf "$R"

# Same claim from the other side: no scope the gate treats as sweep's own may be
# one a human would plausibly type. This asserts the list, so widening it back
# to `docs` fails here even if scenario 3 were somehow satisfied another way.
assert_not_contains \
  "$(grep '^SWEEP_PATTERN=' "$REPO_ROOT/skills/en-sweep/scripts/ensemble-sweep-activity-check")" \
  "docs" "SWEEP_PATTERN claims no scope humans share"

# And the batch table must not reintroduce the collision from the other end.
assert_not_contains \
  "$(grep -F 'lint-fixes' "$REPO_ROOT/skills/en-sweep/references/sweep-checks.md")" \
  "chore(docs)" "the lint batch does not author a human-shared scope"

# --- 4. Ordinary commits since the last sweep -> run --------------------------
R=$(new_repo)
commit "$R" "chore(sweep): fix 3 lint findings"
commit "$R" "fix: correct the retry backoff"
commit "$R" "feat: add the billing endpoint"
out=$(gate "$R")
assert_contains "$out" "should-run=true" "commits since last sweep run the cycle"
assert_contains "$out" "2 new commit" "and the count excludes the sweep commit itself"
rm -rf "$R"

# --- 5. Sweep's own scopes still do not count as activity ---------------------
# The counting half of the pattern. If these were treated as human commits,
# every sweep run would schedule the next one and the gate would never skip.
R=$(new_repo)
commit "$R" "feat: initial work"
commit "$R" "chore(sweep): fix 3 lint findings"
for scope in arch plans learnings maps; do
  commit "$R" "chore($scope): a sweep-authored follow-up"
done
out=$(gate "$R")
assert_contains "$out" "should-run=false" "sweep's own scopes are not activity"
rm -rf "$R"

# --- 6. Manual dispatch bypasses everything -----------------------------------
R=$(new_repo)
commit "$R" "chore(sweep): fix 3 lint findings"
out=$(gate "$R" --manual)
assert_contains "$out" "should-run=true" "--manual overrides a would-be skip"
assert_contains "$out" "manual trigger" "and names itself as the reason"
rm -rf "$R"

# --- 7. Not a git repo -> run, do not crash -----------------------------------
# Fails open on purpose. A gate that errored here would take the workflow red on
# every runner that checked out shallow or not at all.
TMP=$(mktemp -d)
out=$(cd "$TMP" && bash "$GATE" --branch main 2>&1)
rc=$?
assert_exit_code 0 "$rc" "outside a repo the gate still exits 0"
assert_contains "$out" "should-run=true" "and fails open rather than skipping"
rm -rf "$TMP"

# --- 8. An unknown branch is not silently a skip ------------------------------
# git log against a ref that does not exist prints nothing, and the gate reads
# an empty result as "no prior sweep" -> run. Fails open, same as 7.
R=$(new_repo); commit "$R" "feat: initial work"
out=$(cd "$R" && bash "$GATE" --branch origin/nonexistent 2>&1)
assert_contains "$out" "should-run=true" "an unresolvable branch fails open"
rm -rf "$R"

report
