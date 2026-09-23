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

has() { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }

# Matches a pattern across line breaks, so a clause can assert that two facts
# appear TOGETHER. Checking the whole file for each fact separately stays green
# when the sentence joining them is deleted and both words survive elsewhere,
# which is how several guards in this file were decorative.
#
# Three portability traps, all hit while writing this:
#   - POSIX ERE has no lazy `?` quantifier modifier.
#   - BSD grep rejects an interval above 255 ("maximum repetition exceeds 255")
#     and reports a miss rather than an error exit.
#   - BSD `grep -z` does NOT match across newlines, despite the flag; the file
#     has to be flattened first. Hence tr, not -z.
has_near() {
  tr '\n' ' ' < "$1" | grep -qiE -- "$2" \
    && pass "$3" || fail "$3" "not found together in $(basename "$1"): $2"
}

# Labels a path by its SKILL, not its parent directory. Both references live in
# a directory called `references/`, so basename(dirname(f)) labelled the two
# iterations below identically and a failure could not be attributed to a skill.
skill_of() { printf '%s' "$1" | sed -n 's|.*/skills/\([^/]*\)/.*|\1|p'; }

# --- 0. both skills route to the contract -----------------------------------
has "$BUILD" 'build-preflight\.md' "en-build routes to its preflight reference"
has "$PLAN" 'linear-publish\.md' "en-plan routes to its publish reference"

# --- 1. the four state names, spelled as the workspace spells them ----------
for f in "$PRE" "$PUB"; do
  n=$(skill_of "$f")
  for state in 'Agent Ready' 'In Progress' 'In Review' 'Done'; do
    has "$f" "$state" "$n names the state: $state"
  done
done

# A bare "Review" as the state name is the drafting error this guards. Matched
# with word boundaries so "In Review" and "peer review" do not trigger it.
for f in "$PRE" "$PUB"; do
  n=$(skill_of "$f")
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

# --- 4. where /en-build stops ------------------------------------------------
has "$PRE" 'GitHub integration' "the PR is the hand-off point; Linear's integration owns it after"
has "$PRE" 'never (edited|written)|not written back|never written back' \
  "progress is never written back into the plan body"

# --- 5. scoped to linear mode, asserted in both skills ----------------------
# Without this, the "before the first mutation, local or remote" phrasing reads
# as unconditional and a local build pays for a Linear lookup it cannot make.
# Anchored on the scoping sentence itself. `only.*linear` also matched
# build-preflight.md's provenance line ("written only on the Linear path"), and
# the bare `` `local` `` alternative matched linear-publish.md's header
# blockquote, so both stayed green with the actual scoping clause deleted.
has "$PRE" 'Only in `linear` mode' "en-build scopes the state contract to linear mode"
has "$PUB" 'Only in `linear` mode' "en-plan scopes the state preflight to linear mode"
for f in "$PRE" "$PUB"; do
  n=$(skill_of "$f")
  # `makes no MCP call` was a third alternative here; it is a strict superstring
  # of `no MCP call`, so it could never be the branch that made a match succeed.
  has "$f" 'no (state )?lookup|no MCP call' \
    "$n: local mode makes no state lookup"
done

# --- 6. abort, and the gap it cannot cover ----------------------------------
# `graceful` alone passed while the sentence tying it to Agent Ready was gone,
# because Agent Ready is independently asserted above as one of the four names.
has_near "$PRE" 'graceful[^#]{0,120}Agent Ready' \
  "a graceful abort returns the parent to Agent Ready"
has "$PRE" 'killed|cannot run that transition' \
  "and the prose narrows the guarantee, because a killed process cannot run it"
has "$PRE" 'reconcile' "the gap is closed at build start by reconciling"
# The bare `ask` alternative matched the sub-state matrix's unrelated "ask the
# user to apply/defer/disagree" row, so the reconciliation behaviour was
# effectively unasserted.
has_near "$PRE" 'reconcile[^#]{0,240}(operator decision|surface the discrepancy)' \
  "reconciliation surfaces for a decision rather than silently resuming or restarting"
# Negation-blind before: "a resumed build RESETS sub-issues already at Done"
# matched the same pattern as the rule's inverse.
has "$PRE" 'does not reset sub-issues already|not reset.{0,20}already at Done' \
  "a resumed build does not reset sub-issues already at Done"

# --- 6b. the transitions are re-cited where they FIRE (review finding) ------
# SKILL.md cited build-preflight.md once, at step 4, while the transitions fire
# at 9c, 9e and after the post-build gates. A contract read at the start of a
# multi-unit session and never re-pointed at the moments it applies is a
# contract that gets skipped. Asserting the filename appears "somewhere" in
# SKILL.md was satisfied by the step-4 mention alone.
unit_loop=$(awk '/^9\. \*\*Unit loop/{f=1} f&&/^10\. /{exit} f' "$BUILD")
printf '%s' "$unit_loop" | grep -qF 'build-preflight.md' \
  && pass "the unit loop re-cites the state table where the transitions fire" \
  || fail "the unit loop must re-cite references/build-preflight.md" \
         "step 4's single citation is read hours before 9c and 9e need it"
# Anchored on the transition phrasing, not the bare state name: "Done" occurs
# in the loop already ("check first whether the unit is already done", "called
# done"), so grep -F 'Done' stayed green with the 9e citation deleted.
printf '%s' "$unit_loop" | grep -qE "sub-issue to \*\*In Progress\*\*" \
  && pass "9c names the In Progress transition inline" \
  || fail "9c must name the In Progress transition"
printf '%s' "$unit_loop" | grep -qE "sub-issue to \*\*Done\*\*" \
  && pass "9e names the Done transition inline" \
  || fail "9e must name the Done transition"

# --- 6c. In Review lands AFTER the post-build gates (peer finding) ----------
# Set at the last unit commit, it precedes simplify, the branch review, the
# evidence audit and any fix loop, and en-build is then forbidden to touch the
# parent, so a graceful failure in those gates cannot return it to Agent Ready.
# Anchored on the TABLE ROW, not the prose. The explanatory paragraph below
# the table also contains "after the post-build gates", so a file-wide check
# stayed green when the row itself was reverted to the last unit commit, which
# is the only place the transition is actually specified.
has "$PRE" '^\| after the post-build gates pass \| the parent moves to \*\*In Review\*\* \|' \
  "the In Review row fires only after the post-build gates pass"
has_near "$PRE" 'evidence audit[^#]{0,200}|In Review comes after' \
  "and the prose says why the last-unit-commit placement was wrong"

# --- 6b. the parent transitions are wired where they fire -------------------
# build-preflight.md is read at pre-flight, long before the post-build phase
# and any abort. Without a pointer at each moment, the transitions live only
# in a file read an hour earlier.
has "$BUILD" '4b\. Status flip.*linear.*parent to In Progress' \
  "en-build's status flip moves the Linear parent to In Progress"
has "$BUILD" '4b\. Status flip.*reconcil' "and reconciles a parent already In Progress"
has "$BUILD" 'Linear mode:\*\* move the parent to In Review[^\n]*after the audit' \
  "the post-build phase moves the parent to In Review after the audit"
has "$BUILD" 'abort before this returns it to Agent Ready' "a graceful abort returns the parent to Agent Ready"

# --- 7. a missing state is a blocking error, raised early -------------------
has "$PRE" 'blocking error|refuse' "a missing or ambiguous state is a blocking error"
has "$PRE" 'before any commit|before the branch is created|before any local commit' \
  "raised before any commit exists, not halfway through a build"
has "$PUB" 'before publishing|before any Linear mutation' \
  "and in en-plan, before publishing"

report
