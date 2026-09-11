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
#   ONLY NAMED KEYS REACH DISK     the per-kind allowlist drops the rest, loudly,
#                                  and gates the VALUES of the one kind a model
#                                  composes.
#   A RUN IS PUBLISHED ONCE        marked, then published, then closed; the
#                                  rollup is idempotent across both retained
#                                  generations and its rotation is serialized.
#   NOTHING NEEDS A VARIABLE       finish and summary resolve the run the way
#                                  emit does, because the variable they used to
#                                  take does not survive between tool calls.
#
# Negative controls at authoring: deleting the `active` fallback in
# _resolve_ledger turned the cross-directory and nesting assertions red;
# testing liveness on the last line alone turned the late-event assertion red;
# skipping the active pop when opted out turned the phantom-parent assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-run-metrics: addressing, allowlist, rollup"

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

# EXPORTED BEFORE THE FIRST CALL, not halfway down. `finish` writes the rollup,
# so a section that drives it before this line is set appends to the operator's
# real ~/.ensemble/analytics — which is exactly what this suite found itself
# doing, 156 lines into their store, on the run that added the rollup.
ADIR="$WORK/analytics"
export ENSEMBLE_ANALYTICS_DIR="$ADIR"

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
rm_ emit --kind lint --json '{"scope":"back-to-parent"}'
assert_eq "1" "$(grep -c '"scope":"back-to-parent"' "$L1" || true)" "emit targets the parent again"

# --- 4. out-of-order finish: pop by path, not by position --------------------
L3=$(rm_ start --skill en-ship)
rm_ finish "$L1"                       # the PARENT finishes while the child lives
rm_ emit --kind lint --json '{"scope":"orphan"}'
assert_eq "1" "$(grep -c '"scope":"orphan"' "$L3" || true)" "emit still targets the surviving run"
rm_ finish "$L3"

# --- 5. the env var overrides the stack --------------------------------------
L4=$(rm_ start --skill en-build)
OVER="$WORK/override.jsonl"
: > "$OVER"
before=$(hash_file "$ACTIVE")
ENSEMBLE_RUN_LEDGER="$OVER" bash "$RM" emit --kind lint --json '{"scope":"override"}'
assert_eq "1" "$(grep -c '"scope":"override"' "$OVER" || true)" "ENSEMBLE_RUN_LEDGER wins over the stack"
assert_eq "0" "$(grep -c '"scope":"override"' "$L4" || true)" "the stack's run is untouched"
assert_eq "$before" "$(hash_file "$ACTIVE")" "active is not consulted or rewritten"
rm_ finish "$L4"

# --- 6. pruning: a deleted ledger and a finished one -------------------------
L5=$(rm_ start --skill en-build)
rm -f "$L5"                            # the ledger vanishes; its log lines stay
rm_ emit --kind lint --json '{"scope":"gone"}'
assert_file_missing "$L5" "an emit against a vanished ledger recreates nothing"
L6=$(rm_ start --skill en-plan)
assert_eq "null" "$(head -1 "$L6" | jq -r '.parent_run_id')" \
  "a run whose ledger vanished does not become a phantom parent"

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
h=$(hash_file "$L8")
rm_ emit --kind lint --json 'not json'  >/dev/null 2>&1
rm_ emit --kind lint --json '[1,2]'     >/dev/null 2>&1
assert_eq "$h" "$(hash_file "$L8")" "a malformed payload leaves the ledger byte-unchanged"
rm_ emit --kind nonsense --json '{}'    >/dev/null 2>&1
assert_eq "$h" "$(hash_file "$L8")" "an unknown kind leaves the ledger byte-unchanged"

# --- 11. an unwritable LEDGER is not fatal -----------------------------------
# chmod 500 on the directory proved nothing: the ledger already existed and an
# append needs no directory write, so the emit succeeded and the failure path
# this names was never entered.
h=$(hash_file "$L8")
chmod 400 "$L8"
err=$(rm_ emit --kind lint --json '{"scope":"ro"}' 2>&1); rc=$?
chmod 600 "$L8"
assert_exit_code 0 $rc "an emit against an unwritable ledger still exits 0"
assert_eq "$h" "$(hash_file "$L8")" "and writes nothing"
assert_contains "$err" "cannot append" "and says so once, on stderr"

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
h9=$(hash_file "$L9")
mkdir -p "$PROJ/.ensemble"
printf 'metrics:\n  enabled: false\n' > "$PROJ/.ensemble/config.local.yaml"
out=$(rm_ start --skill en-review 2>/dev/null)
assert_eq "" "$out" "config opt-out makes start print nothing"
rm_ emit --kind lint --json '{"scope":"after-optout"}'
assert_eq "$h9" "$(hash_file "$L9")" "emit records nothing once opted out"
rm_ finish "$L9"
assert_eq "$h9" "$(hash_file "$L9")" "finish appends no event once opted out"

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
h=$(hash_file "$L12")
rm_ emit --kind nonsense --json '{"tier":"graph"}' 2>/dev/null
assert_eq "$h" "$(hash_file "$L12")" "an unknown kind is rejected, not filtered"

# --- 17. nothing already recorded starts being dropped -----------------------
# Each payload below is the shape references/run-metrics.md documents. If this
# block goes red, the allowlist broke what /en-build and /en-plan already write.
check_kind() {  # <kind> <payload>
  rm_ emit --kind "$1" --json "$2"
  assert_eq "$1"   "$(last | jq -r '.kind')"    "kind '$1' is accepted and written"
  assert_eq "null" "$(last | jq -r '.dropped')" "kind '$1' keeps every documented key"
}
check_kind dispatch '{"agent":"repo-research","host":"claude-code","model":null,"model_source":"inherit","started":1,"ended":2}'
check_kind peer     '{"iteration":1,"peer":"codex","decision":"on","elapsed_s":126}'
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
check_kind outcome  '{"verdict":"revise","findings_total":9,"peer_only":3,"corroborated":4,"host_only":2,"applied":6,"deferred":2,"disagreed":1}'

# The explicit-file form filters identically; one allowlist, not two.
rm_ event "$L12" --kind lint --json '{"scope":"docs","cwd":"/Users/someone"}' 2>/dev/null
assert_eq "null" "$(last | jq -r '.cwd')"     "the explicit-file form filters through the same allowlist"
assert_eq "1"    "$(last | jq -r '.dropped')" "the explicit-file form counts drops too"
rm_ finish "$L12"

# --- 18. the durable rollup (U3) ---------------------------------------------
# One line per run, in the only file that survives the clone. ENSEMBLE_ANALYTICS_DIR
# is what keeps this suite out of the operator's real store; without it, this
# test would do to <repo>.jsonl exactly what check-guardrail.test.sh did to
# guardrail.jsonl for four months.
ROLL="$ADIR/proj.jsonl"
# Sections 1-17 finished runs too, so the rollup already holds their lines.
rm -f "$ROLL" "$ROLL.1"
rmA() { env -u ENSEMBLE_RUN_LEDGER ENSEMBLE_ANALYTICS_DIR="$ADIR" bash "$RM" "$@"; }

L13=$(rmA start --skill en-review --plan EN17)
rmA emit --kind select --json '{"tier":"graph","reason":"two files","count":4,"total":260}'
rmA emit --kind peer   --json '{"peer":"codex","decision":"on","elapsed_s":126}'
rmA emit --kind peer   --json '{"peer":"codex","decision":"degraded","elapsed_s":31}'
rmA emit --kind outcome --json '{"findings_total":9,"peer_only":3,"corroborated":4,"host_only":2}'
rmA finish "$L13"

assert_file_exists "$ROLL" "finish writes one line to the repo's rollup"
assert_eq "1" "$(wc -l < "$ROLL" | tr -d ' ')" "exactly one line per run"
R=$(cat "$ROLL")
assert_eq "1"         "$(printf '%s' "$R" | jq -r '.schema')"          "the line is schema-versioned"
assert_eq "en-review" "$(printf '%s' "$R" | jq -r '.skill')"           "it names the skill"
assert_eq "EN17"      "$(printf '%s' "$R" | jq -r '.plan_id')"         "and the plan"
assert_eq "proj"      "$(printf '%s' "$R" | jq -r '.repo')"            "and the repo"
assert_eq "2"         "$(printf '%s' "$R" | jq -r '.counts.peer')"     "counts are per kind"
assert_eq "1"         "$(printf '%s' "$R" | jq -r '.counts.outcome')"  "including the outcome event"
assert_eq "2"         "$(printf '%s' "$R" | jq -r '.detail.peer|length')" "detail carries every peer pass"
assert_eq "126"       "$(printf '%s' "$R" | jq -r '.detail.peer[0].elapsed_s')" "in emit order"
assert_eq "graph"     "$(printf '%s' "$R" | jq -r '.detail.select.tier')" "and the selection tier"
assert_eq "260"       "$(printf '%s' "$R" | jq -r '.detail.select.total')" "and its ratio"
assert_eq "3"         "$(printf '%s' "$R" | jq -r '.outcome.peer_only')" "the outcome object is carried verbatim"
assert_eq "true"      "$(printf '%s' "$R" | jq -r '.duration_s >= 0')"  "duration_s is a non-negative integer"
assert_eq "null"      "$(printf '%s' "$R" | jq -r '.parent_run_id')"    "a top-level run has no parent"

# A nested pair, finished child first.
: > "$ROLL"
LP=$(rmA start --skill en-build)
LC=$(rmA start --skill en-review)
rmA finish "$LC"; rmA finish "$LP"
assert_eq "2" "$(wc -l < "$ROLL" | tr -d ' ')" "a nested pair leaves two rollup lines"
pid=$(head -1 "$LP" | jq -r '.run_id')
assert_eq "$pid" "$(jq -rs '.[] | select(.skill=="en-review") | .parent_run_id' "$ROLL")" \
  "the child's rollup line names the parent run"

# No outcome, no select: null rather than absent, so a reader can tell the
# difference between "did not happen" and "older schema".
: > "$ROLL"
L14=$(rmA start --skill en-ship); rmA finish "$L14"
assert_eq "null" "$(jq -r '.outcome' "$ROLL")"        "a run with no outcome records null, not absence"
assert_eq "null" "$(jq -r '.detail.select' "$ROLL")"  "a run with no selection records null"
assert_eq "0"    "$(jq -r '.detail.peer|length' "$ROLL")" "and an empty peer list"

# Finishing twice appends nothing the second time.
before=$(wc -l < "$ROLL" | tr -d ' ')
rmA finish "$L14"
assert_eq "$before" "$(wc -l < "$ROLL" | tr -d ' ')" "a second finish adds no second rollup line"

# --- 19. rotation at the size cap --------------------------------------------
seed_over_cap() { dd if=/dev/zero bs=1024 count=5121 2>/dev/null | tr '\0' 'x' | sed 's/^/{"seed":"/; s/$/"}/' > "$ROLL"; }
seed_over_cap
seeded=$(wc -c < "$ROLL" | tr -d ' ')
L15=$(rmA start --skill en-build); rmA finish "$L15"
assert_file_exists "$ROLL.1" "an over-cap file is rotated to .1"
assert_eq "$seeded" "$(wc -c < "$ROLL.1" | tr -d ' ')" "the whole previous generation moves intact"
assert_eq "1" "$(wc -l < "$ROLL" | tr -d ' ')" "the current file holds only the new line"

seed_over_cap
L16=$(rmA start --skill en-build); rmA finish "$L16"
assert_file_missing "$ROLL.2" "only one previous generation is kept"

# Contention must never cost an event, and must never duplicate one. A caller
# that cannot take the lock DEFERS: the run stays open and a later finish
# publishes it. Check, rotate and append are one transaction, so a writer that
# lost the rename can no longer append into the generation being expired.
rm -f "$ROLL.1"; seed_over_cap
mkdir -p "$ROLL.rotate.lock"
L17=$(rmA start --skill en-build); rmA finish "$L17" >/dev/null 2>&1; rc=$?
# Captured at the call. Read after an assertion, `$?` is that assertion's
# status, so the check was green for any status finish returned.
assert_exit_code 0 $rc "finish under a held lock still exits 0"
assert_file_missing "$ROLL.1" "a held lock publishes nothing, so nothing rotates"
assert_eq "0" "$(grep -c '"kind":"finish"' "$L17" || true)" "and holds the run open"
rmdir "$ROLL.rotate.lock"
rmA finish "$L17"
assert_eq "1" "$(grep -c "$(head -1 "$L17" | jq -r '.run_id')" "$ROLL" || true)" \
  "and the retry publishes it exactly once, once the lock is free"

# Ten concurrent finishes across the threshold: every run recorded exactly once,
# and the seeded history still present in one generation or the other.
rm -f "$ROLL.1"; seed_over_cap
ids=""
for i in $(seq 1 10); do
  l=$(rmA start --skill en-build --run-id "conc$i")
  ids="$ids $l"
done
for l in $ids; do rmA finish "$l" & done
wait
missing=0; dupes=0
for i in $(seq 1 10); do
  n=$(cat "$ROLL" "$ROLL.1" 2>/dev/null | grep -cF "\"run_id\":\"conc$i\"" || true)
  [ "$n" -eq 1 ] || { [ "$n" -eq 0 ] && missing=$((missing+1)) || dupes=$((dupes+1)); }
done
assert_eq "0" "$missing" "ten concurrent finishes: every run recorded"
assert_eq "0" "$dupes"   "ten concurrent finishes: none recorded twice"
assert_eq "1" "$(cat "$ROLL" "$ROLL.1" 2>/dev/null | grep -c '"seed"' || true)" \
  "the seeded generation survives the concurrent rotation"

# --- 20. failure and retry ---------------------------------------------------
# An unwritable store leaves the run OPEN, which is what makes the retry work.
rm -f "$ROLL" "$ROLL.1"
L18=$(rmA start --skill en-build)
chmod 500 "$ADIR"
rmA finish "$L18" >/dev/null 2>&1
rc=$?
chmod 700 "$ADIR"
assert_eq "0" "$rc" "an unwritable analytics store is not fatal"
assert_eq "0" "$(grep -c '"kind":"finish"' "$L18" || true)" "the ledger is left open"
assert_contains "$(cat "$ACTIVE")" "$L18" "and the run stays on the active stack"
rmA finish "$L18"
assert_eq "1" "$(wc -l < "$ROLL" | tr -d ' ')" "the retry publishes exactly one line"
assert_eq "1" "$(grep -c '"kind":"finish"' "$L18" || true)" "and closes the ledger"

# Idempotence, in the current file and in the rotated one.
L19=$(rmA start --skill en-build --run-id dedupe1)
printf '{"schema":1,"run_id":"dedupe1","skill":"en-build"}\n' >> "$ROLL"
n=$(wc -l < "$ROLL" | tr -d ' ')
rmA finish "$L19"
assert_eq "$n" "$(wc -l < "$ROLL" | tr -d ' ')" "a run already in the rollup is not appended twice"
assert_eq "1" "$(grep -c '"kind":"finish"' "$L19" || true)" "and its ledger still closes"

L20=$(rmA start --skill en-build --run-id dedupe2)
printf '{"schema":1,"run_id":"dedupe2","skill":"en-build"}\n' > "$ROLL.1"
n=$(wc -l < "$ROLL" | tr -d ' ')
rmA finish "$L20"
assert_eq "$n" "$(wc -l < "$ROLL" | tr -d ' ')" \
  "a run already in the ROTATED generation is not re-appended"

# A ledger that will never parse is unrecoverable, so it closes rather than
# retrying forever. That is the opposite call from the unwritable store above,
# and it is deliberate.
L21=$(rmA start --skill en-build)
printf 'not json at all\n' > "$L21"
n=$(wc -l < "$ROLL" | tr -d ' ')
rmA finish "$L21" >/dev/null 2>&1
assert_eq "0" "$?" "a malformed ledger is not fatal"
assert_eq "$n" "$(wc -l < "$ROLL" | tr -d ' ')" "and produces no rollup line"
assert_eq "1" "$(grep -c '"kind":"finish"' "$L21" || true)" \
  "but is closed rather than retried forever"


# --- 21. finish needs no variable (the defect that made the feature inert) ---
# `emit` was built pathless because a shell variable does not survive from the
# call that ran `start` to the call that runs a helper. `finish "$METRICS"`
# needed exactly such a variable: it resolved empty, hit the silent no-op, and
# the run was never published, never closed, and parented every later run.
rm -f "$ROLL" "$ROLL.1"
L22=$(rmA start --skill en-build)
rmA emit --kind lint --json '{"scope":"pathless"}'
# "${METRICS:-}" rather than "$METRICS" only because this file runs under
# set -u; in a real fresh shell the variable is simply empty, which is the
# whole point. Either way the helper receives an empty first argument.
( cd "$PROJ" && env -u ENSEMBLE_RUN_LEDGER -u METRICS ENSEMBLE_ANALYTICS_DIR="$ADIR" \
    bash "$RM" finish "${METRICS:-}" )
rc=$?
assert_exit_code 0 $rc "finish with an unset variable exits 0"
assert_eq "1" "$(wc -l < "$ROLL" | tr -d ' ')" "and still publishes the run"
assert_eq "1" "$(grep -c '\"kind\":\"finish\"' "$L22" || true)" "and closes the ledger"
rm_ emit --kind lint --json '{"scope":"after-pathless-finish"}'
assert_eq "0" "$(grep -c 'after-pathless-finish' "$L22" || true)" \
  "and nothing resolves to it afterwards"

# The bare form, with no argument at all.
rm -f "$ROLL"
L23=$(rmA start --skill en-plan)
rmA finish
assert_eq "1" "$(wc -l < "$ROLL" | tr -d ' ')" "finish with no argument publishes the run"
assert_eq "en-plan" "$(jq -r '.skill' "$ROLL")" "and publishes the right one"

# summary too, and `event` still demands its explicit path.
L24=$(rmA start --skill en-build)
rmA emit --kind dispatch --json '{"agent":"repo-research"}'
assert_contains "$(rmA summary)" "1 dispatches" "summary with no argument reads the open run"
rmA event --kind lint --json '{"scope":"x"}' 2>/dev/null
assert_eq "0" "$(grep -c '\"scope\":\"x\"' "$L24" || true)" \
  "event without a path writes nothing: it is the explicit-path form"
rmA finish "$L24"

# --- 22. a run nobody closed stops being live -------------------------------
# Liveness was only "no finish event", so a killed run stayed live forever: it
# parented every later run and every emit paid one grep for it. Measured at 365
# such entries, an emit went from 60ms to 1264ms.
rm -f "$ROLL"
L25=$(rmA start --skill en-build)
touch -t 202001010000 "$L25"                   # yesterday's run, never finished
L26=$(rmA start --skill en-review)
assert_eq "null" "$(head -1 "$L26" | jq -r '.parent_run_id')" \
  "an abandoned run does not parent the next one"
rmA emit --kind lint --json '{"scope":"after-abandon"}'
assert_eq "1" "$(grep -c 'after-abandon' "$L26" || true)" "emit targets the live run"
assert_eq "0" "$(grep -c 'after-abandon' "$L25" || true)" "not the abandoned one"
rmA finish "$L26"

# A live run one second old is NOT abandoned; the bound must not eat real runs.
L27=$(rmA start --skill en-build)
L28=$(rmA start --skill en-review)
assert_ne "null" "$(head -1 "$L28" | jq -r '.parent_run_id')" \
  "a fresh parent still parents"
rmA finish "$L28"; rmA finish "$L27"

# --- 23. the newest live run wins, whatever the stack depth ------------------
rm -f "$ROLL"
A1=$(rmA start --skill en-build)
A2=$(rmA start --skill en-review)
A3=$(rmA start --skill en-ship)
rmA emit --kind lint --json '{"scope":"innermost"}'
assert_eq "1" "$(grep -c 'innermost' "$A3" || true)" "three deep, the innermost run receives the event"
rmA finish "$A3"
rmA emit --kind lint --json '{"scope":"next-out"}'
assert_eq "1" "$(grep -c 'next-out' "$A2" || true)" "and the next one out after it closes"
rmA finish "$A2"; rmA finish "$A1"

# --- 24. a run cannot be published without being marked first ----------------
# Publishing is a read of the whole ledger followed by a write. An event landing
# between those two was in the ledger, absent from the rollup, and then
# unrecoverable. The `closing` marker means no later emit resolves to it at all.
rm -f "$ROLL"
L29=$(rmA start --skill en-build)
rmA emit --kind lint --json '{"scope":"before-close"}'
rmA finish "$L29"
assert_eq "1" "$(grep -c '\"kind\":\"closing\"' "$L29" || true)" "finish marks the ledger before publishing"
assert_eq "1" "$(jq -r '.counts.lint' "$ROLL")" "and the rollup carries the event that raced in before the mark"
assert_eq "null" "$(jq -r '.counts.closing' "$ROLL")" "the marker is bookkeeping, not an event"
assert_eq "null" "$(jq -r '.counts.finish' "$ROLL")" "and neither is the finish line"

# --- 25. a failed publish is retryable, and records nothing meanwhile --------
rm -f "$ROLL" "$ROLL.1"
L30=$(rmA start --skill en-build)
rmA emit --kind lint --json '{"scope":"pre-fail"}'
chmod 500 "$ADIR"
rmA finish "$L30" >/dev/null 2>&1
rc=$?
assert_exit_code 0 $rc "a finish that cannot publish still exits 0"
assert_eq "1" "$(grep -c '\"kind\":\"closing\"' "$L30" || true)" "the ledger is marked"
assert_eq "0" "$(grep -c '\"kind\":\"finish\"' "$L30" || true)" "but not closed, so the run can retry"
# And while it is marked, nothing new attaches to it.
h=$(hash_file "$L30")
rmA emit --kind lint --json '{"scope":"during-close"}'
assert_eq "$h" "$(hash_file "$L30")" "a marked ledger accepts no further events"
chmod 700 "$ADIR"
rmA finish "$L30"
assert_eq "1" "$(wc -l < "$ROLL" | tr -d ' ')" "the retry publishes exactly once"
assert_eq "1" "$(grep -c '\"kind\":\"closing\"' "$L30" || true)" "and does not re-mark"
assert_eq "1" "$(jq -r '.counts.lint' "$ROLL")" "with the events it had when it was marked"

# --- 26. --run-id is validated like --skill ---------------------------------
out=$(rmA start --skill en-build --run-id "$(printf 'a\tb')" 2>/dev/null)
assert_eq "" "$out" "a run-id containing a tab is refused"
out=$(rmA start --skill en-build --run-id 'a b' 2>/dev/null)
assert_eq "" "$out" "so is one containing a space"
out=$(rmA start --skill en-build --run-id 'ok-1.2_3' 2>/dev/null)
assert_ne "" "$out" "a well-formed run-id is accepted"
rmA finish "$out"

# --- 27. a backwards clock records unknown, not a negative ------------------
rm -f "$ROLL"
L31=$(rmA start --skill en-build)
python3 - "$L31" <<'PYEOF'
import json, sys
lines = open(sys.argv[1]).read().splitlines()
d = json.loads(lines[0]); d["at"] = "2099-01-01T00:00:00Z"
lines[0] = json.dumps(d, separators=(",", ":"))
open(sys.argv[1], "w").write("\n".join(lines) + "\n")
PYEOF
rmA finish "$L31"
assert_eq "null" "$(jq -r '.duration_s' "$ROLL")" \
  "a finish earlier than its start records duration_s null, never a negative"

# --- 28. the durable store gates values, not just keys ----------------------
# `outcome` is the one kind a model composes and the only free text on the path
# to the operator's permanent store. A verdict reading "leaked /Users/alice/..."
# landed there byte-for-byte with dropped:0.
rm -f "$ROLL"
L32=$(rmA start --skill en-review)
rmA emit --kind outcome --json '{"verdict":"revise: saw /Users/alice/.aws/credentials on fix/CVE-1","findings_total":9,"peer_only":3}'
e=$(grep '"kind":"outcome"' "$L32" | tail -1)
assert_eq "unknown" "$(printf '%s' "$e" | jq -r '.verdict')" \
  "a verdict outside the enum is recorded as unknown, not verbatim"
assert_not_contains "$e" "/Users/alice" "so no path reaches the ledger through it"
assert_eq "3" "$(printf '%s' "$e" | jq -r '.peer_only')" "and the counts beside it survive"

rmA emit --kind outcome --json '{"verdict":"approve","findings_total":0}'
assert_eq "approve" "$(grep '\"kind\":\"outcome\"' "$L32" | tail -1 | jq -r '.verdict')" \
  "a verdict inside the enum is kept"
rmA emit --kind outcome --json '{"verdict":"revise","findings_total":"lots"}'
assert_eq "null" "$(grep '\"kind\":\"outcome\"' "$L32" | tail -1 | jq -r '.findings_total')" \
  "a count that is not a number is recorded as null"
rmA finish "$L32"
assert_not_contains "$(cat "$ROLL")" "/Users/alice" "and nothing of it reaches the durable store"

# --- 29. a plan PATH does not become durable data ---------------------------
# Every caller is handed a path (`/en-build docs/plans/active/EN17-....md`), so
# passing it where a plan id belongs is the likely mistake, not an exotic one.
rm -f "$ROLL"
L33=$(rmA start --skill en-review --plan '/Users/someone/CodeRepo/acme-client/docs/plans/secret.md')
rmA finish "$L33"
assert_eq "null" "$(jq -r '.plan_id' "$ROLL")" "a plan path is recorded as null"
assert_not_contains "$(cat "$ROLL")" "acme-client" "so no client name reaches the store"
rm -f "$ROLL"
L34=$(rmA start --skill en-review --plan EN17)
rmA finish "$L34"
assert_eq "EN17" "$(jq -r '.plan_id' "$ROLL")" "a plan id is kept"

# --- 30. concurrent starts do not lose registrations ------------------------
# Unlocked, `start`'s append landed between another process's read and its
# rename and was destroyed; a run whose entry was lost then wrote its events
# into a different run's ledger. Measured at 5 of 12 before the lock.
CW="$WORK/conc"; mkdir -p "$CW"
( cd "$CW" && git init -q . && git config user.email t@e && git config user.name t )
cled() { ( cd "$CW" && env -u ENSEMBLE_RUN_LEDGER ENSEMBLE_ANALYTICS_DIR="$ADIR" bash "$RM" "$@" ); }
for i in 1 2 3; do cled start --skill en-build --run-id "pad$i" >/dev/null; done
for i in 1 2 3 4 5 6 7 8; do cled start --skill en-review --run-id "c$i" >/dev/null & done
wait
CACTIVE="$CW/.git/ensemble/runs/active"
lost=0
for i in 1 2 3 4 5 6 7 8; do grep -q "	c$i	" "$CACTIVE" || lost=$((lost + 1)); done
assert_eq "0" "$lost" "eight concurrent starts all register"
assert_eq "0" "$(grep -cv '^[+-]	' "$CACTIVE" || true)" "and none of them corrupts a line"

# The race is gone rather than guarded: `active` is append-only, so there is no
# rewrite for a concurrent append to land inside. The structural property is
# that nothing rewrites it.
rewriters=$(grep -cE 'mv -f "\$(tmp|af)"|> *"\$af"' "$RM" || true)
assert_eq "0" "$rewriters" "nothing rewrites the run log; it is append-only"
assert_eq "0" "$(grep -c '_active_prune\|_active_pop\|_active_top' "$RM" || true)" \
  "and the mutable-stack machinery is gone with it"

# --- 31. the rollup retry is bounded ----------------------------------------
# Unbounded, one unwritable store left EVERY run in the repo open: active grew
# forever and every later rollup line named a parent that was not its parent.
rm -f "$ROLL" "$ROLL.1"
L35=$(rmA start --skill en-build)
chmod 500 "$ADIR"
rmA finish "$L35" >/dev/null 2>&1
assert_eq "0" "$(grep -c '\"kind\":\"finish\"' "$L35" || true)" "the first failure holds the run open"
rmA finish "$L35" >/dev/null 2>&1
assert_eq "1" "$(grep -c '\"kind\":\"finish\"' "$L35" || true)" \
  "the second closes it rather than holding it open forever"
chmod 700 "$ADIR"
rm_ emit --kind lint --json '{"scope":"after-bounded-retry"}'
assert_eq "0" "$(grep -c 'after-bounded-retry' "$L35" || true)" \
  "and nothing resolves to it once it is closed"

# --- 32. a lock nobody released does not disable rotation forever -----------
# No trap and no staleness check meant a process killed between the mkdir and
# the rmdir turned the 5 MB cap off silently and permanently.
rm -f "$ROLL" "$ROLL.1"
seed_over_cap
mkdir -p "$ROLL.rotate.lock"
touch -t 202001010000 "$ROLL.rotate.lock"
L36=$(rmA start --skill en-build); rmA finish "$L36"
assert_file_exists "$ROLL.1" "a stale rotate lock is cleared and rotation resumes"
rmdir "$ROLL.rotate.lock" 2>/dev/null || true

# --- 33. the store is created private ---------------------------------------
PW="$WORK/perm"; mkdir -p "$PW"
( cd "$PW" && git init -q . && git config user.email t@e && git config user.name t )
PA="$PW/analytics"
( cd "$PW" && env -u ENSEMBLE_RUN_LEDGER ENSEMBLE_ANALYTICS_DIR="$PA" bash "$RM" start --skill en-build >/dev/null )
( cd "$PW" && env -u ENSEMBLE_RUN_LEDGER ENSEMBLE_ANALYTICS_DIR="$PA" bash "$RM" finish )
assert_eq "700" "$(ls -ld "$PA" | awk '{print $1}' | sed 's/[^rwx-]//g' | awk '{
  p=$0; o=0; g=0; w=0;
  if (substr(p,1,1)=="r") o+=4; if (substr(p,2,1)=="w") o+=2; if (substr(p,3,1)=="x") o+=1;
  if (substr(p,4,1)=="r") g+=4; if (substr(p,5,1)=="w") g+=2; if (substr(p,6,1)=="x") g+=1;
  if (substr(p,7,1)=="r") w+=4; if (substr(p,8,1)=="w") w+=2; if (substr(p,9,1)=="x") w+=1;
  printf "%d%d%d", o, g, w }')" "the analytics directory is created 700"

# --- 34. a rejected argument leaves nothing broken behind -------------------
# `start` used to reject a bad --run-id from inside a critical section without
# releasing the lock, after which every later pop skipped silently. There is no
# lock now, and this asserts the property that mattered: the next run still
# resolves.
rmA start --skill en-build --run-id 'bad id' >/dev/null 2>&1
rmA start --skill en-build --run-id "$(printf 'a\tb')" >/dev/null 2>&1
assert_file_missing "$ACTIVE.lock" "no run-log lock exists to leak"
L37=$(rmA start --skill en-build)
rmA emit --kind lint --json '{"scope":"after-bad-ids"}'
assert_eq "1" "$(grep -c 'after-bad-ids' "$L37" || true)" \
  "and a rejected run-id leaves the next run resolvable"
rmA finish "$L37"

# --- 35. a pathless retry finds the run whose publish failed ----------------
# _active_top returns only LIVE entries, and a marked-but-unpublished run is by
# definition not live, so the pathless form walked past it and closed the outer
# parent instead: a run that failed its first publish could never be closed.
rm -f "$ROLL" "$ROLL.1"
L38=$(rmA start --skill en-build)
chmod 500 "$ADIR"
rmA finish >/dev/null 2>&1
chmod 700 "$ADIR"
assert_eq "1" "$(grep -c '\"kind\":\"closing\"' "$L38" || true)" "the pathless finish marked it"
assert_eq "0" "$(grep -c '\"kind\":\"finish\"' "$L38" || true)" "and held it open"
rmA finish >/dev/null 2>&1
assert_eq "1" "$(grep -c '\"kind\":\"finish\"' "$L38" || true)" \
  "and a pathless retry finds the marked run and closes it"
assert_eq "1" "$(wc -l < "$ROLL" | tr -d ' ')" "publishing it exactly once"

# A retry must not close somebody else's run when the marked one is nested.
rm -f "$ROLL"
LP2=$(rmA start --skill en-build)
LC2=$(rmA start --skill en-review)
chmod 500 "$ADIR"; rmA finish >/dev/null 2>&1; chmod 700 "$ADIR"
rmA finish >/dev/null 2>&1
assert_eq "1" "$(grep -c '\"kind\":\"finish\"' "$LC2" || true)" "the retry closes the marked child"
assert_eq "0" "$(grep -c '\"kind\":\"finish\"' "$LP2" || true)" "and leaves the live parent open"
rmA finish "$LP2"

# --- 36. a published ledger takes nothing further ---------------------------
# The marker stops a pathless emit resolving, but an explicit path and an
# env-var path both bypassed it, and the rollup has already read the file.
rm -f "$ROLL"
L39=$(rmA start --skill en-build)
rmA finish "$L39"
h=$(hash_file "$L39")
rmA event "$L39" --kind lint --json '{"scope":"after-close"}'
assert_eq "$h" "$(hash_file "$L39")" "an explicit-path event on a closed ledger writes nothing"
( cd "$PROJ" && ENSEMBLE_RUN_LEDGER="$L39" ENSEMBLE_ANALYTICS_DIR="$ADIR" bash "$RM" \
    emit --kind lint --json '{"scope":"env-after-close"}' )
assert_eq "$h" "$(hash_file "$L39")" "and neither does one addressed by ENSEMBLE_RUN_LEDGER"

report
