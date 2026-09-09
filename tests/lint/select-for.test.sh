#!/usr/bin/env bash
# tests/lint/select-for.test.sh
#
# tests/select-for.sh is the repo's own answer to "which tests could this change
# break". It exists because four consecutive branches lost time to the same loop:
# small edit, run the whole 286s suite, repeat. It is APPROXIMATE by design, so
# what is guarded here is the shape of that approximation, not its completeness:
#
#   IT NEVER RETURNS NOTHING QUIETLY   an unmatched path says so on stderr.
#   THE HARNESS ESCALATES              editing tests/lib or run.sh runs the lot,
#                                      because nothing is safe to approximate
#                                      when the thing that runs tests changed.
#   A SKILL EDIT PULLS ITS NEIGHBOURS  size, payload, parity and frontmatter all
#                                      move when a skill does, and all of them
#                                      have caught a real regression.
#
# It must NOT be trusted as final: many tests here anchor on file content and no
# path rule can find those. That caveat lives in the script and in AGENTS.md, and
# is asserted below so it cannot quietly disappear.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="select-for"

S="$REPO_ROOT/tests/select-for.sh"
assert_file_exists "$S" "the selector exists"
[ -x "$S" ] && pass "the selector is executable" || fail "the selector is executable"

pat() { ( cd "$REPO_ROOT" && bash "$S" --print "$@" 2>/dev/null ); }

# --- a skill edit selects its own tests and the cross-cutting ones ------------
p=$(pat skills/en-ship/SKILL.md)
for want in en-ship parity skill-size skill-payload frontmatter; do
  printf '%s' "$p" | grep -qF "$want" \
    && pass "a SKILL.md edit selects $want" \
    || fail "a SKILL.md edit must select $want" "got: $p"
done

# --- a script edit selects the script's own test ------------------------------
p=$(pat skills/en-ship/scripts/ensemble-ship-watch)
printf '%s' "$p" | grep -qF "ensemble-ship-watch" \
  && pass "a script edit selects the script's own test" \
  || fail "a script edit must select its own test" "got: $p"

# --- a test file selects itself -----------------------------------------------
p=$(pat tests/lint/en-ship-preflight.test.sh)
assert_eq "en-ship-preflight" "$p" "a test file selects itself and nothing else"

# --- foundation edits reach the decision-log guard ----------------------------
p=$(pat docs/foundation.md)
printf '%s' "$p" | grep -qF "decision-log-order" \
  && pass "a foundation edit selects the decision-log guard" \
  || fail "a foundation edit must select decision-log-order" "got: $p"

# --- the harness escalates to everything --------------------------------------
# A selector that approximates its own runner is a selector that can hide its
# own breakage.
# --print must ANSWER, never run: the first version exec'd the runner here and
# recursed through this very file until it was killed.
out=$( cd "$REPO_ROOT" && timeout 20 bash "$S" --print tests/lib/assert.sh 2>/dev/null )
assert_eq "FULL-SUITE" "$out" "a change to tests/lib escalates to the full suite"
out=$( cd "$REPO_ROOT" && timeout 20 bash "$S" --print tests/select-for.sh 2>/dev/null )
assert_eq "FULL-SUITE" "$out" "a change to the selector itself escalates too"
out=$( cd "$REPO_ROOT" && timeout 20 bash "$S" --print tests/run.sh 2>/dev/null )
assert_eq "FULL-SUITE" "$out" "a change to the runner escalates too"

# --- an unmatched path is reported, never silently empty ----------------------
err=$( cd "$REPO_ROOT" && bash "$S" --print README.md 2>&1 >/dev/null )
printf '%s' "$err" | grep -qF "run the full suite" \
  && pass "a path it cannot map says so and points at the full suite" \
  || fail "an unmatched path must be reported, not silently return nothing"

# --- the caveat is stated where a reader will hit it --------------------------
# The one way this becomes dangerous is someone treating it as authoritative.
grep -qiE 'not authoritative|must not be treated as one' "$S" \
  && pass "the script says it is not authoritative" \
  || fail "the script must say it is approximate"
grep -qF 'in full before you commit' "$REPO_ROOT/AGENTS.md" \
  && pass "AGENTS.md pairs it with the full run before committing" \
  || fail "AGENTS.md must pair the fast loop with a full run before commit"

# --- and the repo actually declares it, or nothing uses it --------------------
grep -qF "test_changed_command: './tests/select-for.sh {files}'" "$REPO_ROOT/AGENTS.md" \
  && pass "AGENTS.md declares it as test_changed_command" \
  || fail "the selector must be declared, or ensemble-test-select still reports empty"
sel=$( cd "$REPO_ROOT" && eval "$(bash skills/en-ship/scripts/ensemble-test-select --files skills/en-ship/SKILL.md)" && printf '%s' "$TEST_SELECT_TIER" )
assert_eq "graph" "$sel" "ensemble-test-select resolves the graph tier on this repo"

# --- usage ---------------------------------------------------------------------
( cd "$REPO_ROOT" && bash "$S" >/dev/null 2>&1 ); rc=$?
assert_eq "2" "$rc" "no arguments is a usage error"

report
