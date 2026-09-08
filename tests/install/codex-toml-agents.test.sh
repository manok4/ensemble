#!/usr/bin/env bash
# tests/install/codex-toml-agents.test.sh
#
# EN16 U5. Codex reads custom agents from ~/.codex/agents/*.toml with name,
# description and developer_instructions; setup used to symlink markdown there,
# which Codex never read, so a Codex host had no Ensemble agents at all. setup
# now renders one TOML per agent, with model and model_reasoning_effort filled
# from the resolver against the GLOBAL config only. Every property below is one
# a broken render would violate silently: Codex does not report a file it
# could not parse.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="setup renders Codex agents as TOML"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# A private copy of the source tree, so fixtures can be added without touching
# the repo. setup resolves everything from its own directory.
SRC="$WORK/src"; mkdir -p "$SRC"
cp "$REPO_ROOT/setup" "$SRC/setup"; cp -R "$REPO_ROOT/skills" "$SRC/skills"
run_setup() {  # <home> [flags...]
  local home="$1"; shift
  mkdir -p "$home/.codex" "$home/.claude"
  # not --quiet: the per-agent "rendered ..." lines are part of what is asserted
  ( cd "$WORK" && HOME="$home" bash "$SRC/setup" --copy "$@" ) >"$WORK/out" 2>&1
}
canonical=$(ls "$REPO_ROOT"/skills/*/agents/*.md | xargs -n1 basename | sed 's/\.md$//' | sort -u)
have_tomllib=false; python3 -c 'import tomllib' 2>/dev/null && have_tomllib=true
toml_get() {  # <file> <key> -> decoded value (tomllib) ; empty when unavailable
  $have_tomllib || { echo ""; return; }
  python3 - "$1" "$2" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f: d = tomllib.load(f)
print(d.get(sys.argv[2], ""), end="")
PY
}

# --- 1. no config: one TOML per agent, no markdown, required keys, no model ---
H1="$WORK/h1"; run_setup "$H1" --host codex; rc=$?
assert_exit_code 0 "$rc" "setup --host codex exits 0 ($(tail -1 "$WORK/out"))"
rendered=$(ls "$H1/.codex/agents"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/\.toml$//' | sort -u)
assert_eq "$canonical" "$rendered" "one .toml per canonical agent name"
assert_eq "0" "$(ls "$H1/.codex/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')" "no markdown under ~/.codex/agents"
bad=""
for f in "$H1/.codex/agents"/*.toml; do
  grep -q '^name = "' "$f" && grep -q '^description = "' "$f" && grep -q "^developer_instructions = '''" "$f" || bad="$bad $(basename "$f")"
  grep -q '^model' "$f" && bad="$bad $(basename "$f"):model-present"
done
assert_eq "" "$(echo $bad)" "every file has name, description, developer_instructions and no model keys when nothing is configured"
if $have_tomllib; then
  parse_bad=""; for f in "$H1/.codex/agents"/*.toml; do python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$f" 2>/dev/null || parse_bad="$parse_bad $(basename "$f")"; done
  assert_eq "" "$(echo $parse_bad)" "every rendered file parses as TOML"
  assert_eq "repo-research" "$(toml_get "$H1/.codex/agents/repo-research.toml" name)" "decoded name matches"
else
  pass "SKIPPED — python3 tomllib not available; parse assertions unchecked (raw-form assertions still run)"
fi
assert_eq "0" "$(ls -a "$H1/.codex/agents" | grep -c '^\..*\.toml\.' )" "no temp render files left behind"
grep -q "Rendered .* agent(s) as TOML" "$WORK/out" || true

# --- 2. configured tier: model and effort land only where the tier applies ---
mkdir -p "$H1/.ensemble"
echo '{"agent_model_codex_evidence":"gpt-x","agent_effort_codex_evidence":"high"}' > "$H1/.ensemble/config.json"
# a prior-install markdown symlink recorded in the manifest must be swept
ln -s "$SRC/skills/en-plan/agents/repo-research.md" "$H1/.codex/agents/repo-research.md"
echo "$H1/.codex/agents/repo-research.md" >> "$H1/.ensemble/install-manifest-codex.txt"
run_setup "$H1" --host codex; rc=$?
assert_exit_code 0 "$rc" "re-run after a config change exits 0"
grep -q '^model = "gpt-x"$' "$H1/.codex/agents/repo-research.toml" && pass "evidence-tier agent gets model = gpt-x" || fail "evidence-tier agent gets model = gpt-x" "$(grep model "$H1/.codex/agents/repo-research.toml")"
grep -q '^model_reasoning_effort = "high"$' "$H1/.codex/agents/repo-research.toml" && pass "evidence-tier agent gets model_reasoning_effort = high" || fail "evidence-tier agent gets model_reasoning_effort = high"
grep -q '^model' "$H1/.codex/agents/repo-fact-lookup.toml" && fail "retrieval-tier agent has no model keys" "$(grep model "$H1/.codex/agents/repo-fact-lookup.toml")" || pass "retrieval-tier agent has no model keys"
[ -e "$H1/.codex/agents/repo-research.md" ] && fail "a prior markdown symlink in the manifest is swept" || pass "a prior markdown symlink in the manifest is swept"
grep -q "rendered agents/repo-research.toml (model: gpt-x, effort: high; source ~/.ensemble/config.json)" "$WORK/out" \
  && pass "the log names the model, effort and the global source file" || fail "the log names the model, effort and the global source file" "$(grep 'repo-research' "$WORK/out")"
assert_eq "0" "$(ls -a "$H1/.codex/agents" | grep -c '^\..*\.toml\.' )" "re-run leaves no temp files"

# --- 3. a body with ''' is refused by name; everything else still renders ---
BAD="$SRC/skills/en-plan/agents/bad-agent.md"
printf -- "---\nname: bad-agent\ndescription: \"x\"\nmodel: sonnet\n---\n# bad\n\nA literal ''' inside.\n" > "$BAD"
H3="$WORK/h3"; run_setup "$H3" --host codex; rc=$?
[ "$rc" -ne 0 ] && pass "a ''' body makes setup exit non-zero (rc=$rc)" || fail "a ''' body makes setup exit non-zero" "rc=$rc"
[ -e "$H3/.codex/agents/bad-agent.toml" ] && fail "no partial TOML for the refused agent" || pass "no partial TOML for the refused agent"
grep -q "bad-agent" "$WORK/out" && pass "the refusal names the agent" || fail "the refusal names the agent" "$(tail -3 "$WORK/out")"
[ -f "$H3/.codex/agents/repo-research.toml" ] && pass "other agents are still rendered" || fail "other agents are still rendered"
rm -f "$BAD"

# --- 4. scalar escaping round-trips a quote and a backslash ---
ESC="$SRC/skills/en-plan/agents/esc-agent.md"
printf -- '---\nname: esc-agent\ndescription: "Says \\"hi\\" and C:\\\\path"\nmodel: sonnet\n---\n# esc\n\nBody line.\n' > "$ESC"
H4="$WORK/h4"; run_setup "$H4" --host codex; rc=$?
assert_exit_code 0 "$rc" "an escapable description renders"
grep -qF 'description = "Says \"hi\" and C:\\path"' "$H4/.codex/agents/esc-agent.toml" \
  && pass "quote and backslash are escaped as TOML basic-string escapes" \
  || fail "quote and backslash are escaped as TOML basic-string escapes" "$(grep description "$H4/.codex/agents/esc-agent.toml")"
if $have_tomllib; then
  assert_eq 'Says "hi" and C:\path' "$(toml_get "$H4/.codex/agents/esc-agent.toml" description)" "decoded description equals the source text"
  assert_eq "$(printf '# esc\n\nBody line.')" "$(toml_get "$H4/.codex/agents/esc-agent.toml" developer_instructions | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')" "decoded developer_instructions equals the source body"
fi
rm -f "$ESC"

# --- 5. --host both: markdown for Claude, TOML for Codex, disjoint manifests ---
H5="$WORK/h5"; run_setup "$H5" --host both; rc=$?
assert_exit_code 0 "$rc" "--host both exits 0"
[ "$(ls "$H5/.claude/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && pass "Claude still gets markdown agents" || fail "Claude still gets markdown agents"
[ "$(ls "$H5/.codex/agents"/*.toml 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && pass "Codex gets TOML agents" || fail "Codex gets TOML agents"
overlap=$(comm -12 <(sort "$H5/.ensemble/install-manifest-claude.txt") <(sort "$H5/.ensemble/install-manifest-codex.txt") | wc -l | tr -d ' ')
assert_eq "0" "$overlap" "the two manifests do not overlap"

# --- 6. two checkouts with conflicting repo-local values: the global file binds ---
H6="$WORK/h6"; mkdir -p "$H6/.ensemble" "$WORK/repoA/.ensemble" "$WORK/repoB/.ensemble"
echo '{"agent_model_codex_evidence":"gpt-global"}' > "$H6/.ensemble/config.json"
printf 'agent_model_codex_evidence: gpt-from-A\n' > "$WORK/repoA/.ensemble/config.local.yaml"
printf 'agent_model_codex_evidence: gpt-from-B\n' > "$WORK/repoB/.ensemble/config.local.yaml"
mkdir -p "$H6/.codex" "$H6/.claude"
( cd "$WORK/repoA" && HOME="$H6" bash "$SRC/setup" --host codex --copy ) >"$WORK/outA" 2>&1; cp "$H6/.codex/agents/repo-research.toml" "$WORK/fromA.toml"
( cd "$WORK/repoB" && HOME="$H6" bash "$SRC/setup" --host codex --copy ) >"$WORK/outB" 2>&1; cp "$H6/.codex/agents/repo-research.toml" "$WORK/fromB.toml"
cmp -s "$WORK/fromA.toml" "$WORK/fromB.toml" && pass "setup from two checkouts renders byte-identical TOML" || fail "setup from two checkouts renders byte-identical TOML"
grep -q '^model = "gpt-global"$' "$WORK/fromA.toml" && pass "the TOML is bound to the global value, not the checkout's" || fail "the TOML is bound to the global value, not the checkout's" "$(grep model "$WORK/fromA.toml")"
grep -q "source ~/.ensemble/config.json" "$WORK/outB" && pass "the log names the global file as the source" || fail "the log names the global file as the source"

report
