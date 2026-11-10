#!/usr/bin/env bash
# tests/lint/ensemble-ship-model.test.sh
#
# EN28 U1. One script answers "which model does /en-ship run on, on this host,
# for this operator": ship_model_claude (an alias) or ship_model_codex (an
# operator ID), repo layer before global, unset meaning inherit. An invalid
# value says so on stderr and inherits, so nothing unvalidated reaches a
# dispatch. Two byte-identical copies, en-ship and en-conductor; parity pins
# them, this test exercises both.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-ship-model"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM HUP
mkdir -p "$W/repo/.ensemble" "$W/home/.ensemble"
J() { printf '%s\n' "$1" > "$W/home/.ensemble/config.json"; }
Y() { printf '%s\n' "$1" > "$W/repo/.ensemble/config.local.yaml"; }
clear_cfg() { rm -f "$W/home/.ensemble/config.json" "$W/repo/.ensemble/config.local.yaml"; }

# The carriers that must exist; every other carrier found is exercised too.
for skill in en-ship en-conductor; do
  assert_file_exists "$REPO_ROOT/skills/$skill/scripts/ensemble-ship-model" "$skill carries ensemble-ship-model"
done

for R in "$REPO_ROOT"/skills/*/scripts/ensemble-ship-model; do
  [ -f "$R" ] || continue
  skill=$(basename "$(dirname "$(dirname "$R")")")
  res() {  # <host> -> "model|source", stderr kept in $W/err
    local out; out=$("$R" --host "$1" --repo-root "$W/repo" --home "$W/home" 2>"$W/err") || { echo "rc=$?"; return; }
    SHIP_MODEL=x; SHIP_MODEL_SOURCE=x; eval "$out"; echo "$SHIP_MODEL|$SHIP_MODEL_SOURCE"
  }

  # --- happy paths, each layer ---
  clear_cfg; Y 'ship_model_claude: sonnet'
  assert_eq "sonnet|config" "$(res claude-code)" "$skill: repo YAML alias resolves on Claude"
  assert_eq "" "$(cat "$W/err")" "$skill: a valid value writes nothing to stderr"
  clear_cfg; J '{"ship_model_codex":"gpt-x.1-mini"}'
  assert_eq "gpt-x.1-mini|config" "$(res codex)" "$skill: global JSON Codex ID resolves on Codex"

  # --- edge cases ---
  clear_cfg; J '{"ship_model_claude":"haiku"}'; Y 'ship_model_claude: sonnet'
  assert_eq "sonnet|config" "$(res claude-code)" "$skill: the repo layer outranks the global one"
  clear_cfg
  assert_eq "|inherit" "$(res claude-code)" "$skill: unset key inherits"
  assert_eq "" "$(cat "$W/err")" "$skill: unset writes nothing to stderr"
  J '{"ship_model_claude":null}'
  assert_eq "|inherit" "$(res claude-code)" "$skill: a JSON null inherits"
  clear_cfg; Y 'ship_model_claude: sonnet'
  assert_eq "|inherit" "$(res codex)" "$skill: the Claude key is never read on Codex"

  # --- error paths ---
  clear_cfg; Y 'ship_model_claude: gpt-5'
  assert_eq "|inherit" "$(res claude-code)" "$skill: an unknown alias inherits"
  assert_contains "$(cat "$W/err")" "ensemble-ship-model: ignoring ship_model_claude=gpt-5" "$skill: an unknown alias is named on stderr"
  clear_cfg; J '{"ship_model_codex":"a b;touch '"$W"'/pwned"}'
  assert_eq "|inherit" "$(res codex)" "$skill: a malformed Codex ID inherits"
  assert_contains "$(cat "$W/err")" "ignoring ship_model_codex=" "$skill: a malformed Codex ID is named on stderr"
  assert_file_missing "$W/pwned" "$skill: a malformed Codex ID is never executed"
  "$R" --host vim --repo-root "$W/repo" --home "$W/home" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "$skill: an unknown --host exits 2"
  "$R" --repo-root "$W/repo" --home "$W/home" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "$skill: a missing --host exits 2"

  # --- integration: the output is safe to eval in a subshell ---
  clear_cfg; Y 'ship_model_claude: opus'
  got=$( (eval "$("$R" --host claude-code --repo-root "$W/repo" --home "$W/home")"; printf '%s:%s' "$SHIP_MODEL" "$SHIP_MODEL_SOURCE") )
  assert_eq "opus:config" "$got" "$skill: eval in a subshell sets both variables"
done

report
