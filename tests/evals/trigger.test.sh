#!/usr/bin/env bash
# tests/evals/trigger.test.sh
#
# Routing guard for the model-invocable skills (EN25 U2). tests/evals/trigger-rank
# ranks every skill's description against the prompts in tests/evals/cases/ and
# fails when a positive prompt misses its skill's top 3, when a negative prompt's
# owner does not outrank the skill, or when two descriptions converge.
#
# Floor: baseline rank-1 rate on 2026-11-03 was 94.4% (34 of 36 positives first,
# all 36 within top 3), after en-ship gained "pull request" and en-learn gained
# "record this decision". The floor is 5 points under it, rounded down: 89.
# Raise it as routing improves; never lower it to make a regression pass.
#
# Negative controls below run every time, not just at authoring: a synthetic
# skills dir with a near-duplicate pair, and one where a prompt's words belong to
# another skill, must both go red. A guard that cannot fail proves nothing.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill trigger routing"

RANK="$REPO_ROOT/tests/evals/trigger-rank"
FLOOR=89

out=$(python3 "$RANK" --min-rank1 "$FLOOR" 2>&1); rc=$?
assert_exit_code 0 "$rc" "every model-invocable skill routes its prompts at rank-1 >= $FLOOR%"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" >&2

# Negative control on the floor itself: no rate can exceed 100.
out=$(python3 "$RANK" --min-rank1 100.1 2>&1); rc=$?
assert_exit_code 1 "$rc" "a floor above any reachable rate fails"
assert_contains "$out" "under the floor" "and says the rank-1 rate is under the floor"

json=$(python3 "$RANK" --json 2>/dev/null)
count=$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["skills"])')
cases=$(ls "$REPO_ROOT"/tests/evals/cases/*.json | wc -l | tr -d ' ')
assert_eq "$count" "$cases" "every model-invocable skill has a case file ($count skills, $cases cases)"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkskill() { # dir name description [manual]
  mkdir -p "$1/$2"
  { echo '---'; echo "name: $2"; echo "description: \"$3\""
    [ -n "${4:-}" ] && echo 'disable-model-invocation: true'; echo '---'; } > "$1/$2/SKILL.md"
}
mkcase() { # dir skill json-body
  mkdir -p "$1"; printf '%s\n' "$3" > "$1/$2.json"
}

# --- negative control: two near-identical descriptions collide ---
S="$T/collide/skills"; C="$T/collide/cases"
mkskill "$S" alpha "Rotate the database credentials and restart the connection pool safely"
mkskill "$S" beta  "Rotate the database credentials and restart the connection pool quickly"
mkskill "$S" gamma "Render the marketing landing page with responsive images"
mkcase "$C" gamma '{"skill":"gamma","positive":[{"prompt":"render the landing page","top_k":1}],"negative":[]}'
out=$(python3 "$RANK" --skills-dir "$S" --cases-dir "$C" 2>&1); rc=$?
assert_exit_code 1 "$rc" "a near-duplicate description pair fails"
assert_contains "$out" "alpha ~ beta" "the collision names the pair"

# --- negative control: a prompt whose words belong to another skill ---
S="$T/route/skills"; C="$T/route/cases"
mkskill "$S" deploy  "Deploy the service to the staging cluster with a canary rollout"
mkskill "$S" invoice "Generate customer invoices and email the monthly statements"
mkskill "$S" search  "Index documents for full text search and rebuild the ranking"
mkcase "$C" deploy '{"skill":"deploy","positive":[{"prompt":"email the monthly customer invoices","top_k":1}],"negative":[]}'
out=$(python3 "$RANK" --skills-dir "$S" --cases-dir "$C" 2>&1); rc=$?
assert_exit_code 1 "$rc" "a positive prompt that routes elsewhere fails"
assert_contains "$out" "email the monthly customer invoices" "the failure names the prompt"

# --- a negative case whose owner wins passes; one whose owner loses fails ---
mkcase "$C" deploy '{"skill":"deploy","positive":[{"prompt":"canary rollout to staging","top_k":1}],"negative":[{"prompt":"rebuild the search index","owner":"search"}]}'
python3 "$RANK" --skills-dir "$S" --cases-dir "$C" >/dev/null 2>&1
assert_exit_code 0 "$?" "a negative whose owner outranks the skill passes"
mkcase "$C" deploy '{"skill":"deploy","positive":[{"prompt":"canary rollout to staging","top_k":1}],"negative":[{"prompt":"deploy to the staging cluster","owner":"search"}]}'
python3 "$RANK" --skills-dir "$S" --cases-dir "$C" >/dev/null 2>&1
assert_exit_code 1 "$?" "a negative whose owner loses fails"

# --- a known_gap that now routes correctly is stale and fails ---
mkcase "$C" deploy '{"skill":"deploy","positive":[{"prompt":"canary rollout to staging","top_k":1}],"negative":[{"prompt":"rebuild the search index","owner":"search","known_gap":"shared words"}]}'
out=$(python3 "$RANK" --skills-dir "$S" --cases-dir "$C" 2>&1); rc=$?
assert_exit_code 1 "$rc" "a known_gap that routes correctly is stale"
assert_contains "$out" "stale known_gap" "the failure says to delete it"

# --- invalid input exits 2, never a rate ---
S="$T/manual/skills"; C="$T/manual/cases"
mkskill "$S" auto "Summarize the weekly sales report"
mkskill "$S" hands "Reconcile the ledger by hand" manual
mkcase "$C" hands '{"skill":"hands","positive":[{"prompt":"reconcile the ledger"}],"negative":[]}'
out=$(python3 "$RANK" --skills-dir "$S" --cases-dir "$C" 2>&1); rc=$?
assert_exit_code 2 "$rc" "a case for a manual skill is a usage error"
assert_contains "$out" "case for manual skill hands" "the error names the manual skill"

rm "$C/hands.json"
mkcase "$C" auto '{"skill":"auto","positive":[{"prompt":"weekly sales summary"}],"negative":[{"prompt":"anything","owner":"nosuch"}]}'
python3 "$RANK" --skills-dir "$S" --cases-dir "$C" >/dev/null 2>&1
assert_exit_code 2 "$?" "a negative owner that does not exist is a usage error"

out=$(python3 "$RANK" --skills-dir "$T/does-not-exist" --cases-dir "$C" 2>&1); rc=$?
assert_exit_code 2 "$rc" "an unreadable skills dir exits 2"
assert_not_contains "$out" "rank-1" "an unreadable skills dir never prints a rate"

report
