#!/usr/bin/env bash
# tests/portability/peer-detached-zsh.test.sh
#
# EN16 U13. On 2026-09-06 the detached peer form (ensemble_peer_start, D81)
# failed on first use from a Claude Code Bash tool on macOS, where the
# sourcing shell is zsh, and one Codex call (25,916 input tokens) was lost
# before the foreground form worked. Nothing reproduced it: the only zsh test
# covered sourcing, not the detached lifecycle. This runs the whole lifecycle
# (start, wait, result) under zsh with a stub peer, and the same under bash as
# the control, so a zsh-only failure is a red test rather than a lost run.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="detached peer invoke under zsh"

INVOKE="$REPO_ROOT/skills/en-plan/scripts/ensemble-peer-invoke"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
printf 'review this\n' > "$WORK/prompt.md"

# A stub peer: prints a well-formed findings object and exits 0. `codex` is not
# involved; the lifecycle under test is the job dir, not the CLI.
STUB="$WORK/stub-peer"
cat > "$STUB" <<'S'
#!/bin/sh
printf '%s\n' '{"verdict":"approve","peer_mode":"cross-agent","summary":"ok","findings":[],"coverage":{"reviewed":"all","not_reviewed":""}}'
S
chmod +x "$STUB"
SLOW="$WORK/slow-peer"
cat > "$SLOW" <<'S'
#!/bin/sh
sleep 30
S
chmod +x "$SLOW"

# The lifecycle script, shell-neutral. It sources the invoke helper, starts a
# detached peer, waits, and prints the result; each step's outcome goes to a
# file so the assertions read state rather than parse a transcript.
LIFECYCLE="$WORK/lifecycle.sh"
cat > "$LIFECYCLE" <<'L'
set -u
. "$INVOKE"
D="$OUT/job"
job=$(ensemble_peer_start --job-dir "$D" --peer-cmd "$PEER" --peer-format "" --prompt-file "$PROMPT" --peer-mode cross-agent) || { echo "start-failed:$?" > "$OUT/status"; exit 0; }
[ "$job" = "$D" ] || { echo "start-returned:$job" > "$OUT/status"; exit 0; }
w=$(ensemble_peer_wait "$D" --max-secs "$MAXSECS"); wrc=$?
echo "$w" > "$OUT/wait"; echo "$wrc" > "$OUT/wait_rc"
if [ "$wrc" -eq 0 ]; then
  ensemble_peer_result "$D" > "$OUT/result" 2>"$OUT/result_err"; echo "$?" > "$OUT/result_rc"
fi
echo ok > "$OUT/status"
L

run_lifecycle() {  # <shell> <peer> <maxsecs> <outdir>
  local sh="$1" peer="$2" maxsecs="$3" out="$4"
  mkdir -p "$out"
  INVOKE="$INVOKE" PEER="$peer" PROMPT="$WORK/prompt.md" MAXSECS="$maxsecs" OUT="$out" \
    "$sh" "$LIFECYCLE" >"$out/stdout" 2>"$out/stderr" </dev/null
}

check_happy() {  # <label> <outdir>
  local label="$1" out="$2"
  assert_eq "ok"   "$(cat "$out/status" 2>/dev/null)"   "$label: lifecycle ran to completion ($(cat "$out/status" 2>/dev/null; head -2 "$out/stderr" 2>/dev/null | tr '\n' ' '))"
  assert_eq "done" "$(cat "$out/wait" 2>/dev/null)"     "$label: ensemble_peer_wait reports done"
  assert_eq "0"    "$(cat "$out/result_rc" 2>/dev/null)" "$label: ensemble_peer_result exits with the invoke's 0"
  for f in pid started exit decision.json; do
    [ -f "$out/job/$f" ] && pass "$label: job dir has $f" || fail "$label: job dir has $f"
  done
  if command -v jq >/dev/null 2>&1; then
    jq -e '.peer' "$out/job/decision.json" >/dev/null 2>&1 \
      && pass "$label: decision.json is a peer_decision object" \
      || fail "$label: decision.json is a peer_decision object" "$(head -c 200 "$out/job/decision.json" 2>/dev/null)"
  fi
}

# --- control: bash ---
run_lifecycle bash "$STUB" 20 "$WORK/bash-happy"
check_happy "bash" "$WORK/bash-happy"

# --- the reproduction: zsh ---
if ! command -v zsh >/dev/null 2>&1; then
  pass "SKIPPED — zsh not installed; the detached lifecycle is unchecked under zsh on this machine"
else
  run_lifecycle zsh "$STUB" 20 "$WORK/zsh-happy"
  check_happy "zsh" "$WORK/zsh-happy"

  # A peer that outlives --max-secs must report running (rc 3) under both shells.
  run_lifecycle zsh  "$SLOW" 2 "$WORK/zsh-slow"
  run_lifecycle bash "$SLOW" 2 "$WORK/bash-slow"
  for sh in zsh bash; do
    assert_eq "running" "$(cat "$WORK/$sh-slow/wait" 2>/dev/null)"    "$sh: a slow peer reports running"
    assert_eq "3"       "$(cat "$WORK/$sh-slow/wait_rc" 2>/dev/null)" "$sh: ensemble_peer_wait exits 3 while running"
    pid=$(cat "$WORK/$sh-slow/job/pid" 2>/dev/null); [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    pkill -f "$SLOW" 2>/dev/null || true
  done

  # Missing --job-dir is a usage error under both shells.
  for sh in zsh bash; do
    err=$("$sh" -c ". '$INVOKE'; ensemble_peer_start --peer-cmd '$STUB' --prompt-file '$WORK/prompt.md'" 2>&1 >/dev/null); rc=$?
    [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -q -- "--job-dir is required" \
      && pass "$sh: ensemble_peer_start without --job-dir exits 2 with the usage line" \
      || fail "$sh: ensemble_peer_start without --job-dir exits 2 with the usage line" "rc=$rc err=$err"
  done
fi

report
