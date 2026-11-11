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

res() {  # <host> -> "model|source" from the carrier in $R, stderr kept in $W/err
  local out; out=$("$R" --host "$1" --repo-root "$W/repo" --home "$W/home" 2>"$W/err") || { echo "rc=$?"; return; }
  SHIP_MODEL=x; SHIP_MODEL_SOURCE=x; eval "$out"; echo "$SHIP_MODEL|$SHIP_MODEL_SOURCE"
}
eff() {  # <host> -> SHIP_EFFORT from the carrier in $R, stderr kept in $W/err
  local out; out=$("$R" --host "$1" --repo-root "$W/repo" --home "$W/home" 2>"$W/err") || { echo "rc=$?"; return; }
  SHIP_EFFORT=x; eval "$out"; echo "$SHIP_EFFORT"
}

for R in "$REPO_ROOT"/skills/*/scripts/ensemble-ship-model; do
  [ -f "$R" ] || continue
  skill=$(basename "$(dirname "$(dirname "$R")")")

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
  for bad in 'haiku,sonnet' '"*"' 'sonnet*'; do
    clear_cfg; Y "ship_model_claude: $bad"
    assert_eq "|inherit" "$(res claude-code)" "$skill: a list or glob ($bad) is not an alias"
    assert_contains "$(cat "$W/err")" "ignoring ship_model_claude=" "$skill: a list or glob ($bad) is named on stderr"
  done
  id64=$(printf 'a%.0s' $(seq 1 64)); id65="${id64}b"
  clear_cfg; J '{"ship_model_codex":"'"$id64"'"}'
  assert_eq "$id64|config" "$(res codex)" "$skill: a 64-character Codex ID is accepted"
  clear_cfg; J '{"ship_model_codex":"'"$id65"'"}'
  assert_eq "|inherit" "$(res codex)" "$skill: a 65-character Codex ID inherits"
  assert_contains "$(cat "$W/err")" "at most 64 characters" "$skill: the length limit is named on stderr"
  # The repo value is the one read; when it is invalid the run inherits, never
  # falling through to a valid global value the operator did not pick here.
  clear_cfg; Y 'ship_model_claude: gpt-5'; J '{"ship_model_claude":"haiku"}'
  assert_eq "|inherit" "$(res claude-code)" "$skill: an invalid repo value inherits rather than falling through to global"
  # An explicit `inherit` stops at its layer, so a repo can keep the session's
  # model under a global value (PR #147 review: the ship evals leaked the
  # operator's global ship_model_claude without it).
  clear_cfg; J '{"ship_model_claude":"opus","ship_model_codex":"gpt-x"}'; Y 'ship_model_claude: inherit'
  assert_eq "|inherit" "$(res claude-code)" "$skill: a repo inherit overrides a global alias"
  assert_eq "" "$(cat "$W/err")" "$skill: an explicit inherit is not reported as invalid"
  Y 'ship_model_codex: inherit'
  assert_eq "|inherit" "$(res codex)" "$skill: a repo inherit overrides a global Codex ID"
  "$R" --host vim --repo-root "$W/repo" --home "$W/home" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "$skill: an unknown --host exits 2"
  "$R" --repo-root "$W/repo" --home "$W/home" >/dev/null 2>&1; rc=$?
  assert_eq "2" "$rc" "$skill: a missing --host exits 2"

  # --- ship_effort_<host> (EN30 U1): resolved beside the model ---
  clear_cfg; Y 'ship_effort_claude: high'
  assert_eq "high" "$(eff claude-code)" "$skill: repo YAML effort resolves on Claude"
  assert_eq "" "$(cat "$W/err")" "$skill: a valid effort writes nothing to stderr"
  assert_eq "|inherit" "$(res claude-code)" "$skill: an effort alone leaves the model inherited"
  clear_cfg; J '{"ship_effort_codex":"low"}'
  assert_eq "low" "$(eff codex)" "$skill: global JSON effort resolves on Codex"
  clear_cfg; Y 'ship_model_claude: sonnet'; printf 'ship_effort_claude: xhigh\n' >> "$W/repo/.ensemble/config.local.yaml"
  assert_eq "sonnet|config" "$(res claude-code)" "$skill: model and effort set together keep the model"
  assert_eq "xhigh" "$(eff claude-code)" "$skill: model and effort set together keep the effort"
  clear_cfg; J '{"ship_effort_claude":"low"}'; Y 'ship_effort_claude: medium'
  assert_eq "medium" "$(eff claude-code)" "$skill: the repo effort outranks the global one"
  clear_cfg
  assert_eq "" "$(eff claude-code)" "$skill: an unset effort is empty"
  assert_eq "" "$(cat "$W/err")" "$skill: an unset effort writes nothing to stderr"
  J '{"ship_effort_claude":null}'
  assert_eq "" "$(eff claude-code)" "$skill: a JSON null effort is empty"
  clear_cfg; Y 'ship_effort_claude: high'
  assert_eq "" "$(eff codex)" "$skill: the Claude effort key is never read on Codex"
  clear_cfg; J '{"ship_effort_claude":"high"}'; Y 'ship_effort_claude: inherit'
  assert_eq "" "$(eff claude-code)" "$skill: a repo inherit overrides a global effort"
  assert_eq "" "$(cat "$W/err")" "$skill: an explicit effort inherit is not reported as invalid"
  for bad in max HIGH 'high,low' '"*"' turbo; do
    clear_cfg; Y "ship_effort_claude: $bad"
    assert_eq "" "$(eff claude-code)" "$skill: effort $bad is refused"
    assert_contains "$(cat "$W/err")" "ignoring ship_effort_claude=" "$skill: effort $bad is named on stderr"
  done
  clear_cfg; Y 'ship_effort_claude: max'; J '{"ship_effort_claude":"high"}'
  assert_eq "" "$(eff claude-code)" "$skill: an invalid repo effort does not fall through to global"
  clear_cfg; J '{"ship_effort_codex":"high;touch '"$W"'/pwned2"}'
  assert_eq "" "$(eff codex)" "$skill: a malformed effort is refused"
  assert_file_missing "$W/pwned2" "$skill: a malformed effort is never executed"

  # --- integration: the output is safe to eval in a subshell ---
  clear_cfg; Y 'ship_model_claude: opus'; printf 'ship_effort_claude: high\n' >> "$W/repo/.ensemble/config.local.yaml"
  got=$( (eval "$("$R" --host claude-code --repo-root "$W/repo" --home "$W/home")"; printf '%s:%s:%s' "$SHIP_MODEL" "$SHIP_MODEL_SOURCE" "$SHIP_EFFORT") )
  assert_eq "opus:config:high" "$got" "$skill: eval in a subshell sets all three variables"
done

# --- the alias list has a twin in ensemble-agent-model; drift turns red ---
ship_list=$(sed -n 's/^SHIP_CLAUDE_ALIASES="\(.*\)"$/\1/p' "$REPO_ROOT/skills/en-ship/scripts/ensemble-ship-model")
agent_list=$(sed -n 's/^CLAUDE_ALIASES="\(.*\)"$/\1/p' "$REPO_ROOT/skills/en-review/scripts/ensemble-agent-model")
assert_ne "" "$ship_list" "the ship alias list is found"
assert_eq "$agent_list" "$ship_list" "ship and agent alias lists match"

# --- a carrier that lost its reader says so instead of inheriting silently ---
mkdir -p "$W/lone"; cp -p "$REPO_ROOT/skills/en-ship/scripts/ensemble-ship-model" "$W/lone/"
clear_cfg; Y 'ship_model_claude: sonnet'
out=$("$W/lone/ensemble-ship-model" --host claude-code --repo-root "$W/repo" --home "$W/home" 2>"$W/err"); rc=$?
assert_eq "0" "$rc" "a missing reader still exits 0"
assert_contains "$out" "SHIP_MODEL=''" "a missing reader inherits"
assert_contains "$(cat "$W/err")" "is missing or not executable" "a missing reader is named on stderr"
assert_contains "$out" "SHIP_EFFORT=''" "a missing reader leaves the effort empty"

# --- both config examples list the effort keys ---
for ex in "$REPO_ROOT/.ensemble/config.local.example.yaml" "$REPO_ROOT/skills/en-setup/references/templates/config-local-example.yaml"; do
  for k in ship_effort_claude ship_effort_codex; do
    if grep -q "^# $k:" "$ex"; then pass "${ex#$REPO_ROOT/} lists $k"; else fail "${ex#$REPO_ROOT/} lists $k" "no '# $k:' line"; fi
  done
done
for k in ship_effort_claude ship_effort_codex; do
  if grep -q "^  \"$k\": null" "$REPO_ROOT/setup"; then pass "setup defaults list $k"; else fail "setup defaults list $k" "missing in config_defaults"; fi
done

report
