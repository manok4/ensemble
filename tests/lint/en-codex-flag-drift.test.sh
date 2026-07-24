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

# === U2: no hardcoded --max-turns at any peer call site; PEER_TURNS used ===
# Scan the FULL peer-contract scope (refs + skills) for a hardcoded
# `$PEER_CMD $PEER_FORMAT --max-turns` invocation OR a `codex exec ... --max-turns`.
hardcoded=$(grep -rnE 'PEER_CMD \$PEER_FORMAT --max-turns|codex exec[^\n]*--max-turns' \
  "$REPO_ROOT/references" "$REPO_ROOT/skills" "$SETUP" 2>/dev/null || true)
if [ -z "$hardcoded" ]; then
  pass "no hardcoded \$PEER_CMD/codex-exec --max-turns remains in the peer contract"
else
  fail "a hardcoded --max-turns peer invocation survived" "$hardcoded"
fi
# Positively assert $PEER_TURNS is referenced at the executable call sites.
for f in "$OUTVOICE" "$HANDOFF"; do
  if grep -qF 'PEER_TURNS' "$f"; then
    pass "$(basename "$f") references \$PEER_TURNS"
  else
    fail "$(basename "$f") must use \$PEER_TURNS at its peer call site"
  fi
done

# === U3: setup smoke test drops codex --max-turns + classifies failures ===
if ! grep -qE 'codex exec[^\n]*--max-turns' "$SETUP"; then
  pass "setup Codex probe has no --max-turns"
else
  fail "setup Codex probe must not pass --max-turns"
fi
if grep -qiE "flag drift" "$SETUP" && grep -qiE "not authenticated|sign in" "$SETUP"; then
  pass "setup smoke test classifies flag-drift vs auth failure"
else
  fail "setup smoke test must distinguish flag drift from auth failure"
fi
# build-orchestration no longer tells the codex worker to pass --max-turns
if ! grep -qE 'max-turns.*(aggressively|30)' "$ORCH"; then
  pass "build-orchestration drops the invalid codex worker --max-turns guidance"
else
  fail "build-orchestration must drop the codex --max-turns worker guidance"
fi

# --- Stub-driven smoke-test classification (EN10-PR-002) ---
# Define the same classifier the setup uses and drive it with fake CLIs.
smoke_class() {
  local err rc out
  out=$("$@" </dev/null 2>&1 >/dev/null); rc=$?
  if [ "$rc" -eq 0 ]; then echo "ok"
  elif printf '%s' "$out" | grep -qiE 'unexpected argument|unrecognized (option|argument|subcommand)|invalid (option|value)|USAGE:|error: unknown'; then echo "flagdrift"
  elif printf '%s' "$out" | grep -qiE 'not logged in|unauthorized|authentication|not authenticated|please (run )?login|setup-token|sign in'; then echo "auth"
  else echo "unknown"; fi
}
STMP=$(mktemp -d)
printf '#!/usr/bin/env bash\necho "error: unexpected argument '"'"'--max-turns'"'"' found" >&2; exit 2\n' > "$STMP/drift"
printf '#!/usr/bin/env bash\necho "You are not logged in. Run codex login." >&2; exit 1\n' > "$STMP/auth"
printf '#!/usr/bin/env bash\necho "network unreachable" >&2; exit 1\n' > "$STMP/unk"
chmod +x "$STMP"/*
assert_eq "flagdrift" "$(smoke_class "$STMP/drift")" "stub: arg-parse error classifies as flag drift"
assert_eq "auth"      "$(smoke_class "$STMP/auth")"  "stub: auth error classifies as not-authenticated"
assert_eq "unknown"   "$(smoke_class "$STMP/unk")"   "stub: other error classifies as unknown"
rm -rf "$STMP"

# === U4: foundation D44 records the fix ===
d44="$(grep -E "^- \*\*D44\." "$FOUNDATION" || true)"
if [ -n "$d44" ] && printf '%s' "$d44" | grep -qF "PEER_TURNS" && printf '%s' "$d44" | grep -qiE "codex"; then
  pass "foundation D44 records the PEER_TURNS / Codex --max-turns fix"
else
  fail "foundation must add D44 naming PEER_TURNS + the Codex flag drift"
fi

report
