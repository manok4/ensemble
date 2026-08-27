#!/usr/bin/env bash
# tests/portability/live-anchor-hosts.test.sh
#
# EN12 U6, from peer finding 2-3. The shell smoke test sets SKILL_DIR itself, so
# it proves the script works while proving nothing about the part that can
# actually fail: whether a HOST gives the model a usable absolute path to
# substitute. Only a live invocation answers that.
#
# OPT-IN. Costs real tokens on two providers, so it skips unless
# ENSEMBLE_LIVE_HOST_TEST=1. CI stays hermetic and free.
#
# Design note, learned the hard way. An earlier version asked the host to echo a
# marker containing the isolated path — which was IN THE PROMPT, so a model
# could produce the "right" answer without running anything, and one did. The
# probe now plants a random token inside the isolated script only. The token
# appears nowhere in the prompt, so returning it is only possible by executing
# that copy.
#
# Recorded result, 2026-08-26, both hosts returned the planted token:
#   Codex        ANCHORPROOF db96e50ceca8dac2cf923695
#   Claude Code  ANCHORPROOF db96e50ceca8dac2cf923695

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="live SKILL_DIR anchor on both hosts"

if [ "${ENSEMBLE_LIVE_HOST_TEST:-0}" != "1" ]; then
  pass "skipped — set ENSEMBLE_LIVE_HOST_TEST=1 to run (costs tokens on two providers)"
  report
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT INT TERM HUP
TOKEN="$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
ISO="$WORK/skills"; mkdir -p "$ISO"
cp -R "$REPO_ROOT/skills/en-plan" "$ISO/en-plan"

# Plant the token ABOVE any early exit, so any invocation reveals it.
python3 - "$ISO/en-plan/scripts/ensemble-plan-hash" "$TOKEN" <<'PY'
import sys
p, tok = sys.argv[1], sys.argv[2]
lines = open(p).read().split('\n')
i = next(i for i, l in enumerate(lines) if l.startswith('set -u'))
lines.insert(i + 1, f'echo "ANCHORPROOF {tok}"')
open(p, 'w').write('\n'.join(lines))
PY

cat > "$WORK/probe.txt" <<PROMPT
Run exactly one Bash command, then answer. Do not read any files first.

SKILL_DIR="<the absolute directory containing $ISO/en-plan/SKILL.md>"; bash "\$SKILL_DIR/scripts/ensemble-plan-hash" --help

Reply with ONLY the output line starting with ANCHORPROOF.
PROMPT

check_host() {
  local label="$1"; shift
  if ! command -v "$1" >/dev/null 2>&1; then
    pass "[$label] CLI not installed — skipped"; return
  fi
  local out
  out=$(timeout 300 "$@" < "$WORK/probe.txt" 2>/dev/null | tr -d '\n')
  case "$out" in
    *"$TOKEN"*) pass "[$label] filled SKILL_DIR and executed the isolated copy" ;;
    *) fail "[$label] did not return the planted token" "got: $(echo "$out" | head -c 200)" ;;
  esac
}

check_host "Codex"       codex exec --json
check_host "Claude Code" claude -p --output-format json --max-turns 12

report
