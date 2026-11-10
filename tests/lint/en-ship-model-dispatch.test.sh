#!/usr/bin/env bash
# tests/lint/en-ship-model-dispatch.test.sh
#
# EN28 U2 (D144). /en-ship reruns itself in a subagent on ship_model_<host>,
# and stays in session whenever it may need the user. Each pin below is the
# only place its rule is stated; deleting the clause turns it red (checked by
# hand when each was written).

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-ship model dispatch"

SKILL="$REPO_ROOT/skills/en-ship/SKILL.md"
CONTRACT="$REPO_ROOT/skills/en-ship/CONTRACT.md"
REF="$REPO_ROOT/skills/en-ship/references/model-dispatch.md"

has() {  # <file> <fixed string> <label>
  if grep -qF -- "$2" "$1"; then pass "$3"; else fail "$3" "missing in ${1#$REPO_ROOT/}: $2"; fi
}

# --- the step: resolution and the three stay-in-session conditions ---
has "$SKILL" '2a. **Model placement.**'                                     "en-ship has a Model placement step"
has "$SKILL" 'scripts/ensemble-ship-model" --host "$HOST"'                 "the step resolves the model through ensemble-ship-model"
has "$SKILL" '`SHIP_MODEL` is empty or `--in-agent` was passed'             "unset key or --in-agent stays in session"
has "$SKILL" '`--interactive` was passed'                                   "--interactive stays in session"
has "$SKILL" "the branch is the repo's default branch"                      "the default branch stays in session"
if grep -qF '`HOST` is not `claude-code`' "$SKILL"; then fail "Codex dispatch is verified (EN28 U4): no host stays in session by host alone"; else pass "Codex dispatch is verified (EN28 U4): no host stays in session by host alone"; fi
has "$SKILL" 'per `references/model-dispatch.md`'                           "the step points at its reference"
has "$SKILL" '| `--in-agent` |'                                             "the flag table lists --in-agent"

# --- order: placement after the recursion guard, before the ledger opens ---
line() { grep -nF -- "$1" "$SKILL" | head -1 | cut -d: -f1; }
g=$(line '2. **Recursion guard.**'); m=$(line '2a. **Model placement.**'); l=$(line '2b. **Start the run ledger.**')
if [ -n "$g" ] && [ -n "$m" ] && [ -n "$l" ] && [ "$g" -lt "$m" ] && [ "$m" -lt "$l" ]; then
  pass "Model placement sits between the recursion guard and the run ledger"
else
  fail "Model placement sits between the recursion guard and the run ledger" "lines guard=$g placement=$m ledger=$l"
fi

# --- the reference: dispatch on both hosts, return, question, fallback ---
has "$REF" 'model: $SHIP_MODEL'                                             "the dispatch passes the resolved model"
has "$REF" 'followed by `/en-ship --in-agent`'                              "the child is invoked with --in-agent"
has "$REF" 'ends your turn with the last line `en-ship: needs-input <question>`' "the brief names the question line"
has "$REF" 'continue this run in session from **Resolve context**'          "a needs-input continuation re-reads branch and PR"
has "$REF" 'run as if `--in-agent` were passed'                             "a needs-input continuation never dispatches again"
has "$REF" '`HEAD` matches the recorded value'                              "fallback: HEAD unchanged"
has "$REF" 'git status --porcelain --untracked-files=no'                    "fallback: tracked tree clean"
has "$REF" 'gh pr list --head <branch> --state open'                        "fallback: no PR for the branch"
has "$REF" 'one `spawn_agent` call with `model: $SHIP_MODEL` and'            "Codex dispatches through spawn_agent with the resolved model"
has "$REF" '`fork_turns: "none"`, then wait for it'                          "the Codex child starts fresh, not from the parent's history"
has "$REF" "this Codex CLI's spawn_agent takes no model"                     "a CLI without a model parameter says so and ships in session"
has "$REF" 'one Agent call, `subagent_type: general-purpose`, with'         "Claude Code dispatches through the Agent tool"

# --- the contract callers read ---
has "$CONTRACT" '| `--in-agent` |'                                          "CONTRACT lists --in-agent"
has "$CONTRACT" '`en-ship: needs-input <question>`'                         "CONTRACT names the needs-input return"

report
