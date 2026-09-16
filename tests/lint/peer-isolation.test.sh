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

# en-review step 9 tells the host how long to keep waiting before it reaps, and
# it can only say so by naming these same two numbers. When they disagree the
# host reaps a peer that the helper is still bounding: on 2026-09-15 step 9 said
# only "or the ceiling", and three read-tree peers were reaped at 532s, 615s and
# 618s and reported as peer-failed:timeout. Assert the prose against the values
# the helper just resolved, not against a literal, so moving a ceiling moves one
# number and this clause names the other.
# Everything AFTER the wait call, not the whole bullet: step 9 also names the
# ceilings when it introduces the access modes, so grepping the line passed
# even with the wait clause reverted to its unnamed-"the ceiling" form. The
# budget has to be stated where the host reads it, next to the call it bounds.
STEP9=$(grep 'ensemble_peer_wait' "$REPO_ROOT/skills/en-review/SKILL.md" | head -1)
STEP9=${STEP9#*ensemble_peer_wait}
# "<n>s for", not a bare "<n>s": the clause also cites the incident that
# produced it ("against a 1200s ceiling"), and a bare match let that citation
# satisfy the assertion about the budget.
for want in "$t_rt" "$t_none"; do
  printf '%s' "$STEP9" | grep -q "${want}s for " \
    && pass "en-review step 9 names the ${want}s ceiling the helper enforces" \
    || fail "en-review step 9 names the ${want}s ceiling the helper enforces" "$STEP9"
done
printf '%s' "$STEP9" | grep -q 'ensemble_peer_reap' \
  && pass "en-review step 9 still says when reaping is correct" \
  || fail "en-review step 9 still says when reaping is correct" "$STEP9"
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
# A reaped pass must still say WHICH CLI it killed. _epi_peer_name is set inside
# ensemble_peer_invoke, which runs in the detached subshell, so the parent that
# reaps had never seen it and every reaped pass reached the durable store as
# "peer":"unknown". Three of the five peer events ever recorded lost their CLI
# that way, on exactly the runs worth diagnosing. The name is asserted from the
# job dir, which is the only state the two shells share.
assert_eq "claude" "$(cat "$J2/peer" 2>/dev/null)" "start leaves the CLI name for a reap in another shell"
pkill -P "$pid" 2>/dev/null || true
# And the reap READS it. Asserting only that start wrote the file left the fix
# itself uncovered: deleting the read in ensemble_peer_reap kept this section
# green. _epi_peer_name is the variable the ledger line is built from one line
# later, so that is what the clause reads, in a fresh shell, on a live job.
mkstub claude 'sleep 30'
J3="$T/job3"
bash --noprofile --norc -c '
  set -eu; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_start --job-dir "$3" --peer-cmd "claude -p" --prompt-file "$4" --out-file "$3/peer.json" >/dev/null
' _ "$T/bin" "$INVOKE" "$J3" "$T/p" 2>/dev/null
named=$(bash --noprofile --norc -c '
  set -u; . "$1"; ensemble_peer_reap "$2" >/dev/null 2>&1; printf "%s" "${_epi_peer_name:-}"
' _ "$INVOKE" "$J3" 2>/dev/null)
assert_eq "claude" "$named" "reap attributes the pass to the CLI it killed, not to 'unknown'"
pid3=$(cat "$J3/pid" 2>/dev/null); [ -z "$pid3" ] || pkill -P "$pid3" 2>/dev/null || true

# --- 12a. the fork is skipped where it does not survive, and traced either way -
# On a Codex host the detached job never reached exec: the job dir held the run
# marker but not the out-file, which the shell creates BEFORE the command runs.
# The same foreground invoke on that host reached the CLI and got an answer. So
# the fork is what fails there, and D81's reason for it (no tool call held open)
# buys nothing under --peer, where the peer is the only reviewer. The signal is
# the one ensemble-detect-host already uses, checked in the safe direction: only
# a positive Codex marker disables the fork.
J6="$T/job6"; J7="$T/job7"
mkstub claude ''
start_job() {  # <dir> <env-prefix...>
  local d="$1"; shift
  env "$@" PATH="$T/bin:$PATH" bash --noprofile --norc -c '
    set -eu; . "$1"
    ensemble_peer_start --job-dir "$2" --peer-cmd "claude -p" --prompt-file "$3" \
      --out-file "$2/peer.json" --effort high >/dev/null
  ' _ "$INVOKE" "$d" "$T/p" 2>/dev/null
}
start_job "$J6" CODEX_HOME=/tmp/not-real
grep -q 'start:no-detach-on-this-host' "$J6/trace" 2>/dev/null && [ -f "$J6/exit" ] \
  && pass "a Codex host runs the peer in the foreground, terminal when start returns" \
  || fail "a Codex host runs the peer in the foreground" "trace=$(cat "$J6/trace" 2>/dev/null | tr '\n' ';')"
grep -q '"peer":"on"' "$J6/decision.json" 2>/dev/null && grep -q '"verdict"' "$J6/peer.json" 2>/dev/null \
  && pass "the foreground path fills the same job-dir contract, findings included" \
  || fail "the foreground path fills the same job-dir contract" "$(cat "$J6/decision.json" 2>/dev/null)"
start_job "$J7" ENSEMBLE_PEER_DETACH=auto
grep -q 'start:forking' "$J7/trace" 2>/dev/null \
  && pass "a host with no Codex marker still forks" \
  || fail "a host with no Codex marker still forks" "trace=$(cat "$J7/trace" 2>/dev/null | tr '\n' ';')"
# The override, both ways, so an operator can pin either behaviour.
J8="$T/job8"; start_job "$J8" ENSEMBLE_PEER_DETACH=never
J9="$T/job9"; start_job "$J9" CODEX_HOME=/tmp/not-real ENSEMBLE_PEER_DETACH=always
grep -q 'start:no-detach-on-this-host' "$J8/trace" 2>/dev/null \
  && grep -q 'start:forking' "$J9/trace" 2>/dev/null \
  && pass "ENSEMBLE_PEER_DETACH pins the launch either way" \
  || fail "ENSEMBLE_PEER_DETACH pins the launch" "never=$(cat "$J8/trace" 2>/dev/null|tr '\n' ';') always=$(cat "$J9/trace" 2>/dev/null|tr '\n' ';')"
# The trace has to bracket the exec, because that is the gap the field failure
# died in: marker present, out-file never created, nothing in between recorded.
grep -q 'invoke:marker-written' "$J7/trace" && grep -q 'invoke:exec-begin' "$J7/trace" \
  && pass "the trace brackets the exec on both sides of the fork" \
  || fail "the trace brackets the exec" "$(cat "$J7/trace" 2>/dev/null | tr '\n' ';')"

# --- 12b. a job whose process is gone is terminal, not "still thinking" -------
# ensemble_peer_wait tested for the exit file alone, so a peer that died before
# exec was indistinguishable from a slow one for the caller's whole budget. On
# 2026-09-15 a Codex-hosted review waited 1276s on a subshell that never reached
# exec and reported peer-failed:timeout, which is a ceiling that never fired
# blamed on a peer that never ran. Reproduced by killing the job's process the
# way the field failure did, and asserting on the SIGNATURE of that run: the
# out-file absent (the shell creates it before the command execs, so its absence
# is proof nothing ran) while the job is still not terminal.
J4="$T/job4"
mkstub claude 'sleep 60'
bash --noprofile --norc -c '
  set -eu; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_start --job-dir "$3" --peer-cmd "claude -p" --prompt-file "$4" \
    --out-file "$3/peer.json" --peer-mode cross-agent --effort high --model-alias opus >/dev/null
' _ "$T/bin" "$INVOKE" "$J4" "$T/p" 2>/dev/null
sleep 1
kill -9 "$(cat "$J4/pid")" 2>/dev/null || true
pkill -9 -P "$(cat "$J4/pid")" 2>/dev/null || true
sleep 1
t0=$(date +%s)
w=$(bash --noprofile --norc -c '. "$1"; ensemble_peer_wait "$2" --max-secs 30' _ "$INVOKE" "$J4" 2>/dev/null); wrc=$?
t_wait=$(( $(date +%s) - t0 ))
[ "$w" = "done" ] && [ "$wrc" = "0" ] && [ "$t_wait" -le 5 ] \
  && pass "wait reports a dead job at once instead of burning the budget (${t_wait}s of 30)" \
  || fail "wait reports a dead job at once" "wait=$w/$wrc took=${t_wait}s"
res=$(bash --noprofile --norc -c '. "$1"; ensemble_peer_result "$2"' _ "$INVOKE" "$J4" 2>/dev/null)
printf '%s' "$res" | grep -q 'peer-failed:died' \
  && pass "a dead job records peer-failed:died, not a timeout that never fired" \
  || fail "a dead job records peer-failed:died" "$res"
# The context comes from the job dir, so a decision written by the PARENT still
# names the tier the job ran at rather than re-defaulting it to medium.
printf '%s' "$res" | grep -q '"effort":"high"' && printf '%s' "$res" | grep -q '"model_alias":"opus"' \
  && pass "the dead job's decision keeps the tier and alias start recorded" \
  || fail "the dead job's decision keeps the tier and alias" "$res"
# A LIVE job must not be called dead: the ceiling is still what bounds it.
J5="$T/job5"
mkstub claude 'sleep 60'
bash --noprofile --norc -c '
  set -eu; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_start --job-dir "$3" --peer-cmd "claude -p" --prompt-file "$4" --out-file "$3/peer.json" >/dev/null
' _ "$T/bin" "$INVOKE" "$J5" "$T/p" 2>/dev/null
w=$(bash --noprofile --norc -c '. "$1"; ensemble_peer_wait "$2" --max-secs 2' _ "$INVOKE" "$J5" 2>/dev/null); wrc=$?
[ "$w" = "running" ] && [ "$wrc" = "3" ] \
  && pass "a live peer still reports running, not died" \
  || fail "a live peer still reports running" "wait=$w/$wrc"
pid5=$(cat "$J5/pid" 2>/dev/null); [ -z "$pid5" ] || { pkill -P "$pid5" 2>/dev/null; kill "$pid5" 2>/dev/null; } || true

# --- 13. the peer's own receipt: what the pass cost, in the CLI's own numbers ----
# Nothing recorded cost or tokens, so no report could ask whether a peer earned
# what it charged. Both CLIs already print it in the response the helper is
# parsing anyway. Claude reports cost, tokens and the served model; codex
# reports tokens only, and null there means "the CLI did not say", never zero.
# The codex branch must also leave its stream BYTE-INTACT, because
# ensemble_extract_json still has to read it afterwards.
CLAUDE_ENV='{"type":"result","subtype":"success","total_cost_usd":2.8656819999999996,"usage":{"input_tokens":41,"output_tokens":1902},"modelUsage":{"claude-opus-5-20260101":{"canonicalModel":"claude-opus-5","inputTokens":41,"outputTokens":1902}},"structured_output":{"verdict":"revise","peer_mode":"cross-agent","summary":"s","findings":[]}}'
cat > "$T/bin/claude" <<STUB
#!/usr/bin/env bash
printf '%s' '$CLAUDE_ENV'
STUB
chmod +x "$T/bin/claude"
receipt() {  # <peer-cmd> -> "model|cost|tin|tout" after one invoke
  bash --noprofile --norc -c '
    set -u; export PATH="$1:$PATH"; . "$2"
    ensemble_peer_invoke --peer-cmd "$3" --prompt-file "$4" --out-file "$5" >/dev/null 2>&1
    printf "%s|%s|%s|%s\n" "$_epi_model_actual" \
      "$(_epi_num_or_null "$_epi_cost_usd")" \
      "$(_epi_num_or_null "$_epi_tokens_in")" \
      "$(_epi_num_or_null "$_epi_tokens_out")"
  ' _ "$T/bin" "$INVOKE" "$1" "$T/p" "$T/out" 2>/dev/null
}
assert_eq "claude-opus-5|2.865682|41|1902" "$(receipt 'claude -p')" \
  "claude envelope: served model, cost and tokens all reach the recorded event"

CODEX_STREAM='{"type":"thread.started","thread_id":"t"}
{"type":"item.completed","item":{"type":"agent_message","text":"{\"verdict\":\"approve\",\"peer_mode\":\"cross-agent\",\"summary\":\"s\",\"findings\":[]}"}}
{"type":"turn.completed","usage":{"input_tokens":55102,"cached_input_tokens":33536,"output_tokens":78}}'
cat > "$T/bin/codex" <<STUB
#!/usr/bin/env bash
printf '%s\n' '$CODEX_STREAM'
STUB
chmod +x "$T/bin/codex"
assert_eq "|null|55102|78" "$(receipt 'codex exec')" \
  "codex stream: tokens are read, cost and served model stay null"
grep -q '"verdict"' "$T/out" \
  && pass "codex stream: the findings still parse out of the untouched stream" \
  || fail "codex stream: the findings still parse out of the untouched stream" "$(head -c 200 "$T/out")"

# A pass whose CLI reported nothing must not inherit the previous pass's
# receipt. `read` past end-of-input leaves the variable alone in some shells,
# which would have made a silent CLI look like a $2.87 one.
mkstub claude ''
assert_eq "|null|null|null" "$(receipt 'claude -p')" \
  "a CLI that reports no receipt records nulls, not the previous pass's numbers"

# --- 14. a failure the CLI already named, and the receipt it came with -------
# A peer that spends its turn budget and returns nothing exits non-zero with a
# COMPLETE envelope on stdout and silence on stderr. The classifier reads
# stderr, so it reported peer-failed:unknown for a failure the CLI had named in
# plain text, and the receipt was dropped because the envelope was only ever
# parsed on the success path: 26 turns and $2.09 recorded as cost_usd null
# (2026-09-16, a Codex-hosted review that then fell back to same-agent).
MT_ENV='{"type":"result","subtype":"error_max_turns","is_error":true,"terminal_reason":"max_turns","num_turns":26,"total_cost_usd":2.089528,"usage":{"input_tokens":91,"output_tokens":3120},"modelUsage":{"claude-opus-5":{"canonicalModel":"claude-opus-5","inputTokens":91,"outputTokens":3120}}}'
cat > "$T/bin/claude" <<STUB
#!/usr/bin/env bash
printf '%s' '$MT_ENV'
exit 1
STUB
chmod +x "$T/bin/claude"
d=$(inv "claude -p" "$T/p" "$T/out")
printf '%s' "$d" | grep -q 'peer-failed:max-turns' \
  && pass "the CLI's own subtype names the failure instead of 'unknown'" \
  || fail "the CLI's own subtype names the failure" "$d"
printf '%s' "$d" | grep -q '"model_actual":"claude-opus-5"' \
  && pass "a FAILED pass still reports what served it" \
  || fail "a failed pass still reports what served it" "$d"
# Read, not rewritten: the classifier and the one retry still need the CLI's
# own answer on disk, and there are no findings in an error envelope to unwrap.
grep -q 'error_max_turns' "$T/out" \
  && pass "a failing envelope is left intact for the classifier" \
  || fail "a failing envelope is left intact" "$(head -c 200 "$T/out")"
# The receipt the ledger needs: the shell-side gate turns it into JSON numbers.
rcpt=$(bash --noprofile --norc -c '
  set -u; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_invoke --peer-cmd "claude -p" --prompt-file "$3" --out-file "$4" >/dev/null 2>&1
  printf "%s|%s|%s\n" "$(_epi_num_or_null "$_epi_cost_usd")" \
    "$(_epi_num_or_null "$_epi_tokens_in")" "$(_epi_num_or_null "$_epi_tokens_out")"
' _ "$T/bin" "$INVOKE" "$T/p" "$T/out" 2>/dev/null)
assert_eq "2.089528|91|3120" "$rcpt" "a failed pass records what it cost, not nulls"

# --- 14b. the receipt names the model that DID THE WORK ----------------------
# modelUsage lists every model the CLI touched, and Claude Code puts its own
# small internal model FIRST. Reading entry [0] reported claude-haiku-4-5 as
# the server of a --model opus review, and reported that side model's handful
# of output tokens as the whole pass: a real review recorded tokens_out 17,
# which is what gave it away (2026-09-16). Ordered side-model-first on purpose,
# because that is the order the CLI actually emits.
SIDE_FIRST='{"type":"result","subtype":"success","total_cost_usd":0.2145395,"usage":{"input_tokens":4,"output_tokens":383},"modelUsage":{"claude-haiku-4-5-20251001":{"canonicalModel":"claude-haiku-4-5","inputTokens":905,"outputTokens":12},"claude-opus-5":{"canonicalModel":"claude-opus-5","inputTokens":4,"outputTokens":383}},"structured_output":{"verdict":"approve","peer_mode":"cross-agent","summary":"s","findings":[]}}'
cat > "$T/bin/claude" <<STUB
#!/usr/bin/env bash
printf '%s' '$SIDE_FIRST'
STUB
chmod +x "$T/bin/claude"
d=$(inv "claude -p" "$T/p" "$T/out" --peer-model "--model opus")
printf '%s' "$d" | grep -q '"model_actual":"claude-opus-5"' \
  && pass "model_actual names the model that produced the output, not the side model" \
  || fail "model_actual names the model that produced the output" "$d"
rcpt=$(bash --noprofile --norc -c '
  set -u; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_invoke --peer-cmd "claude -p" --prompt-file "$3" --out-file "$4" >/dev/null 2>&1
  printf "%s|%s\n" "$(_epi_num_or_null "$_epi_tokens_in")" "$(_epi_num_or_null "$_epi_tokens_out")"
' _ "$T/bin" "$INVOKE" "$T/p" "$T/out" 2>/dev/null)
assert_eq "909|395" "$rcpt" "tokens are the whole pass, summed across every model it touched"
# The single-model case must be unaffected: one entry is still that entry.
ONE_MODEL='{"type":"result","subtype":"success","total_cost_usd":1.5,"modelUsage":{"claude-opus-5":{"canonicalModel":"claude-opus-5","inputTokens":50,"outputTokens":700}},"structured_output":{"verdict":"approve","peer_mode":"cross-agent","summary":"s","findings":[]}}'
cat > "$T/bin/claude" <<STUB
#!/usr/bin/env bash
printf '%s' '$ONE_MODEL'
STUB
chmod +x "$T/bin/claude"
d=$(inv "claude -p" "$T/p" "$T/out")
printf '%s' "$d" | grep -q '"model_actual":"claude-opus-5"' \
  && pass "a single-model receipt is unchanged" \
  || fail "a single-model receipt is unchanged" "$d"

# --- 15. the trace says which flags were exec'd ------------------------------
# "Was --json-schema actually bound?" was the first question the 2026-09-16
# failure raised, and the trace could not answer it. Names only: one flag's
# value is the whole schema and another is a prompt path.
mkstub claude ''
JT="$T/job-trace"
bash --noprofile --norc -c '
  set -eu; export PATH="$1:$PATH"; . "$2"
  ensemble_peer_start --job-dir "$3" --peer-cmd "claude -p" --peer-format "--output-format json" \
    --prompt-file "$4" --out-file "$3/peer.json" --schema "$5" --access read-tree \
    --peer-model "--model opus" >/dev/null
' _ "$T/bin" "$INVOKE" "$JT" "$T/p" "$REPO_ROOT/skills/en-review/scripts/peer-findings.schema.json" 2>/dev/null
sleep 1
flagline=$(grep 'invoke:exec-begin' "$JT/trace" 2>/dev/null || true)
miss=""
for f in --json-schema --tools --permission-mode --model; do
  printf '%s' "$flagline" | grep -q -- "$f" || miss="$miss $f"
done
[ -z "$miss" ] && pass "the trace names the flags the peer was exec'd with" \
               || fail "the trace names the flags the peer was exec'd with" "missing:$miss line=$flagline"
printf '%s' "$flagline" | grep -q 'mcpServers' \
  && fail "the trace leaks flag VALUES" "$flagline" \
  || pass "the trace carries flag names only, never their values"

report
