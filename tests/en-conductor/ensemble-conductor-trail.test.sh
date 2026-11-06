#!/usr/bin/env bash
# Tests for skills/en-conductor/scripts/ensemble-conductor-trail (EN27 U4).
#
# Runs the script in throwaway git repos and reads the trail back as the skill's
# resume does. Nothing here touches the Ensemble checkout.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="conductor trail"

T="$REPO_ROOT/skills/en-conductor/scripts/ensemble-conductor-trail"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

fresh_repo() {
  local d="$SCRATCH/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  printf '%s' "$d"
}
start_run() { bash "$T" start --request "$1" --route fix --done-when "PR open"; }
rc_of() { "$@" >/dev/null 2>&1; echo $?; }

# --- finish records the run on the rollup, without the free text ---------------
M="$REPO_ROOT/skills/en-conductor/scripts/ensemble-run-metrics"
AN="$SCRATCH/analytics"
metrics_repo=$(fresh_repo metrics)
(
  cd "$metrics_repo" || exit 1
  export ENSEMBLE_ANALYTICS_DIR="$AN"
  unset ENSEMBLE_RUN_LEDGER ENSEMBLE_METRICS
  bash "$M" start --skill en-conductor >/dev/null 2>&1
  bash "$T" start --request 'do-not-store-this-request' --route fix --done-when 'PR open' >/dev/null
  bash "$T" log question fix 'q?' 'a' >/dev/null
  bash "$T" log decision route plan 'risk surface' >/dev/null
  bash "$T" log stage plan ok 'plan.md' >/dev/null
  bash "$T" log stage qa skipped 'needs_browser false' >/dev/null
  bash "$T" log stage qa ok 'reran' >/dev/null
  bash "$T" finish stopped ship 'do-not-store-this-reason' >/dev/null
  bash "$M" finish >/dev/null 2>&1
)
ROLL=$(cat "$AN"/*.jsonl 2>/dev/null)
c() { printf '%s' "$ROLL" | jq -r ".detail.conductor$1"; }
assert_eq "en-conductor" "$(printf '%s' "$ROLL" | jq -r '.skill')" "the rollup records a conductor run"
assert_eq "plan"    "$(c .route)"        "a reroute to plan wins over the start row"
assert_eq "stopped" "$(c .state)"        "the final state is recorded"
assert_eq "ship"    "$(c .stage)"        "the stage it ended at is recorded"
assert_eq "ok"      "$(c .stages.plan)"  "each stage's result is recorded"
assert_eq "ok"      "$(c .stages.qa)"    "a stage's last row wins"
assert_eq "1"       "$(c .questions)"    "questions are counted"
assert_eq "1"       "$(c .decisions)"    "decisions are counted"
case "$ROLL" in
  *do-not-store*) fail "the rollup must not hold the request or the reason" "$ROLL" ;;
  *) pass "the rollup holds neither the request nor the reason" ;;
esac

off_repo=$(fresh_repo metrics-off)
(
  cd "$off_repo" || exit 1
  export ENSEMBLE_ANALYTICS_DIR="$SCRATCH/off" ENSEMBLE_METRICS=off
  bash "$T" start --request 'r' --route fix --done-when 'PR open' >/dev/null
  bash "$T" finish done fix 'ok' >/dev/null
) && pass "finish still succeeds with metrics off" || fail "metrics off must not fail finish"
[ ! -e "$SCRATCH/off" ] && pass "metrics off writes nothing" || fail "metrics off must write nothing"

# --- a whole run ---
R=$(fresh_repo whole); cd "$R" || exit 1
trail=$(start_run "fix the parser")
bash "$T" log stage build ok evidence
bash "$T" finish done ship reason
assert_eq "$(wc -l < "$trail" | tr -d ' ')" "4" "a run writes a header and three rows"
assert_eq "$(awk -F'\t' 'NF != 7' "$trail" | wc -l | tr -d ' ')" "0" "every row has seven columns"
assert_eq "$(awk -F'\t' 'NR==2 {print $3 "|" $6 "|" $7}' "$trail")" "fix|fix the parser|PR open" \
  "the start row holds the route, the request and the predicate"
assert_eq "$(awk -F'\t' 'NR==3 {print $4 "|" $5}' "$trail")" \
  "$(git symbolic-ref --short HEAD)|$(git rev-parse HEAD)" "a row records the branch and the full HEAD"
assert_eq "$(rc_of bash "$T" latest)" "3" "a finished run is not latest"
assert_eq "$(bash "$T" latest 2>/dev/null)" "no-open-run" "latest names why"
case "$trail" in "$(git rev-parse --absolute-git-dir)/ensemble/conductor/"*.tsv) pass "the trail sits under the git dir" ;;
  *) fail "the trail must sit under the git dir" "$trail" ;; esac

# --- a hostile value stays on one row ---
R=$(fresh_repo hostile); cd "$R" || exit 1
trail=$(start_run "one")
bash "$T" log decision route "a$(printf '\t')b" "line1
line2"
assert_eq "$(wc -l < "$trail" | tr -d ' ')" "3" "a newline does not add a row"
assert_eq "$(awk -F'\t' 'NR==3 {print NF "|" $6 "|" $7}' "$trail")" "7|a b|line1 line2" \
  "tabs and newlines become single spaces"

# --- text the shell must not run is stored as written ---
marker="$SCRATCH/injected"
bash "$T" log decision route 'quote'\''s' "\$(touch $marker) \`touch $marker\`
TXT
)"
assert_eq "$(tail -n 1 "$trail" | cut -f6)" "quote's" "a single quote survives"
assert_eq "$(tail -n 1 "$trail" | cut -f7)" "\$(touch $marker) \`touch $marker\` TXT )" "shell syntax is stored as data"
[ ! -e "$marker" ] && pass "nothing in the value ran" || fail "a logged value ran"

# --- a second start supersedes ---
err=$(start_run "two" 2>&1 >/dev/null)
case "$err" in *"$trail"*) pass "a second start names the run it closed" ;;
  *) fail "a second start must name the run it closed" "$err" ;; esac
assert_eq "$(tail -n 1 "$trail" | cut -f2)" "superseded" "the first run gets a superseded row"
second=$(bash "$T" latest)
[ "$second" != "$trail" ] && pass "latest is the new run" || fail "latest must be the new run"

# --- stop, resume, finish ---
R=$(fresh_repo cycle); cd "$R" || exit 1
trail=$(start_run "cycle")
bash "$T" finish stopped build reason
assert_eq "$(bash "$T" latest)" "$trail" "a stopped run is still latest"
assert_eq "$(rc_of bash "$T" log stage build ok x)" "3" "log refuses a stopped run"
assert_eq "$(rc_of bash "$T" finish done ship x)" "3" "finish refuses a stopped run"
bash "$T" resume >/dev/null
assert_eq "$(tail -n 1 "$trail" | cut -f2)" "resume" "resume appends its row"
assert_eq "$(rc_of bash "$T" log stage build ok x)" "0" "resume makes log work again"
bash "$T" finish done ship x
assert_eq "$(rc_of bash "$T" latest)" "3" "finish done leaves nothing to resume"
assert_eq "$(rc_of bash "$T" resume)" "3" "resume with nothing live exits 3"

# --- a new run closes a stopped one ---
trail=$(start_run "old"); bash "$T" finish stopped build reason
new=$(start_run "new" 2>/dev/null)
assert_eq "$(tail -n 1 "$trail" | cut -f2)" "superseded" "start closes a stopped run"
assert_eq "$(bash "$T" latest)" "$new" "and latest is the new run"

# --- a failed write fails, and start does not spin ---
R=$(fresh_repo readonly); cd "$R" || exit 1
trail=$(start_run "stuck"); chmod 444 "$trail"
if [ -w "$trail" ]; then
  pass "skipped: this user can write a read-only file"
else
  assert_eq "$(rc_of bash "$T" log stage build ok x)" "1" "log exits 1 on a failed write"
  bash "$T" start --request r --route fix --done-when d >/dev/null 2>&1 & p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$p" 2>/dev/null || break; sleep 1; done
  if kill -0 "$p" 2>/dev/null; then
    kill "$p"; fail "start must not spin when it cannot close a live run"
  else
    wait "$p"; assert_eq "$?" "1" "start exits 1 when it cannot close a live run"
  fi
fi
chmod 644 "$trail"

# --- usage and state errors ---
R=$(fresh_repo errors); cd "$R" || exit 1
assert_eq "$(rc_of bash "$T" log stage build ok x)" "3" "log with no run exits 3"
assert_eq "$(rc_of bash "$T" finish done ship x)" "3" "finish with no run exits 3"
start_run "errors" >/dev/null
assert_eq "$(rc_of bash "$T" log bogus x y z)" "2" "an unknown event exits 2"
assert_eq "$(rc_of bash "$T" log stage nowhere ok x)" "2" "an unknown stage exits 2"
assert_eq "$(rc_of bash "$T" log stage build done x)" "2" "a stage row's what is ok, skipped or failed"
assert_eq "$(rc_of bash "$T" start --request r --route elsewhere --done-when d)" "2" "an unknown route exits 2"
assert_eq "$(rc_of bash "$T" start --route fix)" "2" "start without a request exits 2"
assert_eq "$(rc_of bash "$T" finish maybe ship x)" "2" "an unknown finish state exits 2"

# --- outside a repo ---
mkdir -p "$SCRATCH/plain"; cd "$SCRATCH/plain" || exit 1
for sub in "start --request r --route fix --done-when d" "log stage build ok x" "finish done ship x" latest resume; do
  # shellcheck disable=SC2086
  rc=$(rc_of env GIT_CEILING_DIRECTORIES="$SCRATCH" bash "$T" $sub)
  assert_eq "$rc" "1" "outside a repo, $sub exits 1"
done
assert_eq "$(find "$SCRATCH/plain" -type f | wc -l | tr -d ' ')" "0" "outside a repo nothing is written"

# --- linked worktree ---
R=$(fresh_repo main); cd "$R" || exit 1
git worktree add -q "$SCRATCH/linked" -b linked
( cd "$SCRATCH/linked" && start_run "in the worktree" >/dev/null )
assert_eq "$(cd "$SCRATCH/linked" && rc_of bash "$T" latest)" "0" "a linked worktree sees its own run"
assert_eq "$(rc_of bash "$T" latest)" "3" "the main checkout does not see the worktree's run"

report
