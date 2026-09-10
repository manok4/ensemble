#!/usr/bin/env bash
# tests/lint/en-qa-autonomy-contract.test.sh
#
# en-build's autonomy contract has been guarded since it was written. en-qa's
# had NO guard at all, while its heading claimed it mirrored en-build's and its
# anti-patterns claimed to be "the same as" that skill's. Neither was true: the
# five pause cases have zero overlap, and en-qa's anti-patterns carried no tells
# where every comparable list in the repo does (en-build, en-debug, good-tests.md
# in both carriers, peer-brief.md).
#
# What is guarded here, and why each:
#
#   THE WINDOW IS NAMED           a contract with no stated scope forbids
#                                 everything or nothing, depending on the reader.
#   THE PAUSE LIST IS EXHAUSTIVE  "no others permitted" is the whole mechanism;
#                                 an open-ended list is a suggestion.
#   EVERY ANTI-PATTERN HAS A TELL a prohibition nobody can detect is decorative.
#   THE CROSS-REFERENCE IS HONEST claiming to mirror a contract whose cases
#                                 differ sends a reader looking for five cases
#                                 that are not there.
#   A DRIVEN RUN NEVER BLOCKS     /en-loop runs this unattended; a question with
#                                 nobody watching does not fail, it waits, and a
#                                 stalled run is indistinguishable from a slow one.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-qa autonomy contract"

SKILL="$REPO_ROOT/skills/en-qa/SKILL.md"
BUILD="$REPO_ROOT/skills/en-build/SKILL.md"

# The contract block only, so a phrase elsewhere in the skill cannot satisfy it.
CONTRACT=$(awk '/^## Agent autonomy contract/{f=1; next} f&&/^## /{exit} f' "$SKILL")
[ -n "$CONTRACT" ] && pass "en-qa has an autonomy contract section" \
  || fail "en-qa must carry an autonomy contract"

has() { printf '%s' "$CONTRACT" | grep -qiE "$1" && pass "$2" || fail "$2"; }

# --- the window ---------------------------------------------------------------
has 'Scope of the contract'            "the contract names its scope"
has 'already-runnable QA flows'        "the window is the runnable-flow period, not the whole run"
has 'Pre-flow setup is NOT governed'   "pre-flow decisions are carved out explicitly"

# --- the pause list is closed --------------------------------------------------
has 'exhaustive within scope, no others permitted' \
                                       "the pause list is closed, not illustrative"
cases=$(printf '%s' "$CONTRACT" | grep -cE '^[0-9]+\. \*\*')
[ "$cases" -eq 5 ] \
  && pass "five pause cases, matching the count the scope promises" \
  || fail "the scope says five pause cases" "found $cases"

# --- every anti-pattern carries a tell ----------------------------------------
# The standard the rest of the repo uses. Counted rather than grepped once: one
# tell on four bullets is the shape this is meant to catch.
AP=$(printf '%s' "$CONTRACT" | awk '/^### Anti-patterns/{f=1; next} f&&/^### /{exit} f')
bullets=$(printf '%s' "$AP" | grep -c '^- \*\*')
tells=$(printf '%s' "$AP" | grep -c 'The tell:')
[ "$bullets" -gt 0 ] && [ "$bullets" -eq "$tells" ] \
  && pass "every anti-pattern carries a tell ($tells of $bullets)" \
  || fail "each anti-pattern needs a tell" "bullets=$bullets tells=$tells"

# --- the cross-reference tells the truth ---------------------------------------
# It claimed to mirror en-build's contract and to share its anti-patterns. The
# pause cases have no overlap, so the claim sent readers to the wrong list.
HEADING=$(grep -m1 '^## Agent autonomy contract' "$SKILL")
printf '%s\n%s' "$HEADING" "$CONTRACT" | grep -qiE 'mirrors .?.?/en-build|same as .?.?/en-build' \
  && fail "en-qa must not claim its cases mirror /en-build's" \
       "the five pause cases have zero overlap; say what is actually shared" \
  || pass "en-qa does not claim its pause cases mirror /en-build's"
has 'The cases are not|different cases' \
                                       "the difference from /en-build is stated, not implied"

# And the claim is checked against the other skill, so a later edit that makes
# them genuinely identical is not punished for it.
build_cases=$(awk '/^### Legitimate pause cases/{f=1; next} f&&/^### /{exit} f' "$BUILD" \
              | grep -oE '^[0-9]+\. \*\*[^*]+\*\*' | sed 's/^[0-9]*\. //')
qa_cases=$(printf '%s' "$CONTRACT" | awk '/^### Legitimate pause cases/{f=1; next} f&&/^### /{exit} f' \
           | grep -oE '^[0-9]+\. \*\*[^*]+\*\*' | sed 's/^[0-9]*\. //')
overlap=$(comm -12 <(printf '%s\n' "$build_cases" | sort) <(printf '%s\n' "$qa_cases" | sort) | grep -c . || true)
[ "${overlap:-0}" -eq 0 ] \
  && pass "the two contracts share no pause case, as the text now says" \
  || fail "a pause case is now shared; the 'different cases' claim needs revisiting" "overlap=$overlap"

# --- a driven run never blocks --------------------------------------------------
has 'When a caller is driving, none of those three may block' \
                                       "pre-flow questions become skips when a caller drives"
has 'waits, which is worse'            "the reason a blocked unattended run is worse than a failed one"

# --- uncertainty ----------------------------------------------------------------
has 'advance, not ask'                 "uncertainty resolves by advancing"

report
