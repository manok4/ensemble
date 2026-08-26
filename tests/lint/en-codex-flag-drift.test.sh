#!/usr/bin/env bash
# Drift guards for EN10 — the Codex `--max-turns` flag drift fix.
# codex-cli 0.144.0 removed --max-turns (codex exec is single-shot); the peer
# contract resolves the turn cap per-agent via PEER_TURNS (--max-turns 1 for
# claude -p, empty for codex exec) instead of hardcoding it. This guard fails if
# any peer-contract reference or `setup` re-introduces a hardcoded Codex
# --max-turns, and it exercises the REAL smoke-test classifier + a hermetic
# host-detection check (stub CLIs on an isolated PATH).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-codex flag drift"

DETECT="$REPO_ROOT/shared/bin/ensemble-detect-host"
HOSTDOC="$REPO_ROOT/shared/references/host-detect.md"
OUTVOICE="$REPO_ROOT/shared/references/outside-voice.md"
HANDOFF="$REPO_ROOT/shared/references/build-handoff.md"
ORCH="$REPO_ROOT/shared/references/build-orchestration.md"
SETUP="$REPO_ROOT/setup"
FOUNDATION="$REPO_ROOT/docs/foundation.md"
SMOKE="$REPO_ROOT/shared/bin/ensemble-cli-smoke"

# ============================================================
# U1: detect-host emits PEER_TURNS, resolved per peer agent (hermetic)
# ============================================================
if grep -qF "PEER_TURNS" "$DETECT"; then
  pass "ensemble-detect-host emits PEER_TURNS"
else
  fail "ensemble-detect-host must emit PEER_TURNS"; report
fi

# Build an isolated PATH dir: symlinks to the coreutils detect-host needs, plus
# only the requested CLI stubs — so peer availability is fully controlled.
mkstub() {  # $1=dir ; $2.. = CLI names to stub as present
  local dir="$1"; shift; local t src
  mkdir -p "$dir"
  for t in cat dirname jq mkdir sed grep bash env printf head tr; do
    src=$(command -v "$t" 2>/dev/null) && ln -sf "$src" "$dir/$t" 2>/dev/null || true
  done
  for cli in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$dir/$cli"; chmod +x "$dir/$cli"; done
}
peer_turns() {  # $1=stubdir ; $2.. = env assignments -> prints PEER_TURNS value (unquoted)
  local stub="$1"; shift; local hometmp; hometmp=$(mktemp -d)
  env -i PATH="$stub" HOME="$hometmp" "$@" bash "$DETECT" --no-cache 2>/dev/null \
    | sed -n "s/^PEER_TURNS=//p" | sed "s/^'//; s/'$//"
  rm -rf "$hometmp"
}
STUBROOT=$(mktemp -d)
mkstub "$STUBROOT/both" claude codex
mkstub "$STUBROOT/claudeonly" claude
mkstub "$STUBROOT/codexonly" codex

assert_eq ""              "$(peer_turns "$STUBROOT/both" CLAUDE_CODE_VERSION=1)"   "dual-agent, Claude host -> Codex peer -> PEER_TURNS empty"
assert_eq "--max-turns 1" "$(peer_turns "$STUBROOT/both" ENSEMBLE_HOST=codex)"     "dual-agent, Codex host -> Claude peer -> PEER_TURNS=--max-turns 1"
assert_eq "--max-turns 1" "$(peer_turns "$STUBROOT/claudeonly" CLAUDE_CODE_VERSION=1)" "single-agent Claude -> fallback peer claude -> --max-turns 1"
assert_eq ""              "$(peer_turns "$STUBROOT/codexonly" ENSEMBLE_HOST=codex)" "single-agent Codex -> fallback peer codex -> empty"
rm -rf "$STUBROOT"

if grep -qF "PEER_TURNS" "$HOSTDOC"; then
  pass "host-detect.md documents PEER_TURNS"
else
  fail "host-detect.md must document PEER_TURNS"
fi

# ============================================================
# U2: no hardcoded --max-turns at any peer call site; PEER_TURNS used
# ============================================================
# Line-oriented patterns (a `[^\n]` class is NOT a newline exclusion in POSIX
# ERE and misses on GNU grep — EN10-CR-003).
DRIFT_PAT_A='PEER_CMD \$PEER_FORMAT --max-turns'
# Executable form only: a flag must follow `codex exec` (prose mentions like
# "for `codex exec`, which removed `--max-turns`" have a backtick/word there, not
# a `--flag`, so they don't match). Line-oriented `.` (not the broken `[^\n]`
# class, which GNU grep reads as "not backslash-or-n" — EN10-CR-003).
DRIFT_PAT_B='codex exec --[a-z].*--max-turns'
# Self-test: the pattern MUST catch a known regression, and must NOT catch prose.
if printf 'codex exec --json --max-turns 1\n' | grep -qE "$DRIFT_PAT_B" \
   && ! printf 'empty for `codex exec`, which removed `--max-turns`\n' | grep -qE "$DRIFT_PAT_B"; then
  pass "self-test: drift pattern catches the executable regression, not prose"
else
  fail "self-test: drift pattern mis-classifies the regression or prose"
fi
hardcoded=$(grep -rnE "$DRIFT_PAT_A|$DRIFT_PAT_B" \
  "$REPO_ROOT/references" "$REPO_ROOT/skills" "$SETUP" 2>/dev/null || true)
if [ -z "$hardcoded" ]; then
  pass "no hardcoded \$PEER_CMD/codex-exec --max-turns remains in the peer contract"
else
  fail "a hardcoded --max-turns peer invocation survived" "$hardcoded"
fi
for f in "$OUTVOICE" "$HANDOFF"; do
  if grep -qF 'PEER_TURNS' "$f"; then
    pass "$(basename "$f") references \$PEER_TURNS"
  else
    fail "$(basename "$f") must use \$PEER_TURNS at its peer call site"
  fi
done
# EN10-CR-001: outside-voice's Claude-only isolation flags are conditional, not
# appended to a shared $PEER_CMD (which could be codex).
if grep -qiE "isolation flags are Claude-CLI-only|CLAUDE_ISOLATION" "$OUTVOICE"; then
  pass "outside-voice scopes the Claude-only isolation flags conditionally (not on a codex peer)"
else
  fail "outside-voice must not append Claude-only isolation flags to a shared \$PEER_CMD"
fi

# ============================================================
# U3: setup drops codex --max-turns + classifies failures (via the REAL helper)
# ============================================================
if ! grep -qE 'codex exec.*--max-turns' "$SETUP"; then
  pass "setup Codex probe has no --max-turns"
else
  fail "setup Codex probe must not pass --max-turns"
fi
if ! grep -qE 'max-turns.*(aggressively|30)' "$ORCH"; then
  pass "build-orchestration drops the invalid codex worker --max-turns guidance"
else
  fail "build-orchestration must drop the codex --max-turns worker guidance"
fi
# setup sources the shared classifier (so this test exercises the real one).
if grep -qF "ensemble-cli-smoke" "$SETUP" && [ -f "$SMOKE" ]; then
  pass "setup sources the shared ensemble-cli-smoke classifier"
else
  fail "setup must source bin/ensemble-cli-smoke (shared with this test)"
fi

# Drive the REAL classifier (sourced, not reimplemented — EN10-CR-004) with stubs.
# shellcheck source=/dev/null
. "$SMOKE"
STMP=$(mktemp -d)
printf '#!/usr/bin/env bash\necho "error: unexpected argument '"'"'--max-turns'"'"' found" >&2; exit 2\n' > "$STMP/drift"
printf '#!/usr/bin/env bash\necho "You are not logged in. Run codex login." >&2; exit 1\n' > "$STMP/auth"
printf '#!/usr/bin/env bash\necho "network unreachable" >&2; exit 1\n' > "$STMP/unk"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STMP/ok"
chmod +x "$STMP"/*
cls() {  # run a stub, capture stderr+rc errexit-safely, classify via the real fn
  local err rc
  if err=$("$1" </dev/null 2>&1 >/dev/null); then rc=0; else rc=$?; fi
  ensemble_smoke_classify "$err" "$rc"
}
assert_eq "flagdrift" "$(cls "$STMP/drift")" "real classifier: arg-parse error -> flag drift"
assert_eq "auth"      "$(cls "$STMP/auth")"  "real classifier: auth error -> not-authenticated"
assert_eq "unknown"   "$(cls "$STMP/unk")"   "real classifier: other error -> unknown"
assert_eq "ok"        "$(cls "$STMP/ok")"    "real classifier: exit 0 -> ok"
# The probe wrapper prints the classified line and does not crash under set -e.
probe_out=$(set -e; ensemble_smoke_probe "Stub CLI" "$STMP/drift")
if printf '%s' "$probe_out" | grep -qi "flag drift"; then
  pass "ensemble_smoke_probe prints a classified line (errexit-safe)"
else
  fail "ensemble_smoke_probe output unexpected" "$probe_out"
fi
rm -rf "$STMP"

# ============================================================
# U4: foundation D44 records the fix
# ============================================================
d44="$(grep -E "^- \*\*D44\." "$FOUNDATION" || true)"
if [ -n "$d44" ] && printf '%s' "$d44" | grep -qF "PEER_TURNS" && printf '%s' "$d44" | grep -qiE "codex"; then
  pass "foundation D44 records the PEER_TURNS / Codex --max-turns fix"
else
  fail "foundation must add D44 naming PEER_TURNS + the Codex flag drift"
fi

report
