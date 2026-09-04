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

report
