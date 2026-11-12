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
order=$(printf '%s\n' "$qp" | grep -E '^[123]\. ' | cut -c1-60)
first=$(printf '%s\n' "$order" | sed -n 1p); second=$(printf '%s\n' "$order" | sed -n 2p); third=$(printf '%s\n' "$order" | sed -n 3p)
case "$first"  in *'running or reading'*) pass "first, answer by running or reading" ;; *) fail "branch 1 must answer by running or reading" "$first" ;; esac
case "$second" in *'irreversible action, ask'*) pass "second, ask only an irreversible action" ;; *) fail "branch 2 must ask only an irreversible action" "$second" ;; esac
case "$third"  in *'Decide everything else'*) pass "third, decide the rest" ;; *) fail "branch 3 must decide the rest" "$third" ;; esac
printf '%s\n' "$qp" | grep -E '^3\. ' | grep -qF 'product and preference calls included' \
  && pass "a reversible product call is decided, not asked" || fail "branch 3 must cover product and preference calls"
assert_contains "$qp" "log decision <stage> call" "a decided call is logged"
has 'the calls you made without asking under their own heading' "the report lists the calls made without asking"
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

# --- a Linear identifier routes on the issue's state (D147) ---
RL="$REPO_ROOT/skills/en-conductor/references/route-linear-issue.md"
assert_file_exists "$RL" "the Linear routing reference exists"
# Step 3's first match wins, so the identifier bullet must sit before the text rules.
route_bullets=$(section Process | grep -E '^   - ' | cut -c1-40)
id_at=$(printf '%s\n' "$route_bullets" | grep -n 'A Linear issue identifier' | cut -d: -f1)
explore_at=$(printf '%s\n' "$route_bullets" | grep -n 'Words asking to explore' | cut -d: -f1)
plan_at=$(printf '%s\n' "$route_bullets" | grep -n '`--plan <path>`' | cut -d: -f1)
[ -n "$id_at" ] && [ -n "$explore_at" ] && [ -n "$plan_at" ] && [ "$plan_at" -lt "$id_at" ] && [ "$id_at" -lt "$explore_at" ] \
  && pass "step 3 tests an identifier after --plan and before the text rules" \
  || fail "step 3's identifier bullet must sit between --plan and the explore rule" "plan=$plan_at id=$id_at explore=$explore_at"
section Process | grep -E '^   - A Linear issue identifier' | grep -qF '`references/route-linear-issue.md`' \
  && pass "the identifier bullet hands off to the routing reference" || fail "the identifier bullet must name references/route-linear-issue.md"
rl=$(cat "$RL")
assert_contains "$rl" 'plan_store --allowed local,linear --default local --strict' "the store is read fail-closed"
assert_contains "$rl" 'only the fix route can take an identifier' "under plan_store: local only /en-fix takes an identifier"
assert_contains "$rl" 'So does an `en-fix: needs-plan clean` return' "under local, a needs-plan return stops instead of reaching /en-plan"
assert_contains "$(section 'Fix outcomes')" 'An identifier under `plan_store: local` stops instead' "the Fix outcomes table carries that stop"
# The identifier shape is the callees': a looser one routes what they refuse.
id_re='^[A-Z][A-Z0-9]*-[0-9]+$'
assert_contains "$rl" "\`$id_re\`" "the identifier shape is stated"
grep -qF -- "\`$id_re\`" "$REPO_ROOT/skills/en-plan/references/linear-intake.md" \
  && pass "it matches en-plan's identifier shape" || fail "the identifier shape must match en-plan's linear-intake.md"
# The table's order is its meaning: a shipped or done issue stops before anything
# builds, an interrupted build resumes in session, and a published plan is built
# before a linked design is planned again.
rows=$(printf '%s\n' "$rl" | grep -oE '^\| (state completed|a published plan, parent In Review|a published plan, parent In Progress|a published plan \||a linked design|otherwise)')
expected=$(printf '%s\n' '| state completed' '| a published plan, parent In Review' '| a published plan, parent In Progress' '| a published plan |' '| a linked design' '| otherwise')
[ "$rows" = "$expected" ] && pass "routing rows: done, In Review, In Progress, published plan, linked design, then text" \
  || fail "the routing rows are out of order or missing" "$rows"
# /en-build sets In Review before QA and Ship, so In Review alone never means a PR exists.
printf '%s\n' "$rl" | grep -E '^\| a published plan, parent In Review' | grep -qF '/en-qa` then `/en-ship`' \
  && pass "In Review without an open PR names the remaining QA and Ship steps" || fail "the In Review row must send an unshipped build to /en-qa then /en-ship"
assert_contains "$rl" 'startswith("<ident, lowercase>-")' "an open PR is found by the identifier-named branch"
printf '%s\n' "$rl" | grep -E '^\| a published plan, parent In Progress' | grep -qF 'in session' \
  && pass "an interrupted build resumes in session, where its reconcile can ask" || fail "the In Progress row must build in session"
# A published plan is the Verification Contract, spelled as en-build's format writes it.
assert_contains "$rl" 'ends with a `## Verification Contract` heading' "a published plan is detected by its Verification Contract"
grep -qF -- '`## Verification Contract` heading' "$REPO_ROOT/skills/en-build/references/linear-plan-format.md" \
  && pass "en-build's plan format still writes that heading" || fail "linear-plan-format.md no longer names the ## Verification Contract heading"
assert_contains "$rl" 'Sub-issues alone do not' "sub-issues alone never count as a plan"
assert_contains "$rl" "grep -lx 'linear_issue: <IDENT>' docs/designs/*.md" "a design is found by its exact frontmatter key"
assert_contains "$rl" "log \`stage plan skipped '<IDENT>'\`" "a skipped Plan stage logs the identifier Resume reads"
# The Plan stage must not cut a <plan_id>-<slug> branch: the PR would not carry the identifier.
assert_contains "$rl" '`/en-plan --orchestrated --branch-on-default no-commit <IDENT>`' "the Plan stage passes no-commit for an identifier"
assert_not_contains "$rl" '--branch-on-default y <IDENT>' "and never y"
grep -qE '^\| `no-commit` \| Stay on the current branch' "$REPO_ROOT/skills/en-plan/references/plan-default-branch-checkpoint.md" \
  && pass "en-plan's no-commit stays on the current branch" || fail "en-plan's no-commit handler must stay on the current branch"
assert_contains "$rl" 'no file under `docs/plans/active/`' "the Plan gate waits for the verified archive"
for call in '/en-build <IDENT> --orchestrated' '/en-brainstorm <IDENT>' '/en-fix <IDENT> --orchestrated'; do
  assert_contains "$rl" "\`$call\`" "each stage receives the identifier: $call"
done
# Linear rewrites `- ` to `* ` and a listing can truncate, so placement reads each
# sub-issue in full, with both markers.
assert_contains "$rl" '`get_issue` each one' "placement reads each sub-issue in full"
assert_contains "$rl" 'with `[-*]` in place of the leading `-`' "placement reads Linear's rewritten list marker"
case "$placement" in '^- '*) pass "the placement grep starts with the marker the reference swaps" ;; *) fail "the placement grep no longer starts with '^- '" "$placement" ;; esac
assert_contains "$(cat "$REPO_ROOT/skills/en-plan/CONTRACT.md")" '`/en-plan <IDENT> --orchestrated --branch-on-default no-commit`' "en-plan's contract accepts the identifier form"
assert_contains "$(cat "$REPO_ROOT/skills/en-build/CONTRACT.md")" '`/en-build <IDENT> --orchestrated`' "en-build's contract accepts the identifier form"
assert_contains "$(cat "$REPO_ROOT/skills/en-brainstorm/CONTRACT.md")" '`/en-brainstorm <IDENT>`' "en-brainstorm's contract accepts the identifier form"

# --- a redispatch keeps the run's restrictions, and the question policy answers ---
assert_contains "$(section 'Fix outcomes')" 'Redispatch with the original flags' "a redispatch keeps --no-ship"
assert_contains "$(section 'Fix outcomes')" 'Classify it under `## Question policy`' "needs-decision goes through the question policy"
assert_contains "$(section 'Fix outcomes')" "Log \`decision fix redispatch" "a Fix redispatch logs the row that closes the returned agent's run"

# --- Ship's model (EN28 U3, D144): one hop, a question stops, Fix passes none ---
printf '%s\n' "$st" | grep -E '^\| Ship \|' | grep -qF '`/en-ship --in-agent` as an agent' \
  && pass "the Ship agent is invoked already placed" || fail "the Ship row must invoke /en-ship --in-agent as an agent"
has 'scripts/ensemble-ship-model" --host "$HOST"' "the Ship stage resolves its model through ensemble-ship-model"
has "Ship's agent is dispatched with \`model\` set to \`SHIP_MODEL\`" "the Ship agent carries the resolved model"
has '`effort` set to `SHIP_EFFORT` (`reasoning_effort` on Codex)' "the Ship agent carries the resolved effort (EN30, D145)"
has 'Each is passed only when it is non-empty, so an effort-only config reaches the agent with no `model`' "each Ship argument is passed only when set"
assert_not_contains "$(cat "$SK")" 'and with no `model` otherwise' "the unconditional model omission is gone"
has 'Its in-session fallback rerun keeps `--in-agent`' "the fallback rerun does not dispatch again"
has '`en-ship: needs-input <question>`, a contract field and not a fallback trigger' "a Ship question is a stop, not a fallback"
has 'naming the question and `/en-ship` to run in session' "a Ship question names /en-ship for the user"
has 'The Fix stage passes neither' "the Fix stage passes no model or effort; en-ship places itself"

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
