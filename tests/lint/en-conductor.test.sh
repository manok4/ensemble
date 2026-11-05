#!/usr/bin/env bash
# Drift guards for the /en-conductor skill (EN27 U4), which replaced /en-flow.
#
# Negative controls, run once at authoring: swapping the question policy's second
# and third branches turned this file red, removing `verdict: ok` turned
# en-conductor-gate-contracts red, and deleting skills/en-fix/CONTRACT.md turned
# contract-shape red.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-conductor skill"

SK="$REPO_ROOT/skills/en-conductor/SKILL.md"
assert_file_exists "$SK" "en-conductor SKILL.md exists"
has() { grep -qF -- "$1" "$SK" && pass "$2" || fail "$2" "missing: $1"; }
section() { awk -v h="## $1" '$0==h{f=1; next} f&&/^## /{exit} f' "$SK"; }

frontmatter=$(awk 'NR==1 && /^---$/{on=1; next} on && /^---$/{exit} on' "$SK")
printf '%s\n' "$frontmatter" | grep -qx 'disable-model-invocation: true' \
  && pass "it is manual-invoke only" || fail "it must carry disable-model-invocation: true"
has 'ENSEMBLE_PEER_REVIEW=true' "it has a recursion guard"

# --- the question policy's order is its meaning ---
qp=$(section 'Question policy')
order=$(printf '%s\n' "$qp" | grep -E '^[123]\. ' | cut -c1-40)
first=$(printf '%s\n' "$order" | sed -n 1p); second=$(printf '%s\n' "$order" | sed -n 2p); third=$(printf '%s\n' "$order" | sed -n 3p)
case "$first"  in *'running or reading'*) pass "first, answer by running or reading" ;; *) fail "branch 1 must answer by running or reading" "$first" ;; esac
case "$second" in *'product or preference'*) pass "second, ask a product or preference call" ;; *) fail "branch 2 must ask a product or preference call" "$second" ;; esac
case "$third"  in *'Decide everything else'*) pass "third, decide the rest" ;; *) fail "branch 3 must decide the rest" "$third" ;; esac
printf '%s\n' "$qp" | grep -E '^2\. ' | grep -qF 'even when the call could be reversed later' \
  && pass "a reversible product call is still asked" || fail "branch 2 must hold for a reversible call"
printf '%s\n' "$qp" | grep -qF 'en-conductor: stopped at <stage>: <question>' \
  && pass "with no question tool, a reserved call ends the run" || fail "the no-question-tool rule must end the run"

# --- stages, in order ---
st=$(section 'Stages')
lines=""
for s in Plan Build Learn QA Ship; do
  lines="$lines $(printf '%s\n' "$st" | grep -n "^| $s |" | head -1 | cut -d: -f1)"
done
[ "$(printf '%s\n' $lines | grep -c .)" -eq 5 ] && [ "$(printf '%s\n' $lines | sort -n | tr '\n' ' ')" = "$(printf '%s\n' $lines | tr '\n' ' ')" ] \
  && pass "stages ordered plan, build, learn, qa, ship" || fail "stages must run plan, build, learn, qa, ship" "$lines"

printf '%s\n' "$st" | grep -E '^\| Ship \|' | grep -qF 'skipped under `--no-ship` or `local_only`' \
  && pass "Ship is skipped under --no-ship on the plan route" || fail "the Ship row must skip under --no-ship"
printf '%s\n' "$st" | grep -qF "stage ship skipped" \
  && pass "the skip is logged" || fail "the plan route must log the skipped Ship"
has 'never `--auto-merge`' "it never auto-merges"
has "grep -Eiq '^- \\*\\*(Risk:\\*\\* (destructive|high)|Gated:\\*\\* true)' <plan-path>" "build placement reads the plan's risk and gates"
has 'en-conductor: done' "the done marker"
has 'en-conductor: stopped at <stage>: <reason>' "the stopped marker"

# --- en-ship's exit states reach the reader (D113) ---
for state in clean settled-externally escalated blocked; do
  printf '%s\n' "$st" | grep -qF "\`$state\`" && pass "names en-ship's exit state $state" || fail "must name en-ship's exit state $state"
done
has 'attempted no repair' "a blocked ship is not read as a failed stage"

# --- learn rule: ci_environment decides nothing ---
learn=$(section 'Learn rule')
for signal in 'Scope widened:' 'P0 or P1 applied' 'redispatch or fallback' '`needs-decision`'; do
  printf '%s\n' "$learn" | grep -qF -- "$signal" && pass "learn signal: $signal" || fail "the Learn rule must name: $signal"
done

# --- fallback: a rerun never repeats work that landed ---
agents=$(section 'Stage agents')
for clause in 'reruns that stage once in session' 'record `HEAD`' 'git status --porcelain --untracked-files=no' '`gh pr view` finds no PR'; do
  printf '%s\n' "$agents" | grep -qF -- "$clause" && pass "fallback: $clause" || fail "the fallback must state: $clause"
done

# --- resume: the restriction and the code it describes survive ---
res=$(section 'Resume')
printf '%s\n' "$res" | grep -qF 'Flags given with `--resume` are refused' \
  && pass "--resume refuses flags" || fail "--resume must refuse flags"
printf '%s\n' "$res" | grep -qF '`branch` and `head` must equal the current branch and `HEAD`' \
  && pass "--resume stops on a changed HEAD" || fail "--resume must stop on a changed HEAD"

# --- /en-loop is named, never invoked ---
if grep -qiE '(invoke|invoking|dispatch(es|ed)?) (the )?`?/en-loop' "$SK"; then
  fail "/en-loop must never follow an invoke verb" "it stays manual"
else
  pass "/en-loop never follows an invoke verb"
fi
section 'Named, never invoked' | grep -qF '`/en-loop`' \
  && pass "/en-loop is in the named table" || fail "/en-loop must be in the named table"

report
