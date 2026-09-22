#!/usr/bin/env bash
# tests/lint/plan-completion-linear.test.sh
#
# EN18 U6. /en-ship's plan-completion checkpoint `git mv`s the plan to
# docs/plans/completed/ and /en-learn flips its `status:` at ship. Both assume
# a file on disk. In Linear mode there is none, and the PR merge moves the
# parent to Done through the GitHub integration instead.
#
# The clause this file exists for is the SYMMETRY one. Both skills act on the
# build's recorded provenance rather than the repo's current `plan_store`,
# because `plan_store` is mutable between build and ship. Writing provenance
# only on the Linear path catches one drift direction and misses the other:
#
#   linear build, config later flipped to local  -> caught by a linear-only field
#   local  build, config later flipped to linear -> NOT caught; the git mv is
#                                                   skipped and the plan never
#                                                   reaches completed/
#
# So the provenance field is written on BOTH paths, and both drift directions
# are asserted separately. A test with only the first scenario passes against
# exactly the bug the peer found.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="plan completion in linear mode"

SHIP="$REPO_ROOT/skills/en-ship/SKILL.md"
COMP="$REPO_ROOT/skills/en-ship/references/plan-completion.md"
LEARN="$REPO_ROOT/skills/en-learn/SKILL.md"
PRE="$REPO_ROOT/skills/en-build/references/build-preflight.md"

has() { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }

# --- 1. the producer: /en-build writes provenance on BOTH paths -------------
has "$PRE" 'provenance' "en-build records the resolved mode as build provenance"
# Anchored on the both-paths claim itself. A looser alternation also matched
# the mode table's "record provenance as `local`" row and stayed green when
# the claim was flipped to "written on the Linear path", which is the only
# thing this clause guards.
has "$PRE" 'written on both paths' \
  "provenance is written on the local path too, not only the Linear one"
has "$PRE" 'immutable|not re-read|never re-resolved' \
  "and it is immutable: ship acts on what the build did, not on the config now"

# --- 2. the consumers read provenance, never the live config ----------------
for f in "$COMP" "$LEARN"; do
  n=$(basename "$(dirname "$f")")
  has "$f" 'provenance' "$n reads the build's provenance"
  has "$f" 'mutable|changed between|since flipped|config(uration)? drift' \
    "$n records why the live plan_store is not the input"
done

# --- 3. both drift directions, asserted separately --------------------------
# The linear->local direction is the obvious one. The local->linear direction
# is the one a linear-only provenance field misses, and it is the more
# expensive of the two: the git mv is skipped and the plan never reaches
# docs/plans/completed/.
for f in "$COMP" "$LEARN"; do
  n=$(basename "$(dirname "$f")")
  if grep -qiE 'both direction|either direction' "$f"; then
    pass "$n: drift is caught in both directions"
  else
    fail "$n: drift must be caught in both directions" \
         "a linear-only provenance field misses a local build shipped under plan_store: linear"
  fi
  has "$f" 'blocking error|stop|refuse' "$n: drift stops rather than guessing"
  has "$f" 'naming both|both values' "$n: the error names the recorded mode and the current one"
done

# --- 4. the Linear-mode outcome is recorded, not silent ---------------------
has "$COMP" 'linear_mode' "the checkpoint records plan_completion_checkpoint: linear_mode"
has "$COMP" 'git mv' "and states what it is recording instead of: the git mv"
has "$COMP" 'GitHub integration|PR merge|merge moves' \
  "the prose says what does move the parent to Done"
has "$LEARN" 'linear' "en-learn branches on the mode too"

# --- 5. a plan with no provenance field is legacy, and is not refused -------
# Every plan written before this feature is one. Refusing them would break
# every in-flight branch on the day this ships.
for f in "$COMP" "$LEARN"; do
  n=$(basename "$(dirname "$f")")
  has "$f" 'legacy|predat|no provenance|absent' "$n: a plan with no provenance field is legacy"
  has "$f" 'treat.*local|read as `?local|assume.*local' "$n: and is read as local"
done

# --- 6. local mode is untouched ---------------------------------------------
# The whole feature is opt-in; a future edit that quietly stopped local mode
# moving the plan to completed/ would pass every clause above.
has "$COMP" 'completed/' "local mode still moves the plan to docs/plans/completed/"
has "$SHIP" 'plan_completion_checkpoint' "the ship summary still records the checkpoint outcome"

# --- 7. a failed archive is not mistaken for a generated file ---------------
# Both live under a plan-shaped name; only the directory tells them apart.
has "$COMP" 'materialized-plans|generated' \
  "a materialized plan is told from an authoring plan by its directory"

report
