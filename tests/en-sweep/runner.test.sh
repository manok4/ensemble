#!/usr/bin/env bash
# tests/en-sweep/runner.test.sh
#
# D101: ensemble-sweep-runner runs /en-sweep through Codex on a schedule and
# merges the eligible PRs afterwards. Behavioural, against the real script,
# with `codex` and `gh` stubbed on PATH and a real git clone with a bare origin.
# Every clause was negative-controlled at authoring (the merge clause by making
# the stub write merge_eligible: false for PR 7; the no-result clause by
# letting the stub write the file).

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-sweep runner (D101)"

RUNNER="$REPO_ROOT/skills/en-sweep/scripts/ensemble-sweep-runner"
assert_file_exists "$RUNNER" "runner exists"
[ -x "$RUNNER" ] && pass "runner is executable" || fail "runner is executable"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export ENSEMBLE_HOME_DIR="$T/ensemble" ENSEMBLE_SWEEP_LOG="$T/ensemble/logs/sweep.log" ENSEMBLE_SWEEP_LOCK="$T/ensemble/sweep.lock"
export ENSEMBLE_SWEEP_CHECKS_POLL=0 ENSEMBLE_SWEEP_CHECKS_TIMEOUT=0
mkdir -p "$T/stub"

# ---- stubs -----------------------------------------------------------------
cat > "$T/stub/codex" <<'S'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_CODEX_ARGV"
dir=""; prev=""
for a in "$@"; do [ "$prev" = "-C" ] && dir="$a"; prev="$a"; done
if [ "${STUB_CODEX_NO_RESULT:-0}" != "1" ]; then
  mkdir -p "$dir/.ensemble"
  printf '{"run_id":"r1","prs":[{"number":7,"batch":"arch","review":"clean","merge_eligible":true},{"number":8,"batch":"maps","review":"findings","merge_eligible":false,"reason":"P1"}]}\n' > "$dir/.ensemble/sweep-result.json"
  printf '## en-sweep summary\nstub\n' > "$dir/.ensemble/sweep-summary.md"
fi
exit 0
S
cat > "$T/stub/gh" <<'S'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view")   echo main ;;
  "pr view")     case "$*" in *statusCheckRollup*) echo "${STUB_GH_CHECK:-SUCCESS}" ;; *mergeStateStatus*) echo CLEAN ;; esac ;;
  "pr merge")    printf '%s\n' "$*" >> "$STUB_GH_MERGES" ;;
  *) exit 1 ;;
esac
S
chmod +x "$T/stub/codex" "$T/stub/gh"
export PATH="$T/stub:$PATH" STUB_CODEX_ARGV="$T/argv" STUB_GH_MERGES="$T/merges"

# ---- fixture: a clone with a bare origin and one human commit -------------
mkrepo() {  # $1=name $2=last-commit-subject
  ( set -e; cd "$T"; git init -q --bare "$1.git"; git clone -q "$T/$1.git" "$1" 2>/dev/null; cd "$1"
    git config user.email t@t.local; git config user.name T; git config commit.gpgsign false
    git commit -q --allow-empty -m "chore(sweep): baseline"; git commit -q --allow-empty -m "$2"
    git branch -q -M main; git push -q -u origin main ) 2>/dev/null
}
mkrepo r1 "feat: human change"
mkdir -p "$T/r1/.ensemble"; printf 'sweep:\n  model: fable\n  effort: high\n' > "$T/r1/.ensemble/config.local.yaml"

# ---- 1. a full run: config model and effort reach codex; eligible PR merges --
: > "$T/merges"
out=$(bash "$RUNNER" --repo "$T/r1" 2>&1); rc=$?
assert_exit_code 0 "$rc" "full run exits 0"
grep -qx -- "-m" "$T/argv" && grep -qx "fable" "$T/argv" && pass "sweep.model reaches codex as -m" || fail "sweep.model reaches codex as -m" "$(tr '\n' ' ' < "$T/argv")"
grep -qx 'model_reasoning_effort="high"' "$T/argv" && pass "sweep.effort reaches codex" || fail "sweep.effort reaches codex"
grep -qx -- "--json" "$T/argv" && pass "codex runs headless with --json" || fail "codex runs headless with --json"
grep -q "operating unattended" "$T/argv" && pass "the prompt carries the autonomous framing" || fail "the prompt carries the autonomous framing"
grep -q "do not merge anything yourself" "$T/argv" && pass "the prompt leaves merging to the runner" || fail "the prompt leaves merging to the runner"
grep -q "^7 --squash --delete-branch" <(sed 's/^pr merge //' "$T/merges") && pass "the eligible PR is squash-merged" || fail "the eligible PR is squash-merged" "$(cat "$T/merges")"
grep -q "^pr merge 8 " "$T/merges" && fail "an ineligible PR is not merged" || pass "an ineligible PR is not merged"

# ---- 2. no result file: nothing merges, the run fails loudly ---------------
: > "$T/merges"
out=$(STUB_CODEX_NO_RESULT=1 bash "$RUNNER" --repo "$T/r1" --force 2>&1); rc=$?
assert_exit_code 1 "$rc" "a run with no result file exits 1"
[ ! -s "$T/merges" ] && pass "nothing merges without a result file" || fail "nothing merges without a result file"
printf '%s' "$out" | grep -q "did not execute" && pass "the log names the missing result" || fail "the log names the missing result"

# ---- 3. a failed check leaves the PR open ---------------------------------
: > "$T/merges"
STUB_GH_CHECK=FAILURE bash "$RUNNER" --repo "$T/r1" --force >/dev/null 2>&1; rc=$?
[ ! -s "$T/merges" ] && pass "a PR with a failed check is left open" || fail "a PR with a failed check is left open"
assert_exit_code 1 "$rc" "a left-open PR counts as a failure"

# ---- 4. the activity gate skips a repo with no human commits ---------------
mkrepo r2 "chore(sweep): only sweep commits"
rm -f "$T/argv"
out=$(bash "$RUNNER" --repo "$T/r2" 2>&1); rc=$?
assert_exit_code 0 "$rc" "a gated repo exits 0"
[ ! -f "$T/argv" ] && pass "codex is not launched when the gate says skip" || fail "codex is not launched when the gate says skip"
printf '%s' "$out" | grep -q "activity gate" && pass "the skip names the gate" || fail "the skip names the gate"
rm -f "$T/argv"; bash "$RUNNER" --repo "$T/r2" --force >/dev/null 2>&1
[ -f "$T/argv" ] && pass "--force bypasses the gate" || fail "--force bypasses the gate"

# ---- 5. machine-wide env default when the repo sets no model --------------
# r2 now carries the stub's untracked .ensemble/ files from clause 4; a runner
# that read them as a dirty tree would skip here, which is what this guards.
rm -f "$T/argv"; rm -f "$T/r2/.ensemble/config.local.yaml"
ENSEMBLE_SWEEP_MODEL=tier-x ENSEMBLE_SWEEP_EFFORT=turbo bash "$RUNNER" --repo "$T/r2" --force >/dev/null 2>&1
grep -qx "tier-x" "$T/argv" && pass "ENSEMBLE_SWEEP_MODEL is the default model" || fail "ENSEMBLE_SWEEP_MODEL is the default model"
grep -q "model_reasoning_effort" "$T/argv" && fail "an unknown effort is dropped" || pass "an unknown effort is dropped"

# ---- 6. --dry-run and --no-merge ------------------------------------------
rm -f "$T/argv"; : > "$T/merges"
bash "$RUNNER" --repo "$T/r1" --force --dry-run >/dev/null 2>&1
[ ! -f "$T/argv" ] && pass "--dry-run launches nothing" || fail "--dry-run launches nothing"
bash "$RUNNER" --repo "$T/r1" --force --no-merge >/dev/null 2>&1
[ ! -s "$T/merges" ] && pass "--no-merge leaves PRs open" || fail "--no-merge leaves PRs open"
: > "$T/merges"; bash "$RUNNER" --repo "$T/r1" --merge-only >/dev/null 2>&1
grep -q "^pr merge 7 " "$T/merges" && pass "--merge-only merges from the existing result file" || fail "--merge-only merges from the existing result file"

# ---- 7. lock, dirty tree, repo list ---------------------------------------
mkdir -p "$ENSEMBLE_SWEEP_LOCK"; echo $$ > "$ENSEMBLE_SWEEP_LOCK/pid"
out=$(bash "$RUNNER" --repo "$T/r1" --force 2>&1); rc=$?
assert_exit_code 0 "$rc" "a held lock exits 0"
printf '%s' "$out" | grep -q "another run holds" && pass "a held lock is reported, not raced" || fail "a held lock is reported, not raced"
rm -rf "$ENSEMBLE_SWEEP_LOCK"
echo dirty > "$T/r1/untracked.txt"
out=$(bash "$RUNNER" --repo "$T/r1" --force 2>&1); rm -f "$T/r1/untracked.txt"
printf '%s' "$out" | grep -q "dirty" && pass "a dirty tree is skipped" || fail "a dirty tree is skipped"
printf '# comment\n%s\n\n%s\n' "$T/r1" "$T/r2" > "$T/repos"
rm -f "$T/argv"; bash "$RUNNER" --repos "$T/repos" --force >/dev/null 2>&1
grep -c "^== " "$ENSEMBLE_SWEEP_LOG" | grep -qE '^[0-9]+$' && pass "the repo list is read with comments and blanks ignored" || fail "the repo list is read"
n=$(grep -c "== $T/r" "$ENSEMBLE_SWEEP_LOG"); [ "$n" -ge 2 ] && pass "both listed repos were visited" || fail "both listed repos were visited" "$n"

report
