#!/usr/bin/env bash
# tests/lint/ensemble-agent-model.test.sh
#
# EN16 U3. One script answers "which model and effort does agent X run on host
# Y for this operator". The order is override, tier, frontmatter, inherit; the
# tier is derived from the agent's `model:` alias; values are validated per
# host and an invalid one falls through rather than reaching a dispatch. The
# 2026-09-06 run spent $67 because no such answer existed and a fallback
# dispatch inherited the session model.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-agent-model"

R="$REPO_ROOT/skills/en-review/scripts/ensemble-agent-model"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT INT TERM HUP
mkdir -p "$W/repo/.ensemble" "$W/home/.ensemble" "$W/agents"
printf -- '---\nname: repo-research\ndescription: "x"\nmodel: sonnet\n---\n# body\n' > "$W/agents/repo-research.md"
printf -- '---\nname: web-research\ndescription: "x"\nmodel: sonnet\n---\n# body\n'  > "$W/agents/web-research.md"
printf -- '---\nname: odd-agent\ndescription: "x"\nmodel: fable\n---\n# body\n'      > "$W/agents/odd-agent.md"

res() {  # <agent> <host> [extra flags] -> eval and echo "tier|model|effort|source"
  local a="$1" h="$2"; shift 2
  local out; out=$("$R" --agent "$a" --host "$h" --agent-file "$W/agents/$a.md" --repo-root "$W/repo" --home "$W/home" "$@" 2>"$W/err") || { echo "rc=$?"; return; }
  eval "$out"; echo "$AGENT_TIER|$AGENT_MODEL|$AGENT_EFFORT|$AGENT_MODEL_SOURCE"
}
J() { printf '%s\n' "$1" > "$W/home/.ensemble/config.json"; }
Y() { printf '%s\n' "$1" > "$W/repo/.ensemble/config.local.yaml"; }
clear_cfg() { rm -f "$W/home/.ensemble/config.json" "$W/repo/.ensemble/config.local.yaml"; }

# --- no config: frontmatter on Claude, inherit on Codex ---
clear_cfg
assert_eq "evidence|sonnet||frontmatter" "$(res repo-research claude-code)" "no config, Claude: the frontmatter alias, source frontmatter"
assert_eq "evidence|||inherit"           "$(res repo-research codex)"       "no config, Codex: inherit (a Claude alias is never emitted on Codex)"

# --- tier and override, across layers, hyphenated agent name ---
J '{"agent_model_claude_evidence":"opus"}'
assert_eq "evidence|opus||tier" "$(res repo-research claude-code)" "global tier value resolves, source tier"
Y 'agent_model_override_web-research_claude: haiku'
assert_eq "evidence|haiku||override" "$(res web-research claude-code)" "repo per-agent override beats the tier (hyphenated key in YAML)"
assert_eq "evidence|opus||tier"      "$(res repo-research claude-code)" "the override is per agent; a sibling still gets the tier value"
clear_cfg
J '{"agent_model_override_web-research_claude":"haiku"}'
assert_eq "evidence|haiku||override" "$(res web-research claude-code)" "hyphenated override key works in JSON too"

# --- Codex: model and effort from tier keys, overrides on top ---
clear_cfg
J '{"agent_model_codex_evidence":"gpt-x","agent_effort_codex_evidence":"medium"}'
assert_eq "evidence|gpt-x|medium|tier" "$(res repo-research codex)" "Codex tier model and effort"
Y 'agent_effort_override_repo-research_codex: high'
assert_eq "evidence|gpt-x|high|tier" "$(res repo-research codex)" "Codex effort override applies while the model still comes from the tier"

# --- an alias outside the table: no tier, overrides still honoured ---
clear_cfg
J '{"agent_model_claude_evidence":"opus"}'
assert_eq "|fable||frontmatter" "$(res odd-agent claude-code)" "fable: no tier, tier keys skipped, frontmatter returned"
J '{"agent_model_override_odd-agent_claude":"opus"}'
assert_eq "|opus||override" "$(res odd-agent claude-code)" "fable: a per-agent override still applies"

# --- a frontmatter alias outside the Agent tool's set never reaches a dispatch (security) ---
printf -- '---\nname: hostile\ndescription: "x"\nmodel: sonnet; touch /tmp/PWNED\n---\n# body\n' > "$W/agents/hostile.md"
clear_cfg
assert_eq "|||inherit" "$(res hostile claude-code)" "a frontmatter alias outside CLAUDE_ALIASES resolves to inherit, not to the dispatch"

# --- --global-only skips the repo layer ---
clear_cfg
Y 'agent_model_claude_evidence: opus'
J '{"agent_model_claude_evidence":"haiku"}'
assert_eq "evidence|opus||tier"  "$(res repo-research claude-code)"               "default: repo layer wins"
assert_eq "evidence|haiku||tier" "$(res repo-research claude-code --global-only)" "--global-only: the global layer alone"

# --- validation per host: invalid values fall through ---
clear_cfg
J '{"agent_model_override_repo-research_claude":"gpt-x","agent_model_claude_evidence":"opus"}'
assert_eq "evidence|opus||tier" "$(res repo-research claude-code)" "a non-alias Claude override is rejected and the tier value is used"
J '{"agent_model_claude_evidence":"opus 4"}'
assert_eq "evidence|sonnet||frontmatter" "$(res repo-research claude-code)" "a Claude value with a space is treated as unset"
J '{"agent_effort_codex_evidence":"turbo","agent_model_codex_evidence":"gpt x"}'
assert_eq "evidence|||inherit" "$(res repo-research codex)" "invalid Codex model and effort are both treated as unset"
J '{"agent_model_codex_evidence":"gpt-x"}'
assert_eq "evidence|gpt-x||tier" "$(res repo-research codex)" "a valid Codex ID with no effort key: model set, effort empty"

# --- errors and fail-soft ---
out=$("$R" --agent nope --host claude-code --agent-file "$W/agents/missing.md" 2>"$W/err"); rc=$?
assert_exit_code 2 "$rc" "a missing --agent-file exits 2"
grep -q "cannot read --agent-file" "$W/err" && pass "the missing-file error names the flag" || fail "the missing-file error names the flag" "$(cat "$W/err")"
out=$("$R" --agent repo-research --host gemini --agent-file "$W/agents/repo-research.md" 2>/dev/null); rc=$?
assert_exit_code 2 "$rc" "an unknown --host exits 2"
J '{"agent_model_claude_evidence": opus}'
assert_eq "evidence|sonnet||frontmatter" "$(res repo-research claude-code)" "malformed global JSON: resolution continues from the frontmatter"
assert_eq "1" "$(grep -c "is not valid JSON" "$W/err")" "malformed global JSON warns exactly once per resolution"
clear_cfg
res repo-research claude-code >/dev/null
assert_eq "" "$(cat "$W/err")" "a clean resolution prints nothing to stderr"

# --- check-health --models lists every agent on both hosts ---
lines=$("$REPO_ROOT/scripts/check-health" --models 2>/dev/null | tail -n +2)
names=$(ls "$REPO_ROOT"/skills/*/agents/*.md | xargs -n1 basename | sed 's/\.md$//' | sort -u | wc -l | tr -d ' ')
assert_eq "$((names * 2))" "$(printf '%s\n' "$lines" | grep -c .)" "check-health --models prints one line per agent per host"
printf '%s\n' "$lines" | awk '$2 == "?" || $2 == "" {bad=1} END {exit bad}' \
  && pass "every bundled agent resolves to a non-empty tier" \
  || fail "every bundled agent resolves to a non-empty tier" "$(printf '%s\n' "$lines" | awk '$2 == "?"')"

report
