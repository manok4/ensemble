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
assert_contains "$qp" 'en-conductor: stopped at <stage>: <question>' "with no question tool, a reserved call ends the run"

# --- stages, in order ---
st=$(section 'Stages')
lines=""
for s in Plan Build QA Learn Ship; do
  lines="$lines $(printf '%s\n' "$st" | grep -n "^| $s |" | head -1 | cut -d: -f1)"
done
[ "$(printf '%s\n' $lines | grep -c .)" -eq 5 ] && [ "$(printf '%s\n' $lines | sort -n | tr '\n' ' ')" = "$(printf '%s\n' $lines | tr '\n' ' ')" ] \
  && pass "stages ordered plan, build, qa, learn, ship" || fail "stages must run plan, build, qa, learn, ship" "$lines"

printf '%s\n' "$st" | grep -E '^\| QA \|' | grep -qF 'only when `needs_browser` is true' \
  && pass "QA runs only when the diff needs a browser" || fail "the QA row must gate on needs_browser"
printf '%s\n' "$st" | grep -E '^\| Ship \|' | grep -qF 'skipped under `--no-ship` or `local_only`' \
  && pass "Ship is skipped under --no-ship on the plan route" || fail "the Ship row must skip under --no-ship"
assert_contains "$st" 'stage ship skipped' "the skip is logged"
has 'never `--auto-merge`' "it never auto-merges"
has "grep -Eiq '^- \\*\\*(Risk:\\*\\* (destructive|high)|Gated:\\*\\* true)' <plan-path>" "build placement reads the plan's risk and gates"
has 'en-conductor: done' "the done marker"
has 'ensemble-conductor-trail" start --metrics-ledger "$(' "the trail names the run's ledger at start"
has 'ensemble-run-metrics" start --skill en-conductor)"' "a run opens under its own name, inside that command"
has 'resume --metrics-ledger' "a resumed run names its own ledger too"
has 'ensemble-run-metrics" finish '"'"'<that path>'"'" "the run closes on its own ledger"
has 'on the fix route the `en-fix:` line verbatim' "the report quotes the fix outcome"
has 'en-conductor: stopped at <stage>: <reason>' "the stopped marker"

# --- en-ship's exit states reach the reader (D113) ---
for state in clean not-watched settled-externally escalated blocked; do
  assert_contains "$st" "\`$state\`" "names en-ship's exit state $state"
done
has 'attempted no repair' "a blocked ship is not read as a failed stage"

# --- learn rule: ci_environment decides nothing ---
learn=$(section 'Learn rule')
for signal in 'Scope widened:' 'P0 or P1 applied' 'redispatch or fallback' '`needs-decision`'; do
  assert_contains "$learn" "$signal" "learn signal: $signal"
done

# --- build placement really matches what the plan template writes ---
placement=$(grep -oE "grep -Eiq '[^']+'" "$SK" | head -1 | sed -E "s/^grep -Eiq '//; s/'$//")
for line in '- **Risk:** high' '- **Risk:** destructive' '- **Gated:** true'; do
  printf '%s\n' "$line" | grep -Eiq "$placement" && pass "builds in session on: $line" || fail "must build in session on: $line"
done
for line in '- **Risk:** medium' '- **Gated:** false'; do
  printf '%s\n' "$line" | grep -Eiq "$placement" && fail "must not force a session build on: $line" || pass "no session build on: $line"
done
grep -qE '^- \*\*Risk:\*\* ' "$REPO_ROOT/skills/en-plan/references/templates/plan-template.md" \
  && grep -qE '^- \*\*Gated:\*\* ' "$REPO_ROOT/skills/en-plan/references/templates/plan-template.md" \
  && pass "the plan template still writes those fields" || fail "the plan template no longer writes - **Risk:** and - **Gated:**"

# --- a redispatch keeps the run's restrictions, and only the user answers ---
assert_contains "$(section 'Fix outcomes')" 'Redispatch with the original flags' "a redispatch keeps --no-ship"
assert_contains "$(section 'Fix outcomes')" 'Never decide it yourself' "the conductor never answers needs-decision itself"
assert_contains "$(section 'Fix outcomes')" "Log \`decision fix redispatch" "a Fix redispatch logs the row that closes the returned agent's run"

# --- fallback: a rerun never repeats work that landed ---
agents=$(section 'Stage agents')
for clause in 'reruns that stage once in session' 'record `HEAD`' 'git status --porcelain --untracked-files=no' '`gh pr view` finds no PR'; do
  assert_contains "$agents" "$clause" "fallback: $clause"
done

# --- resume: the restriction and the code it describes survive ---
res=$(section 'Resume')
assert_contains "$res" 'Flags given with `--resume` are refused' "--resume refuses flags"
assert_contains "$res" '`branch` and `head` must equal the current branch and `HEAD`' "--resume stops on a changed HEAD after Build"
assert_contains "$res" 'its `head` must be an ancestor of `HEAD`' "--resume continues a build that committed after Plan"
assert_contains "$res" 'would re-triage committed work' "--resume never starts a fresh /en-fix on committed work"

assert_contains "$res" 'never read a missing row as no flags' "--resume stops when the flags row is missing"

# --- free text cannot reach the shell ---
has "with each \`'\` written as \`'\\''\`" "free text goes in single quotes"

# --- /en-loop is named, never invoked ---
if grep -qiE '(invoke|invoking|dispatch(es|ed)?) (the )?`?/en-loop' "$SK"; then
  fail "/en-loop must never follow an invoke verb" "it stays manual"
else
  pass "/en-loop never follows an invoke verb"
fi
assert_contains "$(section 'Named, never invoked')" '`/en-loop`' "/en-loop is in the named table"

report
