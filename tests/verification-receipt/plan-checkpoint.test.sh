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

report
