#!/usr/bin/env bash
# tests/lint/en-test-audit-contract.test.sh
#
# /en-test-audit deletes tests, so the order of its steps is the safety
# property. The scripts it calls are tested on their own (tests/en-test-audit/);
# this guards that the flow calls them, and in the order that makes them mean
# anything. A verifier that runs after the commit, or a ledger written after the
# edit, would pass every script test and protect nothing.
#
#   USER-INVOKED ONLY      disable-model-invocation, so nothing dispatches it
#                          and it needs no CONTRACT.md (D122).
#   PREFLIGHT FIRST        the refusals run before discovery reads anything.
#   LEDGER BEFORE EDIT     evidence is written before the batch is touched.
#   VERIFY BEFORE COMMIT   the ledger verifier gates the commit (U2).
#   MUTATE ON CLEAN CODE   after the test edits, before seams touch production (U3).
#   RED BASELINE KEPT      a failing test is a product bug, never a deletion.
#   NO PUSH, NO MERGE      /en-ship owns those.
#
# Negative controls at authoring: removing disable-model-invocation, moving the
# preflight below discovery, moving the ledger step below the edit step, moving
# the verifier below the commit, moving the mutation step below the seam
# removal, and deleting the red-baseline clause each turned its assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-test-audit flow contract"

SK="$REPO_ROOT/skills/en-test-audit/SKILL.md"
assert_file_exists "$SK" "the skill exists"

# The number of the first Process step whose line matches a pattern.
step_of() { awk -v pat="$1" '/^## Process/{on=1; next} /^## /{on=0} on && /^[0-9]+\. / && $0 ~ pat {sub(/\..*/, ""); print; exit}' "$SK"; }

frontmatter=$(awk 'NR==1 && /^---$/{on=1; next} on && /^---$/{exit} on' "$SK")
printf '%s' "$frontmatter" | grep -qx 'disable-model-invocation: true' \
  && pass "it is user-invoked only" \
  || fail "SKILL.md must carry disable-model-invocation: true" \
          "a skill that deletes tests is not something another skill should dispatch"
[ ! -f "$REPO_ROOT/skills/en-test-audit/CONTRACT.md" ] \
  && pass "it carries no CONTRACT.md, since no skill calls it" \
  || fail "en-test-audit must not carry a CONTRACT.md" "contract-shape requires callers for one"

pre=$(step_of 'ensemble-test-audit-preflight'); disc=$(step_of '\\*\\*Discover')
if [ -n "$pre" ] && [ -n "$disc" ] && [ "$pre" -lt "$disc" ]; then
  pass "the preflight (step $pre) runs before discovery (step $disc)"
else
  fail "the preflight must run before discovery" "preflight=${pre:-none} discover=${disc:-none}"
fi

led=$(step_of 'references/ledger-format.md'); edit=$(step_of '\\*\\*Edit one owner-boundary batch')
if [ -n "$led" ] && [ -n "$edit" ] && [ "$led" -lt "$edit" ]; then
  pass "the ledger (step $led) is written before the batch is edited (step $edit)"
else
  fail "the ledger must be written before the edit" "ledger=${led:-none} edit=${edit:-none}"
fi

ver=$(step_of 'ensemble-test-ledger-verify'); com=$(step_of '^[0-9]+\\. \\*\\*Commit\\*\\*')
if [ -n "$ver" ] && [ -n "$com" ] && [ "$ver" -lt "$com" ] && [ "$edit" -lt "$ver" ]; then
  pass "the ledger is verified (step $ver) after the edit and before the commit (step $com)"
else
  fail "the verifier must run between the edit and the commit" "edit=${edit:-none} verify=${ver:-none} commit=${com:-none}"
fi
# Mutations run on clean production files: after the test edits, before the
# seam removal touches production code (the check refuses dirty targets), and
# before the verifier, which requires their diffs to exist.
mut=$(step_of 'ensemble-mutation-check'); seam=$(step_of '\\*\\*Remove the seams')
if [ -n "$mut" ] && [ -n "$seam" ] && [ "$edit" -lt "$mut" ] && [ "$mut" -lt "$seam" ] && [ "$mut" -lt "$ver" ]; then
  pass "mutations (step $mut) run after the test edits and before seams (step $seam) and the verifier"
else
  fail "mutations must run between the test edits and the seam removal" \
       "edit=${edit:-none} mutation=${mut:-none} seams=${seam:-none} verify=${ver:-none}"
fi
grep -qiE 'never its bare name' "$SK" \
  && pass "--expect is the keeper's failure output, never its bare name" \
  || fail "SKILL.md must say --expect is failure output, not a name" \
          "a name printed on a passing run proves nothing about failure"

awk '/^## Process/{on=1} /^## Retention/{on=0} on' "$SK" | grep -qE 'Nothing is committed until it exits 0' \
  && pass "the commit is conditional on the verifier's exit 0" \
  || fail "the flow must commit only on the verifier's exit 0"
grep -qF 'Test-Audit-Ledger:' "$SK" \
  && pass "the commit carries a Test-Audit-Ledger: trailer" \
  || fail "the commit must carry a Test-Audit-Ledger: trailer"

grep -qiF 'never deleted to make the suite pass' "$SK" \
  && pass "a red baseline is reported, never deleted" \
  || fail "SKILL.md must say a baseline failure is never deleted" \
          "deleting the failing test is the cheapest way to a green suite"

grep -qiE 'never pushes, never opens a PR, never merges' "$SK" \
  && pass "it never pushes, opens a PR or merges" \
  || fail "SKILL.md must leave push, PR and merge to /en-ship"

report
