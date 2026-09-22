#!/usr/bin/env bash
# tests/lint/en-build-linear-state.test.sh
#
# EN18 U5. In `plan_store: linear`, Linear reflects build progress at unit
# granularity and an abandoned build leaves the plan visibly re-runnable.
#
# Three of these clauses guard a mistake that was already made once in this
# plan's own drafting, or measured against the real workspace:
#
#   - The third state is named "In Review", not "Review". An earlier draft of
#     this unit said "Review" and would have failed its own preflight on a
#     correctly configured team.
#   - States are matched by NAME. "In Progress" and "In Review" share type
#     `started` (U1 listed them), so a type-based lookup picks arbitrarily
#     between the two and passes on whichever team happens to list them in the
#     convenient order.
#   - The whole contract is scoped to linear mode. The prose says the states
#     are resolved "before the first mutation, local or remote", which reads as
#     unconditional; a workspace-wide state preflight on every local build is
#     both a latency cost and a hard failure for repos with no Linear
#     workspace at all.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build linear state"

BUILD="$REPO_ROOT/skills/en-build/SKILL.md"
PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
PRE="$REPO_ROOT/skills/en-build/references/build-preflight.md"
PUB="$REPO_ROOT/skills/en-plan/references/linear-publish.md"

has()   { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }
hasnt() { grep -qiE -- "$2" "$1" && fail "$3" "present in $(basename "$1"): $2" || pass "$3"; }

# --- 0. both skills route to the contract -----------------------------------
has "$BUILD" 'build-preflight\.md' "en-build routes to its preflight reference"
has "$PLAN" 'linear-publish\.md' "en-plan routes to its publish reference"

# --- 1. the four state names, spelled as the workspace spells them ----------
for state in 'Agent Ready' 'In Progress' 'In Review' 'Done'; do
  has "$PRE" "$state" "en-build names the state: $state"
done
for state in 'Agent Ready' 'In Progress' 'In Review' 'Done'; do
  has "$PUB" "$state" "en-plan names the state: $state"
done

# A bare "Review" as the state name is the drafting error this guards. Matched
# with word boundaries so "In Review" and "peer review" do not trigger it.
for f in "$PRE" "$PUB"; do
  n=$(basename "$(dirname "$f")")
  if grep -qE '(state|status)[^.]*\bto Review\b|\bReview state\b' "$f"; then
    fail "$n: the third state must be spelled 'In Review'" \
         "a bare 'Review' fails its own preflight on a correctly configured team"
  else
    pass "$n: the third state is not spelled as a bare 'Review'"
  fi
done

# --- 2. matched by name, never by type --------------------------------------
has "$PRE" 'by name' "en-build matches states by name"
has "$PRE" 'share (a |the )?type|both type `?started|same type' \
  "and records why: two states share type started"

# --- 3. the four transitions ------------------------------------------------
has "$PRE" 'parent.*In Progress|In Progress.*parent' "the parent moves to In Progress at build start"
has "$PRE" 'sub-issue.*In Progress|when the unit starts' "each sub-issue moves to In Progress when its unit starts"
has "$PRE" 'Done when it commits|commits.*Done' "each sub-issue moves to Done when its unit commits"
has "$PRE" 'In Review after the last|after the last unit' "the parent moves to In Review after the last unit commits"

# --- 4. where /en-build stops ------------------------------------------------
has "$PRE" 'GitHub integration' "the PR is the hand-off point; Linear's integration owns it after"
has "$PRE" 'never (edited|written)|not written back|never written back' \
  "progress is never written back into the plan body"

# --- 5. scoped to linear mode, asserted in both skills ----------------------
# Without this, the "before the first mutation, local or remote" phrasing reads
# as unconditional and a local build pays for a Linear lookup it cannot make.
has "$PRE" 'only.*linear|linear mode only|scoped to `?linear' \
  "en-build scopes the state contract to linear mode"
has "$PUB" 'only.*linear|linear mode only|scoped to `?linear|`local`' \
  "en-plan scopes the state preflight to linear mode"
for f in "$PRE" "$PUB"; do
  n=$(basename "$(dirname "$f")")
  has "$f" 'no (state )?lookup|makes no MCP call|no MCP call' \
    "$n: local mode makes no state lookup"
done

# --- 6. abort, and the gap it cannot cover ----------------------------------
has "$PRE" 'graceful' "a graceful abort returns the parent to Agent Ready"
has "$PRE" 'killed|cannot run that transition' \
  "and the prose narrows the guarantee, because a killed process cannot run it"
has "$PRE" 'reconcile' "the gap is closed at build start by reconciling"
has "$PRE" 'operator decision|surface the discrepancy|ask' \
  "reconciliation surfaces for a decision rather than silently resuming or restarting"
has "$PRE" 'already Done|already at Done' "a resumed build does not reset sub-issues already at Done"

# --- 7. a missing state is a blocking error, raised early -------------------
has "$PRE" 'blocking error|refuse' "a missing or ambiguous state is a blocking error"
has "$PRE" 'before any commit|before the branch is created|before any local commit' \
  "raised before any commit exists, not halfway through a build"
has "$PUB" 'before publishing|before any Linear mutation' \
  "and in en-plan, before publishing"

report
