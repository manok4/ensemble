#!/usr/bin/env bash
# tests/lint/peer-run-marker.test.sh
#
# `timeout` bounds a peer that runs too long, and exit 124 is reported as
# peer-failed:timeout. It cannot help when the HOST's tool call dies — context
# exhaustion, Ctrl-C, a truncated call. The subprocess dies with it and nothing is
# written, so the next step cannot tell "the peer was never asked" from "the peer
# answered nothing". That is the gap TD1 describes.
#
# A marker written before the call and cleared when a decision is emitted turns
# that silence into evidence. Deliberately not a job runner: no polling, no job
# roots, no process supervision — the reference implementation is 2,250 lines and
# 61 functions, and none of that is needed to make a death visible.
#
# The clear lives in _epi_decision rather than at each exit path, so an exit added
# later cannot leave a false orphan behind. A false orphan is worse than none: it
# reports an interruption that never happened.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="peer run marker"

. "$REPO_ROOT/skills/en-plan/scripts/ensemble-peer-invoke"
TMP=$(mktemp -d); OUT="$TMP/peer.json"

# --- the marker exists for the window the call is in flight ------------------
_epi_marker_write "$OUT" "codex" "cross-agent"; _epi_marker_out="$OUT"
[ -f "$OUT.run" ] && pass "a marker is written before the peer runs" \
                  || fail "a marker is written before the peer runs"

_epi_decision "on" "default-on" "cross-agent" "medium" "" "42" >/dev/null
[ -f "$OUT.run" ] && fail "emitting a decision clears the marker" \
                  || pass "emitting a decision clears the marker"

# --- a killed host call is visible to the next invocation --------------------
_epi_marker_write "$OUT" "codex" "cross-agent"; _epi_marker_out="$OUT"
if ensemble_peer_orphaned_run "$OUT" >/dev/null 2>&1; then
  pass "an interrupted run is reported as an orphan"
else
  fail "an interrupted run is reported as an orphan"
fi

# The orphan must carry enough to act on: when, which peer, which mode.
orphan=$(ensemble_peer_orphaned_run "$OUT" 2>/dev/null)
for k in started peer_cmd peer_mode; do
  printf '%s' "$orphan" | grep -q "\"$k\"" \
    && pass "the orphan record carries: $k" \
    || fail "the orphan record carries: $k"
done
printf '%s' "$orphan" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
  && pass "the orphan record is valid JSON" || fail "the orphan record is valid JSON"
rm -f "$OUT.run"

# --- no marker, no orphan ----------------------------------------------------
# The common case must stay silent, or every run reports a phantom interruption.
if ensemble_peer_orphaned_run "$OUT" >/dev/null 2>&1; then
  fail "a clean state reports no orphan"
else
  pass "a clean state reports no orphan"
fi

# --- /dev/null callers are unharmed ------------------------------------------
# out_file defaults to /dev/null; writing "/dev/null.run" would litter the cwd.
_epi_marker_write "/dev/null" "codex" "cross-agent"
[ -f "/dev/null.run" ] && fail "a /dev/null out_file writes no marker" \
                       || pass "a /dev/null out_file writes no marker"
ensemble_peer_orphaned_run "/dev/null" >/dev/null 2>&1 \
  && fail "a /dev/null out_file reports no orphan" \
  || pass "a /dev/null out_file reports no orphan"

# --- elapsed travels with every decision, so the ceiling is tunable ----------
# The 600s default was never measured against anything. Real calls in one session
# ran 141-242s; recording elapsed turns the next tuning into evidence.
el=$(_epi_decision "on" "default-on" "cross-agent" "medium" "" "195" | python3 -c 'import json,sys; print(json.load(sys.stdin)["elapsed_s"])')
assert_eq "$el" "195" "elapsed_s travels with the decision"

el=$(_epi_decision "off" "peer-failed:timeout" "cross-agent" "medium" "" | python3 -c 'import json,sys; print(json.load(sys.stdin)["elapsed_s"])')
assert_eq "$el" "None" "elapsed_s is null when it was not measured"

# --- the clear is centralized, not per-exit ---------------------------------
INV="$REPO_ROOT/skills/en-plan/scripts/ensemble-peer-invoke"
n_dec=$(grep -c '_epi_decision "' "$INV")
n_el=$(grep -c '_t0 ))"' "$INV")
assert_eq "$n_el" "$n_dec" "every decision call reports elapsed"

grep -q '_epi_marker_clear "\$_epi_marker_out"' "$INV" \
  && pass "the marker is cleared inside _epi_decision" \
  || fail "the marker is cleared inside _epi_decision"

if grep -q '_epi_marker_clear "\$out_file"' "$INV"; then
  fail "no per-exit-path marker clears remain"
else
  pass "no per-exit-path marker clears remain"
fi

# --- all carriers identical --------------------------------------------------
# 5 -> 4 on 2026-08-31: D52 left en-build dispatching no peer of its own, so it
# stopped carrying the invoker. The four that remain all invoke it by name.
n=$(ls "$REPO_ROOT"/skills/*/scripts/ensemble-peer-invoke 2>/dev/null | wc -l | tr -d ' ')
# 4 -> 3 on 2026-09-01: en-cross-review merged into /en-review as its --peer
# mode, so its copy of the invoker went with it.
assert_eq "$n" "3" "three skills carry the peer invoker"
d=$(for f in "$REPO_ROOT"/skills/*/scripts/ensemble-peer-invoke; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
assert_eq "$d" "1" "every carried copy is byte-identical"

rm -rf "$TMP"
report
