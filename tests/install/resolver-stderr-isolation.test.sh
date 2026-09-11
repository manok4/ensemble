#!/usr/bin/env bash
# tests/install/resolver-stderr-isolation.test.sh
#
# `ensemble-agent-model` is fail-soft by contract: `KEY='value'` lines on
# stdout, any diagnostic on stderr, exit 0 either way. setup captured the Codex
# call with `2>&1` and eval'd the result, so a warning like
#
#   config.json is not valid JSON (jq: parse error: ...)
#
# was parsed as shell and died on the `(`. A syntax error aborts the WHOLE eval,
# so the valid assignments that followed on stdout were thrown away too, and
# every agent rendered `model: inherit, effort: inherit` — which reads as a
# resolution rather than a lost one. The Claude call had the opposite bug,
# `2>/dev/null`, so the same config degraded it in total silence.
#
# Reported from a real machine whose ~/.ensemble/config.json had one malformed
# value; six `syntax error near unexpected token '('` lines and no mention of
# the actual cause.
#
# Guarded here:
#
#   STDERR IS NEVER EVAL'D     a diagnostic cannot become shell.
#   STDERR IS NEVER SWALLOWED  both hosts report a broken config.
#   SAID ONCE, NOT PER AGENT   it is the same sentence six times over.
#   A GOOD RESOLUTION SURVIVES a warning must not cost the model and effort
#                              that were sitting on stdout, valid.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="setup never evals the resolver's stderr"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
SRC="$WORK/src"; mkdir -p "$SRC"
cp "$REPO_ROOT/setup" "$SRC/setup"; cp -R "$REPO_ROOT/skills" "$SRC/skills"

mkhome() {  # <name> <config-json-body> -> prints the home path
  local h="$WORK/$1"
  mkdir -p "$h/.ensemble" "$h/.codex" "$h/.claude"
  printf '%s\n' "$2" > "$h/.ensemble/config.json"
  printf '%s\n' "$h"
}
run_setup() {  # <home> <host>
  ( cd "$WORK" && HOME="$1" bash "$SRC/setup" --copy --host "$2" ) >"$WORK/out" 2>&1 || true
  cat "$WORK/out"
}

# A config that parses as far as line 9 and then does not: the shape reported.
BROKEN='{
  "peer_model_claude": "opus",
  "peer_model_codex": "gpt-5.6-sol",
  "peer_effort_codex": "high",
  "agent_model_codex_retrieval": "gpt-5.6-luna",
  "agent_effort_codex_retrieval": "high",
  "agent_effort_codex_evidence": "medium",
  "review_confidence_threshold": 7,
  "broken": 00x7
}'
VALID='{
  "agent_model_codex_retrieval": "gpt-5.6-luna",
  "agent_effort_codex_retrieval": "high"
}'

# --- a diagnostic never reaches the shell -----------------------------------
out=$(run_setup "$(mkhome broken-codex "$BROKEN")" codex)
assert_not_contains "$out" "syntax error" "a resolver diagnostic is never eval'd as shell"
assert_not_contains "$out" "unexpected token" "so no unexpected-token error can appear"

# --- and is never swallowed either, on either host --------------------------
assert_contains "$out" "not valid JSON" "a broken global config is reported on the Codex path"
n=$(printf '%s\n' "$out" | grep -c "not valid JSON" || true)
assert_eq "1" "$n" "and reported once, not once per agent"

out=$(run_setup "$(mkhome broken-claude "$BROKEN")" claude)
assert_contains "$out" "not valid JSON" \
  "the Claude path reports it too; 2>/dev/null degraded in silence"

# --- a valid config still resolves, which is what the eval was for -----------
out=$(run_setup "$(mkhome ok-codex "$VALID")" codex)
assert_contains "$out" "model: gpt-5.6-luna" "a valid config still resolves the model"
assert_contains "$out" "effort: high" "and the effort"
assert_not_contains "$out" "not valid JSON" "with nothing to warn about"

# --- the shape that caused it cannot come back ------------------------------
# Both call sites go through one runner, because they were wrong in opposite
# directions and one shape is what stops that recurring.
code=$(grep -vE '^\s*#' "$REPO_ROOT/setup")
printf '%s' "$code" | grep -qE 'ensemble-agent-model.*2>&1' \
  && fail "a resolver call folds stderr into stdout again" \
          "that stream is eval'd; a diagnostic in it becomes shell" \
  || pass "no resolver call merges stderr into the stream setup evals"
printf '%s' "$code" | grep -qE '"\$resolver".*2>/dev/null' \
  && fail "a resolver call discards stderr again" \
          "a broken config then degrades the install in silence" \
  || pass "no resolver call discards stderr outright"

report
