#!/usr/bin/env bash
# tests/lint/en-plan-warranted-gate.test.sh
#
# en-plan always wrote a file. A one-line dependency bump got U-IDs, a peer
# pass, a plan hash and a commit: ceremony that costs more than it returns and
# leaves a plan in docs/plans/active/ that someone has to close out.
#
# The first fix put the offer inside the write step, which made it reachable
# but late: intake, research, question rounds, the unit breakdown and the
# pre-write review had all run before the user heard a plan was not needed.
# D138 moved it to the routing step, before any research dispatch, and replaced
# its size conditions (Lightweight, one unit) with plan-or-fix.md's list of
# what a plan settles.
#
# What keeps the gate safe rather than a hole:
#
#   It is early and reachable. Inside the numbered flow, before research.
#
#   It reads the shared list. en-fix triages against the same file, byte for
#   byte, so a request one skill refuses is one the other accepts.
#
#   It is honest about the consequence. /en-build consumes a plan file. Decline
#   the file and there is nothing to build, so the offer says so.
#
#   It refuses where a plan must happen: a resume or legacy run, a user who
#   asked for the file, and any risk surface, which is exactly the one-unit
#   change that most wants a written plan and a peer pass.
#
# Negative controls at authoring: moving the route step below research, deleting
# the plan-or-fix.md citation, dropping the design-doc condition from the list,
# and deleting the risk-surface carve-out each turned its assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan routing gate"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
LIST="$REPO_ROOT/skills/en-plan/references/plan-or-fix.md"

proc=$(grep -n '^## Process' "$SKILL" | head -1 | cut -d: -f1)
endp=$(awk -v p="$proc" 'NR>p && /^## / {print NR; exit}' "$SKILL")
gate=$(grep -nE '^[0-9]+\. \*\*Route, then right-size depth\.\*\*' "$SKILL" | head -1 | cut -d: -f1)
research=$(grep -nE '^[0-9]+\. \*\*Phase 1 research' "$SKILL" | head -1 | cut -d: -f1)
gate_block=$(awk -v a="$gate" 'NR==a' "$SKILL")

# --- 1. the gate sits in the numbered flow, before any research ---
if [ -n "$gate" ] && [ "$gate" -gt "$proc" ] && [ "$gate" -lt "$endp" ]; then
  pass "the gate sits inside the numbered flow (line $gate, flow $proc-$endp)"
else
  fail "the gate must sit inside the numbered flow" "gate=$gate flow=$proc-$endp"
fi
if [ -n "$gate" ] && [ -n "$research" ] && [ "$gate" -lt "$research" ]; then
  pass "the gate fires before research is dispatched (gate=$gate research=$research)"
else
  fail "the gate must fire before research" "gate=$gate research=$research"
fi

# --- 2. it decides by the shared list, not by size ---
printf '%s' "$gate_block" | grep -qF 'references/plan-or-fix.md' \
  && pass "the gate tests the request against references/plan-or-fix.md" \
  || fail "the gate must cite references/plan-or-fix.md"
missing=""
# 'design doc' is the condition that is not about the work at all: the close-out
# that retires a consumed design lives in the promotion block, which the no-plan
# path never reaches, so skipping the plan would strand that design at
# status: open and back in /en-brainstorm's resume pool.
for c in 'An open decision' 'A risk surface' 'must land in order' 'More than one session' 'A design doc' 'no file or line count'; do
  grep -qiF "$c" "$LIST" || missing="$missing '$c'"
done
[ -z "$missing" ] \
  && pass "the list names every condition and rules out a size count" \
  || fail "a condition went missing from plan-or-fix.md" "missing:$missing"
grep -qE '\b(one unit|Lightweight)\b' <<<"$gate_block" \
  && fail "the gate must not decide by size" "it names one unit or Lightweight" \
  || pass "the gate does not decide by unit count or depth"

# --- 3. the refusals ---
missing=""
for c in '`--resume`' '`--from-legacy`' 'asked for a plan file' 'a risk surface (authentication, payments, migrations, external contracts) always gets the plan'; do
  printf '%s' "$gate_block" | grep -qF "$c" || missing="$missing '$c'"
done
[ -z "$missing" ] \
  && pass "the offer is refused on resume, legacy, an explicit request and any risk surface" \
  || fail "a refusal went missing from the gate" "missing:$missing"

# --- 4. the consequence is stated, and the path leads somewhere ---
# /en-plan "fix the typo in the --verbose help text" holds no condition. The
# user who takes the offer gets no plan file and no U-IDs, is told /en-build
# cannot run, and is pointed at /en-fix (D124). Suggested, never invoked:
# /en-fix is manual-only, and contract-shape.test.sh catches an invoke.
if printf '%s' "$gate_block" | grep -qF 'no file, no U-IDs' \
   && printf '%s' "$gate_block" | grep -qiE 'consumes a plan file' \
   && printf '%s' "$gate_block" | grep -qF '`/en-fix <request>`'; then
  pass "declining the plan names its consequence for /en-build and suggests /en-fix"
else
  fail "the gate must state that /en-build cannot run and suggest /en-fix" \
       "implying a handoff that cannot happen is worse than writing the file"
fi
printf '%s' "$gate_block" | grep -qF 'close the run' \
  && pass "taking the offer closes the run the route opened" \
  || fail "the gate's stop must close the run" "an open run parents every later run in the repo"

# --- 5. the old write-step offer is gone, so there is one gate, not two ---
if grep -qF 'Is a plan file warranted' "$SKILL" "$REPO_ROOT/skills/en-plan/references/plan-prewrite.md"; then
  fail "the write-step offer was removed" "two gates with different conditions disagree"
else
  pass "the write-step offer was removed"
fi

# --- 6. en-fix reads the same list ---
assert_eq "$(hash_file "$LIST")" "$(hash_file "$REPO_ROOT/skills/en-fix/references/plan-or-fix.md")" \
  "en-plan and en-fix carry the same plan-or-fix.md"

report
