#!/usr/bin/env bash
# tests/lint/peer-isolation.test.sh
#
# references/outside-voice.md has called the Claude isolation flags
# "load-bearing" since PR #9: no MCP servers, no skills, no session state, no
# user-level settings, and --tools '' so the single --max-turns cannot be spent
# on a tool call (a loaded LSP did exactly that in the field). D49 routed every
# peer call through ensemble-peer-invoke, and the helper never applied them.
# The flags lived in prose and in a comment block of the prompt builder, and a
# text guard (en-codex-flag-drift) confirmed the prose still said so. Every
# Claude peer call from en-plan, en-foundation and en-review ran unisolated.
#
# This drives the real helper against a PATH-shadow `claude` that records its
# argv, so the assertion is about what the subprocess receives, not what a
# document says.
#
# Negative control at authoring: removing `--tools ''` from en-plan's copy of
# the array turned two clauses red, the flag clause and the byte-identity
# clause (only one carrier had been edited), which is the pair you want.
#
# D81 added a second access mode. read-tree gives the Claude peer Read, Grep
# and Glob, --permission-mode dontAsk and a 25-turn cap; codex gets
# -s read-only in both modes; --schema binds the CLI's output schema; the
# claude result envelope is unwrapped to the findings and its modelUsage key
# becomes the decision's model_actual; and a detached start/wait/result/reap
# form lets a long peer run outside any tool call. Negative controls at
# authoring: dropping --permission-mode from the read-tree set turned clause 7
# red; disabling the envelope unwrap turned clause 11 red; making start wait
# on the subshell turned the "returns at once" clause red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="peer isolation flags"

INVOKE="$REPO_ROOT/skills/en-plan/scripts/ensemble-peer-invoke"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf 'peer review of a plan\n' > "$T/p"
ARGV="$T/argv"; CALLS="$T/calls"

# --- 1. one implementation: every carrier is byte-identical -----------------
distinct=$(for f in "$REPO_ROOT"/skills/*/scripts/ensemble-peer-invoke; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
assert_eq "1" "$distinct" "every ensemble-peer-invoke carrier is byte-identical"

# A stub that records argv (one arg per line, empty args included) and answers.
mkstub() {  # $1=name $2=body-before-answer (may exit early)
  cat > "$T/bin/$1" <<STUB
#!/usr/bin/env bash
echo call >> "$CALLS"
: > "$ARGV"; for a in "\$@"; do printf '%s\n' "\$a" >> "$ARGV"; done
$2
printf '%s' '{"verdict":"approve","peer_mode":"cross-agent","summary":"ok","findings":[]}'
STUB
  chmod +x "$T/bin/$1"
}

inv() {  # inv <peer-cmd> [extra flags...] -> decision json
  : > "$CALLS"
  bash --noprofile --norc -c '
    set -eu
    export PATH="$1:$PATH"; . "$2"; shift 2
    ensemble_peer_invoke --peer-cmd "$1" --peer-format "--output-format json" \
      --peer-turns "--max-turns 1" --prompt-file "$2" --out-file "$3" "${@:4}" || true
  ' _ "$T/bin" "$INVOKE" "$@" 2>/dev/null
}

has_arg() { grep -qxF -- "$1" "$ARGV"; }

# --- 2. a claude peer receives the full isolation set -----------------------
mkstub claude ''
d=$(inv "claude -p" "$T/p" "$T/out")
iso_ok=1
for f in --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands \
         --no-session-persistence --setting-sources project --tools; do
  has_arg "$f" || { iso_ok=0; missing="${missing:-} $f"; }
done
# --tools must be followed by an EMPTY argument, and it must survive as one.
tools_empty=$(awk '$0=="--tools"{getline; print (length($0)==0 ? "empty" : "nonempty"); exit}' "$ARGV")
[ "$tools_empty" = "empty" ] || { iso_ok=0; missing="${missing:-} tools-arg=$tools_empty"; }
has_arg "-p" && has_arg "--output-format" && has_arg "--max-turns" || { iso_ok=0; missing="${missing:-} base-flags"; }
[ "$iso_ok" -eq 1 ] && pass "claude peer gets every isolation flag, with --tools '' intact" \
                    || fail "claude peer gets every isolation flag" "missing:${missing:-}"
printf '%s' "$d" | grep -q '"peer": *"on"' && pass "decision is a normal on" || fail "decision is a normal on" "$d"

# --- 3. a codex peer receives none of them ------------------------------------
mkstub codex ''
inv "codex exec" "$T/p" "$T/out" >/dev/null
leaked=""
for f in --strict-mcp-config --mcp-config --disable-slash-commands --no-session-persistence --setting-sources --tools; do
  has_arg "$f" && leaked="$leaked $f"
done
[ -z "$leaked" ] && pass "codex peer receives no Claude isolation flag" \
                 || fail "codex peer receives no Claude isolation flag" "leaked:$leaked"

# --- 4. ENSEMBLE_PEER_ISOLATION=off disables the set for a session ------------
ENSEMBLE_PEER_ISOLATION=off inv "claude -p" "$T/p" "$T/out" >/dev/null
has_arg "--strict-mcp-config" && fail "ENSEMBLE_PEER_ISOLATION=off disables the set" "flag still present" \
                              || pass "ENSEMBLE_PEER_ISOLATION=off disables the set"

# --- 5. a rejected isolation flag costs one retry without the set, not the review
mkstub claude 'for a in "$@"; do case "$a" in --setting-sources) echo "error: unexpected argument '"'"'--setting-sources'"'"' found" >&2; exit 2;; esac; done'
d=$(inv "claude -p" "$T/p" "$T/out" --peer-effort "--effort medium")
calls=$(wc -l < "$CALLS" | tr -d ' ')
if [ "$calls" = "2" ] && printf '%s' "$d" | grep -q 'dropped-isolation-fragment' \
   && printf '%s' "$d" | grep -q '"peer": *"degraded"' \
   && ! has_arg "--strict-mcp-config" && has_arg "--effort"; then
  pass "isolation rejection: one retry, set dropped, effort kept, decision degraded"
else
  fail "isolation rejection: one retry, set dropped, effort kept, decision degraded" \
       "calls=$calls decision=$d"
fi

# --- 6. the retry after a model rejection keeps the isolation set --------------
mkstub claude 'for a in "$@"; do case "$a" in --model) echo "error: unexpected argument '"'"'--model'"'"' found" >&2; exit 2;; esac; done'
d=$(inv "claude -p" "$T/p" "$T/out" --peer-model "--model sonnet")
if printf '%s' "$d" | grep -q 'dropped-model-fragment' && has_arg "--strict-mcp-config" && ! has_arg "--model"; then
  pass "model rejection drops only the model fragment; isolation survives the retry"
else
  fail "model rejection drops only the model fragment; isolation survives the retry" "$d"
fi

# --- 7. read-tree access: Read/Grep/Glob, dontAsk, the helper's own turn cap ----
mkstub claude ''
inv "claude -p" "$T/p" "$T/out" --access read-tree >/dev/null
arg_after() { awk -v k="$1" '$0==k{getline; print; exit}' "$ARGV"; }
rt_ok=1; rt_why=""
[ "$(arg_after --tools)" = "Read,Grep,Glob" ] || { rt_ok=0; rt_why="$rt_why tools=$(arg_after --tools)"; }
[ "$(arg_after --permission-mode)" = "dontAsk" ] || { rt_ok=0; rt_why="$rt_why permission-mode=$(arg_after --permission-mode)"; }
[ "$(arg_after --max-turns)" = "25" ] || { rt_ok=0; rt_why="$rt_why max-turns=$(arg_after --max-turns)"; }
[ "$(grep -cx -- '--max-turns' "$ARGV")" = "1" ] || { rt_ok=0; rt_why="$rt_why caller-turn-cap-survived"; }
has_arg "--strict-mcp-config" && has_arg "--setting-sources" || { rt_ok=0; rt_why="$rt_why base-set-missing"; }
[ "$rt_ok" -eq 1 ] && pass "read-tree: Read,Grep,Glob + dontAsk + a single 25-turn cap, base set intact" \
                   || fail "read-tree: Read,Grep,Glob + dontAsk + a single 25-turn cap" "$rt_why"
ENSEMBLE_PEER_MAX_TURNS=7 inv "claude -p" "$T/p" "$T/out" --access read-tree >/dev/null
[ "$(arg_after --max-turns)" = "7" ] && pass "ENSEMBLE_PEER_MAX_TURNS sets the read-tree turn cap" \
                                     || fail "ENSEMBLE_PEER_MAX_TURNS sets the read-tree turn cap" "got $(arg_after --max-turns)"
inv "claude -p" "$T/p" "$T/out" >/dev/null
[ "$(arg_after --max-turns)" = "1" ] && [ "$(awk '$0=="--tools"{getline; print length($0); exit}' "$ARGV")" = "0" ] \
  && pass "default access is still none: --tools '' and the caller's one turn" \
  || fail "default access is still none" "max-turns=$(arg_after --max-turns)"

# --- 8. codex: read-only sandbox in both modes, no Claude flags ---------------------
mkstub codex ''
inv "codex exec" "$T/p" "$T/out" --access read-tree >/dev/null
[ "$(arg_after -s)" = "read-only" ] && ! has_arg "--permission-mode" && ! has_arg "--tools" \
  && pass "codex read-tree: -s read-only and no Claude flag" \
  || fail "codex read-tree: -s read-only and no Claude flag" "s=$(arg_after -s)"
inv "codex exec" "$T/p" "$T/out" >/dev/null
[ "$(arg_after -s)" = "read-only" ] && pass "codex none: -s read-only too (the peer never writes)" \
                                    || fail "codex none: -s read-only too" "s=$(arg_after -s)"

# --- 9. --schema binds the CLI's output schema --------------------------------------
printf '{"type":"object","required":["verdict"]}' > "$T/schema.json"
mkstub claude ''
inv "claude -p" "$T/p" "$T/out" --schema "$T/schema.json" >/dev/null
[ "$(arg_after --json-schema)" = '{"type":"object","required":["verdict"]}' ] \
  && pass "claude: --json-schema carries the schema text" \
  || fail "claude: --json-schema carries the schema text" "got $(arg_after --json-schema)"
mkstub codex ''
inv "codex exec" "$T/p" "$T/out" --schema "$T/schema.json" >/dev/null
[ "$(arg_after --output-schema)" = "$T/schema.json" ] \
  && pass "codex: --output-schema carries the schema path" \
  || fail "codex: --output-schema carries the schema path" "got $(arg_after --output-schema)"
d=$(inv "claude -p" "$T/p" "$T/out" --schema "$T/missing.json" 2>&1 || true)
[ -z "$(printf '%s' "$d" | grep '"peer"')" ] && pass "a missing schema file is refused before any call" \
                                              || fail "a missing schema file is refused before any call" "$d"

# --- 10. the timeout ceiling follows the access mode ----------------------------------
cat > "$T/bin/timeout" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$1" > "$T/tmo"; shift; exec "\$@"
STUB
chmod +x "$T/bin/timeout"
mkstub claude ''
inv "claude -p" "$T/p" "$T/out" >/dev/null;                       t_none=$(cat "$T/tmo")
inv "claude -p" "$T/p" "$T/out" --access read-tree >/dev/null;    t_rt=$(cat "$T/tmo")
peer_timeout_seconds=42 inv "claude -p" "$T/p" "$T/out" --access read-tree >/dev/null; t_cfg=$(cat "$T/tmo")
[ "$t_none" = "600" ] && [ "$t_rt" = "1200" ] && [ "$t_cfg" = "42" ] \
  && pass "timeout: 600 one-shot, 1200 read-tree, peer_timeout_seconds overrides both" \
  || fail "timeout follows the access mode" "none=$t_none read-tree=$t_rt cfg=$t_cfg"
rm -f "$T/bin/timeout"

# --- 11. the claude result envelope is unwrapped; modelUsage becomes model_actual ----
ENV_WITH='{"type":"result","subtype":"success","result":"```json\n{\"verdict\":\"approve\",\"findings\":[]}\n```","structured_output":{"verdict":"approve","peer_mode":"cross-agent","summary":"ok","findings":[]},"modelUsage":{"claude-opus-5-20260101":{"canonicalModel":"claude-opus-5","inputTokens":1}}}'
cat > "$T/bin/claude" <<STUB
#!/usr/bin/env bash
: > "$ARGV"; for a in "\$@"; do printf '%s\n' "\$a" >> "$ARGV"; done
printf '%s' '$ENV_WITH'
STUB
chmod +x "$T/bin/claude"
d=$(inv "claude -p" "$T/p" "$T/out")
if command -v jq >/dev/null 2>&1; then got=$(jq -c . "$T/out" 2>/dev/null); else got=$(cat "$T/out"); fi
if printf '%s' "$got" | grep -q '"peer_mode":"cross-agent"' && ! grep -q '"type"' "$T/out" \
   && printf '%s' "$d" | grep -q '"model_actual":"claude-opus-5"'; then
  pass "envelope with structured_output: findings unwrapped, model_actual from canonicalModel"
else
  fail "envelope with structured_output: findings unwrapped, model_actual from canonicalModel" "out=$got decision=$d"
fi
ENV_WITHOUT='{"type":"result","result":"Here you go:\n```json\n{\"verdict\":\"revise\",\"findings\":[]}\n```","modelUsage":{"claude-sonnet-5-20260101":{"inputTokens":1}}}'
cat > "$T/bin/claude" <<STUB
#!/usr/bin/env bash
printf '%s' '$ENV_WITHOUT'
STUB
chmod +x "$T/bin/claude"
d=$(inv "claude -p" "$T/p" "$T/out")
if grep -q '"verdict"' "$T/out" && ! grep -q '"type"' "$T/out" && ! grep -q '```' "$T/out" \
   && printf '%s' "$d" | grep -q '"model_actual":"claude-sonnet-5-20260101"'; then
  pass "envelope without structured_output: result text unfenced, model_actual from the usage key"
else
  fail "envelope without structured_output: result text unfenced, model_actual from the usage key" "out=$(cat "$T/out") decision=$d"
fi
printf '%s' '{"verdict":"approve","findings":[]}' > "$T/plain"
cat > "$T/bin/claude" <<STUB
#!/usr/bin/env bash
cat "$T/plain"
STUB
chmod +x "$T/bin/claude"
d=$(inv "claude -p" "$T/p" "$T/out")
grep -q '"verdict":"approve"' "$T/out" && printf '%s' "$d" | grep -q '"model_actual":null' \
  && pass "plain JSON passes through; model_actual is null when there is no receipt" \
  || fail "plain JSON passes through; model_actual null without a receipt" "out=$(cat "$T/out") decision=$d"

# --- 12. detached form: start returns at once, wait is bounded, result and reap ----
# Each step runs in its own shell, as each host tool call does, so this also
# proves the peer outlives the shell that started it.
mkstub claude 'sleep 3'
J="$T/job"
t0=$(date +%s)
started=$(bash --noprofile --norc -c '
  set -eu; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_start --job-dir "$3" --peer-cmd "claude -p" --peer-format "--output-format json" \
    --peer-turns "--max-turns 1" --prompt-file "$4" --out-file "$3/peer.json"
' _ "$T/bin" "$INVOKE" "$J" "$T/p" 2>/dev/null)
t_start=$(( $(date +%s) - t0 ))
[ "$started" = "$J" ] && [ "$t_start" -le 2 ] && pass "start prints the job dir and returns at once (${t_start}s)" \
                                              || fail "start prints the job dir and returns at once" "printed=$started took=${t_start}s"
w1=$(bash --noprofile --norc -c '. "$1"; ensemble_peer_wait "$2" --max-secs 1' _ "$INVOKE" "$J" 2>/dev/null); rc1=$?
w2=$(bash --noprofile --norc -c '. "$1"; ensemble_peer_wait "$2" --max-secs 20' _ "$INVOKE" "$J" 2>/dev/null); rc2=$?
[ "$w1" = "running" ] && [ "$rc1" = "3" ] && [ "$w2" = "done" ] && [ "$rc2" = "0" ] \
  && pass "wait: running/3 inside the slice, done/0 once the peer finishes" \
  || fail "wait: running/3 then done/0" "w1=$w1/$rc1 w2=$w2/$rc2"
res=$(bash --noprofile --norc -c '. "$1"; ensemble_peer_result "$2"' _ "$INVOKE" "$J" 2>/dev/null); rrc=$?
printf '%s' "$res" | grep -q '"peer":"on"' && [ "$rrc" = "0" ] && grep -q '"verdict"' "$J/peer.json" \
  && pass "result: the decision and the invoke's exit code, peer output in the job dir" \
  || fail "result: decision + exit code + peer output" "res=$res rc=$rrc"
mkstub claude 'sleep 30'
J2="$T/job2"
bash --noprofile --norc -c '
  set -eu; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_start --job-dir "$3" --peer-cmd "claude -p" --peer-format "--output-format json" \
    --peer-turns "--max-turns 1" --prompt-file "$4" --out-file "$3/peer.json" >/dev/null
' _ "$T/bin" "$INVOKE" "$J2" "$T/p" 2>/dev/null
sleep 1
t0=$(date +%s)
bash --noprofile --norc -c '. "$1"; ensemble_peer_reap "$2" --effort high' _ "$INVOKE" "$J2" 2>/dev/null
t_reap=$(( $(date +%s) - t0 ))
res=$(bash --noprofile --norc -c '. "$1"; ensemble_peer_result "$2"' _ "$INVOKE" "$J2" 2>/dev/null); rrc=$?
pid=$(cat "$J2/pid"); alive=0; kill -0 "$pid" 2>/dev/null && alive=1
if printf '%s' "$res" | grep -q 'peer-failed:timeout' && printf '%s' "$res" | grep -q '"effort":"high"' \
   && [ "$rrc" = "1" ] && [ "$alive" = "0" ] && [ "$t_reap" -le 5 ]; then
  pass "reap: kills the running peer, records peer-failed:timeout with the caller's tier (${t_reap}s)"
else
  fail "reap: kills the running peer and records peer-failed:timeout" "res=$res rc=$rrc alive=$alive took=${t_reap}s"
fi
pkill -P "$pid" 2>/dev/null || true

report
