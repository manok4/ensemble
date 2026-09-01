#!/usr/bin/env bash
# tests/lint/en-foundation-discovery.test.sh
#
# The six mechanisms added to /en-foundation on 2026-09-01, and the four files
# the same pass removed.
#
# Every clause here is scoped to ONE file and anchored on wording only that file
# carries. This campaign produced roughly ten guards that could not fail because
# a whole-directory grep was satisfied by an incidental mention somewhere else in
# the skill; each was caught only by breaking the target and watching the test
# stay green. Widening any grep below re-opens that hole.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-foundation discovery"
cd "$REPO_ROOT"

SKILL=skills/en-foundation/SKILL.md
Q=skills/en-foundation/references/foundation-questions.md

has() {  # $1=file  $2=ERE  $3=label
  grep -qE "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$1")"
}

# --- 1. orient writes a ledger, and discovery subtracts against it ------------
# Without the subtraction the ledger is a report nobody acts on, so both halves
# are asserted, in the two different steps that must carry them.
has "$SKILL" 'known-facts ledger'                        "orient produces a known-facts ledger"
has "$SKILL" 'Ask only what the ledger left open'        "discovery subtracts what orient answered"
# Anchored on each site's own wording. The bare phrase "confirmed in one line"
# occurs in BOTH the discovery loop and the retrofit section, so a grep for it
# stayed green when either one was deleted — a decorative clause, caught by its
# own negative control. Two sites, two anchors.
has "$SKILL" 'confirmed in one line\*\* \(\*"Detected' "discovery confirms an answered group instead of asking it"
has "$SKILL" 'confirmed in one line each'                "the retrofit confirms its four detected groups"
has "$Q"     'after the orient ledger has been subtracted' "the question bands count post-subtraction"

# The bands themselves must still be there — subtraction without a band is a
# licence to ask forever.
# Anchored on the row start: the band's dash is a multibyte en-dash, and a "."
# there matches one of its three bytes, not the character.
has "$Q"     '^\| Deep \| 30'                            "the Deep question band survives"

# --- 2. the traceability gate ------------------------------------------------
has "$SKILL" '6a\. \*\*Traceability gate' "the traceability gate is its own step"

# The load-bearing words. ce tried a mechanical "every ID appears" rule and threw
# it out: a tally invites requirements written to satisfy the counter, which then
# reach plans as real work. If the judgment clause is ever dropped, this is the
# clause that notices.
has "$SKILL" '\*\*that affects behavior\*\*'  "coverage is scoped by a judgment clause"
has "$SKILL" 'never "every ID appears'        "the mechanical-tally reading is ruled out by name"
has "$SKILL" 'Deferral is a first-class outcome' "an uncovered goal may be deferred, not force-fitted"

# A gate that fires on a section the depth tier omitted produces empty headers
# and dangling IDs — the failure ce warned about in the no-origin path.
has "$SKILL" 'Conditional on the section existing' "the gate does not fire on absent sections"

# --- 3. report at the precision you have -------------------------------------
has "$SKILL" 'Report at the precision you actually have' "the precision rule is stated"
has "$SKILL" 'Never upgrade a directional goal'          "a directional goal is not rendered as a metric"
has "$SKILL" 'No invented metrics'                       "an ungiven measure is TBD, not a figure"
has "$SKILL" "Use the user's terminology"                "the user's vocabulary is preserved"

# Written as a character class so this line cannot match itself.
if grep -qE '\[TO' "$SKILL" && ! grep -qE 'must not appear in the output' "$SKILL"; then
  fail "placeholder text is forbidden, not demonstrated"
else
  pass "placeholder text is forbidden, not demonstrated"
fi

# --- 4. §9 gets a quality bar ------------------------------------------------
has "$Q" 'Design it twice'                "§9 requires a second, structurally distinct shape"
has "$Q" 'Record the rejected alternative' "the losing shape is recorded as a decision"

# All four red flags, each individually — a count would pass on four copies of one.
for flag in 'Shallow module' 'Information leakage' 'Temporal decomposition' 'Pass-through'; do
  has "$Q" "$flag" "red flag screened: $flag"
done

# --- 5. the retrofit scopes before it scans ----------------------------------
has "$SKILL" 'Scope before you scan'  "the retrofit scopes before scanning"
has "$SKILL" 'git log --oneline'      "hot spots come from commit history"

# --- 6. the cuts stay cut ----------------------------------------------------
# Each of these was reachable, and none was needed. A skill that starts carrying
# one again has almost certainly re-linked it from a shared file by accident.
for f in agents/learnings-research.md agents/web-research.md \
         references/diff-signal-detection.md references/architecture-update-rules.md; do
  if [ -e "skills/en-foundation/$f" ]; then
    fail "en-foundation no longer carries $f"
  else
    pass "en-foundation no longer carries $f"
  fi
done

# The contradiction that kept two of them alive: the shared dispatch matrix said
# en-foundation always dispatches a learnings scout, while the flow never did.
grep -qE '^\| .en-foundation. \| \(any\) \|.*\| never \|' \
  skills/en-foundation/references/research-dispatch.md \
  && pass "the dispatch matrix agrees with the flow: no learnings scout" \
  || fail "the dispatch matrix agrees with the flow: no learnings scout"

# en-plan lost diff-signal-detection by the same edit and for the same reason:
# it reviews a document it just wrote, so is_small_and_safe has no diff to read.
[ -e skills/en-plan/references/diff-signal-detection.md ] \
  && fail "en-plan no longer carries diff-signal-detection either" \
  || pass "en-plan no longer carries diff-signal-detection either"

# The skills that DO review a diff must still carry it — the cut was scoped, not
# a blanket removal, and this is the half that proves it.
for s in en-review en-qa; do
  [ -e "skills/$s/references/diff-signal-detection.md" ] \
    && pass "$s still carries diff-signal-detection" \
    || fail "$s still carries diff-signal-detection"
done

report
