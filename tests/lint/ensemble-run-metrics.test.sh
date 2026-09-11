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

report
