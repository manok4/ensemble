#!/usr/bin/env bash
# tests/lint/en-learn-artifact-types.test.sh
#
# en-learn writes three kinds of artifact, not one. The split is load-bearing
# because the three differ in shape, lifecycle, and write path — the property the
# old bugs|patterns|decisions taxonomy never had, which is why nobody could apply
# it consistently.
#
# The routing rule is executed by a model, so these assertions lock down the
# SPECIFICATION: that the types are named with their paths, that the tie-break is
# an ordering rather than prose a reader could invert, and that each type carries
# a worked example. They do NOT show that a candidate routes correctly — that is
# behaviour, and TD7 tracks it.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn artifact types"

# Prose gets reflowed; a single-line grep goes red on a wrapped sentence, which
# is a false failure about formatting. Flatten before matching.

REF="$REPO_ROOT/skills/en-learn/references/artifact-types.md"
SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"

assert_file_exists "$REF" "the artifact-types reference exists"

# --- the three types, each with the path it writes to ----------------------
# A type named without its path cannot route anything.
while IFS='|' read -r label path; do
  grep -q "$path" "$REF" \
    && pass "$label names its path ($path)" \
    || fail "$label names its path ($path)"
done <<'PAIRS'
glossary|docs/CONTEXT.md
decision|docs/decisions/
solution|docs/learnings/
PAIRS

# --- the tie-break is an ORDERING -------------------------------------------
# A candidate can match two types. Prose saying "prefer the more durable one"
# is invertible by a reader who disagrees about which is more durable; an
# explicit ordering is not.
flat "$REF" | grep -qE 'term *> *decision *> *solution' \
  && pass "the tie-break is written as an explicit ordering" \
  || fail "the tie-break is written as an explicit ordering"

flat "$REF" | grep -qi 'more durable' \
  && pass "the ordering is justified by durability" \
  || fail "the ordering is justified by durability"

# --- worked examples ---------------------------------------------------------
# Few-shot examples are the only part of this reference that does measurable
# work on the model, so their absence is a real regression.
ex=$(grep -c '^### Routes to ' "$REF" 2>/dev/null || echo 0)
[ "$ex" -ge 3 ] \
  && pass "each type carries a worked example ($ex)" \
  || fail "each type carries a worked example (found $ex, need 3)"

# --- the gate runs first -----------------------------------------------------
# The gate decides WHETHER to write; the router decides WHICH artifact. A router
# that ran first would classify candidates that should never have been written.
flat "$REF" | grep -qi 'capture gate.*first\|after the capture gate\|gate.*runs first' \
  && pass "the gate is stated to run before the router" \
  || fail "the gate is stated to run before the router"

# --- honesty about what is verified -----------------------------------------
# TD7: shell tests check specifications. A reference claiming its routing is
# test-verified would be claiming coverage that does not exist.
flat "$REF" | grep -qi 'TD7\|not.*mechanically verif\|specification, not.*behaviour' \
  && pass "the reference states that routing is not mechanically verified" \
  || fail "the reference states that routing is not mechanically verified"

# --- declared in requires: ---------------------------------------------------
# A skill is self-contained: every file it reads is listed. An undeclared
# reference is invisible to the payload test and can be pruned silently.
grep -q 'references/artifact-types.md' "$SKILL" \
  && pass "artifact-types.md is declared in en-learn's requires:" \
  || fail "artifact-types.md is declared in en-learn's requires:"

report
