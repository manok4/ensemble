#!/usr/bin/env bash
# tests/lint/ensemble-run-metrics.test.sh
#
# ensemble-run-metrics existed for weeks and wrote nothing, because recording
# was the model's job and the model forgot. EN17 moves it into the helpers, and
# the property that makes that possible is addressing: a helper anywhere in the
# repo must find the current run WITHOUT being handed a path and WITHOUT an
# environment variable, because every tool call here is a fresh shell.
#
# Guarded here:
#
#   ADDRESSING WITHOUT ARGUMENTS   `emit` resolves the ledger from a file on
#                                  disk, so a helper invoked from another
#                                  directory in another shell still lands.
#   SILENCE IS THE DEFAULT         outside a run, emit writes nothing, creates
#                                  nothing, and exits 0. Every existing test of
#                                  every emitter depends on this.
#   A CLOSED RUN STAYS CLOSED      liveness is the absence of a finish event
#                                  anywhere in the ledger, not a last-line test:
#                                  an event arriving after finish must not
#                                  resurrect the run.
#   OPT-OUT MEANS OPT-OUT          checked by every subcommand, not just start.
#                                  A run begun before the operator opted out
#                                  must stop recording, and must still leave
#                                  the active stack.
#
# Negative controls at authoring: deleting the `active` fallback in
# _resolve_ledger turned the cross-directory and nesting assertions red;
# testing liveness on the last line alone turned the late-event assertion red;
# skipping the active pop when opted out turned the phantom-parent assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-run-metrics ledger addressing"

RM="$REPO_ROOT/skills/en-build/scripts/ensemble-run-metrics"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# A throwaway repo. Every call below runs inside it, never in the real one.
PROJ="$WORK/proj"
mkdir -p "$PROJ/sub/deeper"
cd "$PROJ"
git init -q .
git config user.email t@example.com
git config user.name T
GIT_DIR_ABS="$PROJ/.git"
RUNS="$GIT_DIR_ABS/ensemble/runs"
ACTIVE="$RUNS/active"

# Each call is its own process with a clean environment, which is the point:
# nothing may be carried between them but the filesystem.
rm_() { env -u ENSEMBLE_RUN_LEDGER bash "$RM" "$@"; }

# --- 1. addressing without arguments, from another directory -----------------
L1=$(cd "$PROJ" && rm_ start --skill en-build --plan EN17)
assert_contains "$L1" "en-build-" "start prints the ledger path"
assert_file_exists "$L1" "start creates the ledger"
assert_file_exists "$ACTIVE" "start registers the run on the active stack"
assert_eq "1" "$(wc -l < "$ACTIVE" | tr -d ' ')" "active holds exactly one line"

( cd "$PROJ/sub/deeper" && env -u ENSEMBLE_RUN_LEDGER bash "$RM" emit --kind lint --json '{"scope":"docs"}' )
n=$(grep -c '"kind":"lint"' "$L1" || true)
assert_eq "1" "$n" "emit from another directory, with no env and no path, lands in the run"

# --- 2. nesting: child ledger, parent pointer --------------------------------
L2=$(rm_ start --skill en-review)
assert_ne "$L1" "$L2" "a nested start mints its own ledger"
parent_id=$(head -1 "$L1" | jq -r '.run_id')
child_parent=$(head -1 "$L2" | jq -r '.parent_run_id')
assert_eq "$parent_id" "$child_parent" "the child records the parent's run_id"
ptr=$(grep '"kind":"child"' "$L1" | jq -r '.ledger')
assert_eq "$L2" "$ptr" "the parent holds a pointer to the child's ledger"
assert_eq "2" "$(wc -l < "$ACTIVE" | tr -d ' ')" "active holds both runs"

rm_ emit --kind lint --json '{"scope":"nested"}'
assert_eq "1" "$(grep -c '"scope":"nested"' "$L2" || true)" "emit targets the innermost run"
assert_eq "0" "$(grep -c '"scope":"nested"' "$L1" || true)" "the parent does not also receive it"

# --- 3. unwinding ------------------------------------------------------------
rm_ finish "$L2"
assert_eq "1" "$(wc -l < "$ACTIVE" | tr -d ' ')" "finish pops the child off the stack"
rm_ emit --kind lint --json '{"scope":"back-to-parent"}'
assert_eq "1" "$(grep -c '"scope":"back-to-parent"' "$L1" || true)" "emit targets the parent again"

# --- 4. out-of-order finish: pop by path, not by position --------------------
L3=$(rm_ start --skill en-ship)
rm_ finish "$L1"                       # the PARENT finishes while the child lives
assert_eq "1" "$(wc -l < "$ACTIVE" | tr -d ' ')" "the parent's line is removed by path"
assert_contains "$(cat "$ACTIVE")" "$L3" "the still-open child survives the parent's finish"
rm_ emit --kind lint --json '{"scope":"orphan"}'
assert_eq "1" "$(grep -c '"scope":"orphan"' "$L3" || true)" "emit still targets the surviving run"
rm_ finish "$L3"

# --- 5. the env var overrides the stack --------------------------------------
L4=$(rm_ start --skill en-build)
OVER="$WORK/override.jsonl"
: > "$OVER"
before=$(shasum "$ACTIVE" | awk '{print $1}')
ENSEMBLE_RUN_LEDGER="$OVER" bash "$RM" emit --kind lint --json '{"scope":"override"}'
assert_eq "1" "$(grep -c '"scope":"override"' "$OVER" || true)" "ENSEMBLE_RUN_LEDGER wins over the stack"
assert_eq "0" "$(grep -c '"scope":"override"' "$L4" || true)" "the stack's run is untouched"
assert_eq "$before" "$(shasum "$ACTIVE" | awk '{print $1}')" "active is not consulted or rewritten"
rm_ finish "$L4"

# --- 6. pruning: a deleted ledger and a finished one -------------------------
L5=$(rm_ start --skill en-build)
rm -f "$L5"                            # the ledger vanishes, the entry remains
assert_eq "1" "$(wc -l < "$ACTIVE" | tr -d ' ')" "the stale entry is still on the stack"
rm_ emit --kind lint --json '{"scope":"gone"}'
assert_file_missing "$L5" "an emit against a vanished ledger recreates nothing"
L6=$(rm_ start --skill en-plan)
assert_eq "1" "$(wc -l < "$ACTIVE" | tr -d ' ')" "start prunes the vanished entry"
assert_eq "null" "$(head -1 "$L6" | jq -r '.parent_run_id')" "a pruned entry does not become a phantom parent"

# --- 7. late event after finish: a closed run stays closed -------------------
rm_ finish "$L6"
printf '{"kind":"note","at":"2026-01-01T00:00:00Z"}\n' >> "$L6"   # arrives after finish
printf '%s\t%s\n' "late" "$L6" >> "$ACTIVE"                       # and back on the stack
L7=$(rm_ start --skill en-build)
assert_eq "null" "$(head -1 "$L7" | jq -r '.parent_run_id')" \
  "a ledger with a finish event is dead even when another line follows it"
rm_ finish "$L7"

# --- 8. no run: silence, and no directory -----------------------------------
BARE="$WORK/bare"
mkdir -p "$BARE"
( cd "$BARE" && git init -q . )
out=$(cd "$BARE" && env -u ENSEMBLE_RUN_LEDGER bash "$RM" emit --kind lint --json '{"scope":"x"}' 2>&1)
rc=$?
assert_eq "0" "$rc" "emit with no run exits 0"
assert_eq "" "$out" "emit with no run says nothing"
assert_file_missing "$BARE/.git/ensemble/runs/active" "emit with no run creates no run directory"

# --- 9. outside a git repository ---------------------------------------------
OUTSIDE="$WORK/outside"
mkdir -p "$OUTSIDE"
( cd "$OUTSIDE" && env -u ENSEMBLE_RUN_LEDGER bash "$RM" emit --kind lint --json '{"a":1}' ) >/dev/null 2>&1
assert_exit_code 0 $? "emit outside a git repo exits 0"

# --- 10. malformed payloads leave the ledger byte-unchanged ------------------
L8=$(rm_ start --skill en-build)
rm_ emit --kind lint --json '{"ok":1}'
h=$(shasum "$L8" | awk '{print $1}')
rm_ emit --kind lint --json 'not json'  >/dev/null 2>&1
rm_ emit --kind lint --json '[1,2]'     >/dev/null 2>&1
assert_eq "$h" "$(shasum "$L8" | awk '{print $1}')" "a malformed payload leaves the ledger byte-unchanged"
rm_ emit --kind nonsense --json '{}'    >/dev/null 2>&1
assert_eq "$h" "$(shasum "$L8" | awk '{print $1}')" "an unknown kind leaves the ledger byte-unchanged"

# --- 11. an unwritable runs directory is not fatal ---------------------------
chmod 500 "$RUNS"
rm_ emit --kind lint --json '{"scope":"ro"}' >/dev/null 2>&1
assert_exit_code 0 $? "emit into a read-only runs directory exits 0"
chmod 700 "$RUNS"

# --- 12. concurrent appends --------------------------------------------------
for i in $(seq 1 20); do rm_ emit --kind note --json "{\"i\":$i}" & done
wait
good=$(grep -c '"kind":"note"' "$L8" || true)
assert_eq "20" "$good" "twenty concurrent appends produce twenty lines"
bad=0
while IFS= read -r line; do printf '%s' "$line" | jq -e . >/dev/null 2>&1 || bad=$((bad+1)); done < "$L8"
assert_eq "0" "$bad" "every line parses as JSON after concurrent appends"
rm_ finish "$L8"

# --- 13. opt-out via ENSEMBLE_METRICS ----------------------------------------
out=$(ENSEMBLE_METRICS=off bash "$RM" start --skill en-build 2>/dev/null)
assert_eq "" "$out" "ENSEMBLE_METRICS=off makes start print nothing"

# --- 14. opt-out via config, including mid-run -------------------------------
L9=$(rm_ start --skill en-build)
rm_ emit --kind lint --json '{"scope":"before-optout"}'
h9=$(shasum "$L9" | awk '{print $1}')
mkdir -p "$PROJ/.ensemble"
printf 'metrics:\n  enabled: false\n' > "$PROJ/.ensemble/config.local.yaml"
out=$(rm_ start --skill en-review 2>/dev/null)
assert_eq "" "$out" "config opt-out makes start print nothing"
rm_ emit --kind lint --json '{"scope":"after-optout"}'
assert_eq "$h9" "$(shasum "$L9" | awk '{print $1}')" "emit records nothing once opted out"
rm_ finish "$L9"
assert_eq "$h9" "$(shasum "$L9" | awk '{print $1}')" "finish appends no event once opted out"
assert_eq "0" "$(wc -c < "$ACTIVE" | tr -d ' ')" "finish still pops the stack while opted out"

# The phantom-parent case: without that pop, the abandoned run parents the next.
rm -f "$PROJ/.ensemble/config.local.yaml"
L10=$(rm_ start --skill en-build)
assert_eq "null" "$(head -1 "$L10" | jq -r '.parent_run_id')" \
  "a run finished while opted out leaves no phantom parent"
rm_ finish "$L10"

# A metrics block without `enabled`, and enabled:true, both leave recording on.
printf 'metrics:\n  note: hello\n' > "$PROJ/.ensemble/config.local.yaml"
out=$(rm_ start --skill en-build 2>/dev/null)
assert_ne "" "$out" "a metrics block with no enabled key leaves recording on"
rm_ finish "$out"
printf 'metrics:\n  enabled: true\n' > "$PROJ/.ensemble/config.local.yaml"
out=$(rm_ start --skill en-build 2>/dev/null)
assert_ne "" "$out" "enabled: true leaves recording on"
rm_ finish "$out"
rm -f "$PROJ/.ensemble/config.local.yaml"

# --- 15. the explicit-file form still works ----------------------------------
L11=$(rm_ start --skill en-build)
rm_ event "$L11" --kind dispatch --json '{"agent":"repo-research"}'
assert_eq "1" "$(grep -c '"agent":"repo-research"' "$L11" || true)" \
  "the pre-existing 'event <file>' form is unchanged"
s=$(rm_ summary "$L11")
assert_contains "$s" "1 dispatches" "summary still reads the ledger"
rm_ finish "$L11"

# --- 16. the per-kind key allowlist (U2) -------------------------------------
# The allowlist is the design's privacy boundary: one place decides what can
# reach disk, so nothing downstream has to re-filter and nothing can drift.
L12=$(rm_ start --skill en-build)
last() { tail -1 "$L12"; }

rm_ emit --kind select --json '{"tier":"graph","reason":"changed 2 files","count":4,"total":260}'
assert_eq "graph" "$(last | jq -r '.tier')"    "an allowed key survives"
assert_eq "4"     "$(last | jq -r '.count')"   "all four select keys survive"
assert_eq "null"  "$(last | jq -r '.dropped')" "a clean payload carries no dropped count"

# A path from the emitting machine is exactly what must never reach disk.
err=$(rm_ emit --kind select --json '{"tier":"graph","cwd":"/Users/someone/secret-project"}' 2>&1)
assert_eq "graph" "$(last | jq -r '.tier')"     "the allowed key is still written"
assert_eq "null"  "$(last | jq -r '.cwd')"      "an unknown key is dropped before the write"
assert_eq "1"     "$(last | jq -r '.dropped')"  "the written line counts the drop"
assert_contains "$err" "cwd" "the dropped key is named on stderr"

rm_ emit --kind select --json '{"nope":1,"also":2}' 2>/dev/null
assert_eq "select" "$(last | jq -r '.kind')"   "a payload of only unknown keys still writes its kind"
assert_eq "2"      "$(last | jq -r '.dropped')" "and counts every drop"

rm_ emit --kind select --json '{}'
assert_eq "null" "$(last | jq -r '.dropped')" "an empty payload carries no dropped count"

# The eight keys ensemble-peer-invoke will pass, all of them.
rm_ emit --kind peer --json '{"peer":"codex","decision":"on","reason":"default-on","peer_mode":"cross-agent","effort":"high","model_alias":"gpt-5.6-sol","model_actual":"gpt-5.6-sol","elapsed_s":126}'
assert_eq "null" "$(last | jq -r '.dropped')" "all eight peer keys survive"
assert_eq "126"  "$(last | jq -r '.elapsed_s')" "elapsed_s reaches disk"

# An unknown KIND stays a rejection, not a drop: the kind names the schema.
h=$(shasum "$L12" | awk '{print $1}')
rm_ emit --kind nonsense --json '{"tier":"graph"}' 2>/dev/null
assert_eq "$h" "$(shasum "$L12" | awk '{print $1}')" "an unknown kind is rejected, not filtered"

# --- 17. nothing already recorded starts being dropped -----------------------
# Each payload below is the shape references/run-metrics.md documents. If this
# block goes red, the allowlist broke what /en-build and /en-plan already write.
check_kind() {  # <kind> <payload>
  rm_ emit --kind "$1" --json "$2"
  assert_eq "$1"   "$(last | jq -r '.kind')"    "kind '$1' is accepted and written"
  assert_eq "null" "$(last | jq -r '.dropped')" "kind '$1' keeps every documented key"
}
check_kind dispatch '{"agent":"repo-research","host":"claude-code","model":null,"model_source":"inherit","started":1,"ended":2}'
check_kind peer     '{"iteration":1,"peer_decision":{"peer":"codex"},"tokens":{"input":null,"output":null}}'
check_kind lint     '{"scope":"docs","seconds":3}'
check_kind findings '{"iteration":1,"P0":0,"P1":3,"P2":5,"P3":2}'
check_kind unit     '{"unit":"U3","event":"end","commit":"a3f1b9c","verify_exit":0,"selection_tier":"graph"}'
check_kind phase    '{"checkpoint":"end-of-loop","event":"end","units":5,"outcome":"passed"}'
check_kind suite    '{"where":"post-build","seconds":286,"outcome":"passed"}'
check_kind review   '{"event":"end","reviewer":"cross-agent","findings":11,"personas":[{"dimension":"testing","seconds":null}]}'
check_kind note     '{"message":"hello","detail":"world"}'
check_kind child    '{"run_id":"r1","skill":"en-review","ledger":"/tmp/x.jsonl"}'
check_kind verify   '{"unit":"U3","tier":"graph","ran":3,"failed":0,"rc":0,"checks":[]}'
check_kind receipt  '{"op":"verify","result":"hit","reason":"ok","age_s":42,"checks":["full_suite"]}'
check_kind outcome  '{"result":"ok","verdict":"revise","findings_total":9,"peer_only":3,"corroborated":4,"host_only":2,"applied":6,"deferred":2,"disagreed":1,"units_total":5,"units_done":5,"gates_failed":0}'

# The explicit-file form filters identically; one allowlist, not two.
rm_ event "$L12" --kind lint --json '{"scope":"docs","cwd":"/Users/someone"}' 2>/dev/null
assert_eq "null" "$(last | jq -r '.cwd')"     "the explicit-file form filters through the same allowlist"
assert_eq "1"    "$(last | jq -r '.dropped')" "the explicit-file form counts drops too"
rm_ finish "$L12"

report
