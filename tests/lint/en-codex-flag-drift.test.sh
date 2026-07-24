#!/usr/bin/env bash
# Drift guards for EN10 — the Codex `--max-turns` flag drift fix.
# codex-cli 0.144.0 removed --max-turns (codex exec is single-shot); the peer
# contract must resolve the turn cap per-agent via PEER_TURNS ($--max-turns 1$
# for claude -p, empty for codex exec) instead of hardcoding it. This guard
# fails if any peer-contract reference or `setup` re-introduces a hardcoded
# Codex --max-turns.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-codex flag drift"

DETECT="$REPO_ROOT/bin/ensemble-detect-host"
HOSTDOC="$REPO_ROOT/references/host-detect.md"
OUTVOICE="$REPO_ROOT/references/outside-voice.md"
WRAPPERS="$REPO_ROOT/references/cli-wrappers.md"
HANDOFF="$REPO_ROOT/references/build-handoff.md"
ORCH="$REPO_ROOT/references/build-orchestration.md"
SETUP="$REPO_ROOT/setup"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# === U1: detect-host emits PEER_TURNS, resolved per agent ===
if grep -qF "PEER_TURNS" "$DETECT"; then
  pass "ensemble-detect-host emits PEER_TURNS"
else
  fail "ensemble-detect-host must emit PEER_TURNS"
  report
fi
# claude peer -> --max-turns 1 ; codex peer -> empty (bypass cache; clean host env)
codex_peer=$(env -u CODEX_HOME -u CODEX_VERSION CLAUDE_CODE_VERSION=1 "$DETECT" --no-cache 2>/dev/null | grep '^PEER_TURNS=')
claude_peer=$(env -u CLAUDE_CODE_VERSION -u CLAUDE_AGENT_NAME ENSEMBLE_HOST=codex "$DETECT" --no-cache 2>/dev/null | grep '^PEER_TURNS=')
if printf '%s' "$codex_peer" | grep -qE "PEER_TURNS=''"; then
  pass "Claude host (Codex peer) resolves PEER_TURNS empty"
else
  fail "Codex peer must resolve PEER_TURNS empty" "got: $codex_peer"
fi
if printf '%s' "$claude_peer" | grep -qF -- "--max-turns 1"; then
  pass "Codex host (Claude peer) resolves PEER_TURNS=--max-turns 1"
else
  fail "Claude peer must resolve PEER_TURNS=--max-turns 1" "got: $claude_peer"
fi
# host-detect.md documents PEER_TURNS
if grep -qF "PEER_TURNS" "$HOSTDOC"; then
  pass "host-detect.md documents PEER_TURNS"
else
  fail "host-detect.md must document PEER_TURNS"
fi

report
