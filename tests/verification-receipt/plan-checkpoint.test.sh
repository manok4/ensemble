#!/usr/bin/env bash
# Tests for skills/en-ship/scripts/ensemble-plan-checkpoint (EN15 U6).
#
# One fixture per outcome. The four exist because a single `incomplete_build`
# conflated three situations needing three different responses: one needs code
# written, one needs a trailer, one needs nothing at all. A test suite that only
# proved "not complete" would leave that conflation exactly where it was.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="plan checkpoint"

C="$REPO_ROOT/skills/en-ship/scripts/ensemble-plan-checkpoint"
assert_file_exists "$C" "the checkpoint helper exists"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# A fixture repo carrying a plan and a branch named for it.
# $1=name $2=plan status $3=unit spec ("U1:in U2:deferred") $4=covered U-IDs $5=implemented U-IDs
fixture() {
  d="$WORK/$1"; mkdir -p "$d/docs/plans/active"
  ( cd "$d" && git init -q . && git config user.email t@e.com && git config user.name t ) >/dev/null 2>&1
  {
    printf -- '---\ntype: plan\nplan_id: EN99\nstatus: %s\n---\n\n# EN99 — fixture\n\n' "$2"
    for spec in $3; do
      uid=${spec%%:*}; scope=${spec##*:}
      printf '### %s. goal\n\n- **Ship scope:** %s\n\n' "$uid" "$scope"
    done
  } > "$d/docs/plans/active/EN99-feature_fixture.md"
  ( cd "$d" && git add . && git commit -qm "docs(plan): EN99" && git checkout -q -b EN99-fixture ) >/dev/null 2>&1
  # Implementing commits, then one review-verdict trailer naming the covered units.
  for u in $5; do
    ( cd "$d" && git commit -q --allow-empty -m "feat(x): work ($u)" ) >/dev/null 2>&1
  done
  if [ -n "$4" ]; then
    units=$(printf '%s' "$4" | tr ' ' ',' | sed 's/\([A-Z0-9]*\)/"\1"/g')
    # A complete trailer: verdict, reviewer, mode, units_covered and findings_count
    # are all required. An incomplete one is rejected as invalid rather than parsed
    # leniently — which this fixture proved by getting it wrong on the first pass.
    ( cd "$d" && git commit -q --allow-empty -m "chore: branch review

review-verdict: {\"verdict\":\"approve\",\"reviewer\":\"cross-agent\",\"mode\":\"headless\",\"units_covered\":[$units],\"findings_count\":0}" ) >/dev/null 2>&1
  fi
  printf '%s\n' "$d"
}

outcome() { ( cd "$1" && "$C" --base master --json 2>/dev/null || cd "$1" && "$C" --base main --json 2>/dev/null ) \
  | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["outcome"])
except Exception: print("UNPARSEABLE")'; }

base_branch() { ( cd "$1" && git rev-parse --verify --quiet main >/dev/null 2>&1 && echo main || echo master ); }
run() { d="$1"; ( cd "$d" && "$C" --base "$(base_branch "$d")" --json 2>/dev/null ); }
outcome_of() { run "$1" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["outcome"])
except Exception: print("UNPARSEABLE")'; }

# --- complete ----------------------------------------------------------------
A=$(fixture complete open "U1:in U2:in" "U1 U2" "U1 U2")
assert_eq "complete" "$(outcome_of "$A")" "every in-scope unit covered is complete"

# --- partial_expected --------------------------------------------------------
# The case the old single outcome got wrong: U2 deliberately held back.
B=$(fixture partial open "U1:in U2:production_pending" "U1" "U1")
assert_eq "partial_expected" "$(outcome_of "$B")" "a deliberately held unit is an expected partial, not a failure"
assert_eq "U2" "$(run "$B" | python3 -c 'import json,sys;print(",".join(json.load(sys.stdin)["deferred_units"]))')" \
  "the held unit is reported as deferred, not missing"

# --- complete_evidence_missing ----------------------------------------------
# Built, but no review-verdict names it. Needs a trailer, not more code.
D=$(fixture evidence open "U1:in U2:in" "" "U1 U2")
assert_eq "complete_evidence_missing" "$(outcome_of "$D")" "built but unreviewed units need a trailer, not code"

# --- incomplete_unexpected ---------------------------------------------------
E=$(fixture incomplete open "U1:in U2:in" "U1" "U1")
assert_eq "incomplete_unexpected" "$(outcome_of "$E")" "a unit with neither coverage nor a commit is genuinely unbuilt"

# --- plan states -------------------------------------------------------------
F=$(fixture done completed "U1:in" "" "")
assert_eq "up_to_date" "$(outcome_of "$F")" "an already-completed plan is up to date"
G=$(fixture drafted draft "U1:in" "" "")
assert_eq "not_applicable" "$(outcome_of "$G")" "a draft plan is not applicable"
H=$(fixture dropped abandoned "U1:in" "" "")
assert_eq "not_applicable" "$(outcome_of "$H")" "an abandoned plan is not applicable"

# --- a branch with no plan is the ordinary case ------------------------------
# It must exit 0. Most branches are not plan branches, and a non-zero exit here
# would force every caller to special-case the common path.
I="$WORK/noplan"; mkdir -p "$I"
( cd "$I" && git init -q . && git config user.email t@e.com && git config user.name t \
    && printf 'x\n' > a.txt && git add . && git commit -qm init && git checkout -q -b feature-no-plan ) >/dev/null 2>&1
( cd "$I" && "$C" --json >/dev/null 2>&1 ); assert_eq "0" "$?" "a branch with no plan exits 0"
assert_eq "not_applicable" "$( cd "$I" && "$C" --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["outcome"])')" \
  "a branch with no plan is not applicable"

# --- lowercase branch still finds its plan -----------------------------------
# /en-build may create en99-fixture while the plan file is EN99-*. On a
# case-sensitive filesystem an unnormalised lookup misses it and silently reports
# not_applicable, defeating the checkpoint.
J=$(fixture lower open "U1:in" "U1" "U1")
( cd "$J" && git checkout -q -b en99-lowercase ) >/dev/null 2>&1
assert_eq "complete" "$(outcome_of "$J")" "a lowercase branch name still resolves its plan"

# --- provenance (EN18): Linear builds and configuration drift ----------------
# A Linear build's branch is <IDENT>-<slug> and its plan is the materialized
# copy. Before these, every Linear build resolved not_applicable, so neither
# linear_mode nor the drift error was reachable.
# $1=name $2=branch $3=plan path $4=plan_source $5=configured_store $6=repo plan_store ("" = unset)
prov_fixture() {
  d="$WORK/$1"; mkdir -p "$d/$(dirname "$3")" "$d/.ensemble" "$WORK/home-$1"
  ( cd "$d" && git init -q . && git config user.email t@e.com && git config user.name t ) >/dev/null 2>&1
  printf -- '---\ntype: plan\nplan_id: EN99\nstatus: in_progress\nplan_source: %s\nconfigured_store: %s\n---\n\n### U1. goal\n\n- **Ship scope:** in\n' \
    "$4" "$5" > "$d/$3"
  [ -n "$6" ] && printf 'plan_store: %s\n' "$6" > "$d/.ensemble/config.local.yaml"
  ( cd "$d" && git commit -q --allow-empty -m init && git checkout -q -b "$2" ) >/dev/null 2>&1
  printf '%s\n' "$d"
}
prov_run() { ( cd "$1" && HOME="$WORK/home-$2" "$C" --json 2>/dev/null ); }
prov_outcome() { prov_run "$1" "$2" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["outcome"])
except Exception: print("UNPARSEABLE")'; }

L=$(prov_fixture lin ENG-412-thing .ensemble/materialized-plans/ENG-412.md linear linear linear)
assert_eq "linear_mode" "$(prov_outcome "$L" lin)" \
  "a Linear branch resolves its materialized plan and returns linear_mode"
assert_eq ".ensemble/materialized-plans/ENG-412.md" \
  "$(prov_run "$L" lin | python3 -c 'import json,sys;print(json.load(sys.stdin)["plan_path"])')" \
  "and names the materialized plan it read"

Ll=$(prov_fixture linlower eng-412-thing .ensemble/materialized-plans/ENG-412.md linear linear linear)
assert_eq "linear_mode" "$(prov_outcome "$Ll" linlower)" "a lowercased Linear branch resolves the same plan"

F=$(prov_fixture flipped ENG-413-thing .ensemble/materialized-plans/ENG-413.md linear linear local)
assert_eq "config_drift" "$(prov_outcome "$F" flipped)" \
  "a Linear build shipped after plan_store flipped to local is drift"
assert_eq "linear/local" \
  "$(prov_run "$F" flipped | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["configured_store"]+"/"+d["current_store"])')" \
  "the drift outcome names both values"

G=$(prov_fixture localdrift EN99-thing docs/plans/active/EN99-feature_fixture.md local local linear)
assert_eq "config_drift" "$(prov_outcome "$G" localdrift)" \
  "a local build shipped under plan_store: linear is drift too, the direction that skips the git mv"

M=$(prov_fixture migrating EN99-thing docs/plans/active/EN99-feature_fixture.md local linear linear)
assert_eq "incomplete_unexpected" "$(prov_outcome "$M" migrating)" \
  "a mid-migration local build (configured_store: linear) is not drift and runs the local outcomes"

# --- provenance from git history (EN19 U3) -----------------------------------
# Every unit commit carries a plan-provenance trailer, so ship reads provenance
# from history on any machine. Before this, provenance lived only in the
# gitignored materialized file: a fresh clone or `git clean` silently turned
# the drift check off and returned not_applicable.
# $1=name $2=branch $3=repo plan_store ("" = unset) $4.. = trailer JSON per unit commit
trailer_fixture() {
  local name="$1" br="$2" store="$3"; shift 3
  d="$WORK/$name"; mkdir -p "$d/.ensemble" "$WORK/home-$name"
  ( cd "$d" && git init -q . && git config user.email t@e.com && git config user.name t \
      && git commit -q --allow-empty -m init && git checkout -q -b "$br" ) >/dev/null 2>&1
  [ -n "$store" ] && printf 'plan_store: %s\n' "$store" > "$d/.ensemble/config.local.yaml"
  local n=1
  for t in "$@"; do
    ( cd "$d" && git commit -q --allow-empty -m "feat(x): unit $n (U$n)

plan-provenance: $t" ) >/dev/null 2>&1
    n=$((n + 1))
  done
  printf '%s\n' "$d"
}
tr_run() { ( cd "$1" && HOME="$WORK/home-$2" "$C" --base "$(base_branch "$1")" --json 2>/dev/null ); }
tr_outcome() { tr_run "$1" "$2" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["outcome"])
except Exception: print("UNPARSEABLE")'; }
LIN='{"plan_source":"linear","configured_store":"linear","plan_ref":"ENG-500"}'

T1=$(trailer_fixture trl ENG-500-thing linear "$LIN" "$LIN")
[ ! -e "$T1/.ensemble/materialized-plans" ] && pass "the fixture has no materialized plan on disk" \
  || fail "the fixture has no materialized plan on disk"
assert_eq "linear_mode" "$(tr_outcome "$T1" trl)" \
  "a Linear build with provenance trailers and no materialized file returns linear_mode"

T2=$(trailer_fixture trldrift ENG-501-thing local "$LIN")
assert_eq "config_drift" "$(tr_outcome "$T2" trldrift)" \
  "trailers recording configured_store: linear, repo now local: config_drift with no file on disk"
assert_eq "linear/local" \
  "$(tr_run "$T2" trldrift | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["configured_store"]+"/"+d["current_store"])')" \
  "the drift names both values, read from the trailer"

T3=$(trailer_fixture trlconflict ENG-502-thing linear "$LIN" \
  '{"plan_source":"local","configured_store":"linear","plan_ref":"docs/plans/active/EN99-x.md"}')
assert_eq "provenance_conflict" "$(tr_outcome "$T3" trlconflict)" \
  "two unit commits whose provenance trailers disagree return provenance_conflict"

# Key order is not provenance: the same values written in another order agree.
T4=$(trailer_fixture trlorder ENG-503-thing linear "$LIN" \
  '{"plan_ref":"ENG-500","configured_store":"linear","plan_source":"linear"}')
assert_eq "linear_mode" "$(tr_outcome "$T4" trlorder)" "trailers with the same values in another key order agree"

# The trailer wins over the materialized file: history is the record, the file
# is a local cache that can be stale.
T5=$(trailer_fixture trlwins ENG-504-thing linear "$LIN")
mkdir -p "$T5/.ensemble/materialized-plans"
printf -- '---\ntype: plan\nplan_id: EN99\nstatus: in_progress\nplan_source: local\nconfigured_store: local\n---\n\n### U1. g\n\n- **Ship scope:** in\n' \
  > "$T5/.ensemble/materialized-plans/ENG-504.md"
assert_eq "linear_mode" "$(tr_outcome "$T5" trlwins)" "the trailer takes precedence over the materialized file's frontmatter"

report
