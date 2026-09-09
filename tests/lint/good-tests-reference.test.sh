#!/usr/bin/env bash
# tests/lint/good-tests-reference.test.sh
#
# Tests were written in /en-build and judged in /en-review against a rubric
# /en-build never saw. The reviewer's testing dimension had nine categories; the
# writer had one line about mocks. On the EN16 build the testing persona was the
# slowest reviewer at 627s, and its findings were fixes for tests written hours
# earlier by a step with no rubric in front of it.
#
# references/good-tests.md is the shared definition. What is guarded here:
#
#   IT IS REACHED FROM BOTH SIDES  the writer at 9c, the reviewer's testing persona.
#   EVERY ANTI-PATTERN HAS A TELL  a prohibition nobody can detect is decorative.
#   THE TWO COPIES DO NOT DRIFT    the peer sees only the brief's text, so the
#                                  brief restates the anti-patterns; that
#                                  duplication is allowed and checked, not
#                                  allowed and forgotten.
#
# Negative controls at authoring: deleting one tell turned the tell assertion
# red; removing the tautological row from the peer brief turned the drift
# assertion red; dropping the 9c pointer turned the reachability assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="the shared good-tests reference"

GT="$REPO_ROOT/skills/en-build/references/good-tests.md"
LOOP="$REPO_ROOT/skills/en-build/references/unit-loop.md"
DISPATCH="$REPO_ROOT/skills/en-review/references/persona-dispatch.md"
BRIEF="$REPO_ROOT/skills/en-review/references/peer-brief.md"

assert_file_exists "$GT" "the shared reference exists"

# --- 1. both sides reach it -------------------------------------------------
# Scoped to the 9c bullet, not the file: the rubric has to be in front of the
# writer BEFORE the first test, and a mention further down does not do that.
# (The first version grepped the whole file and stayed green when the 9c pointer
# was deleted, because the system-wide check names the file too.)
if awk '/^- \*\*9c\. Implement\.\*\*/' "$LOOP" | grep -qF 'references/good-tests.md'; then
  pass "the unit loop points at it on 9c, before the unit's tests get written"
else
  fail "9c must point at good-tests.md" \
       "the writer needs the rubric before writing, not after review finds the gap"
fi
grep -qF 'references/good-tests.md' "$DISPATCH" \
  && pass "the testing persona points at it" \
  || fail "persona-dispatch must point the testing dimension at good-tests.md"

# --- 2. the anti-patterns, and a tell for each -------------------------------
# The names are the contract between the two files; the tells are what makes a
# name actionable rather than a slogan.
PATTERNS='Implementation-coupled Tautological "Horizontal slicing" "Reads source instead of running it" "Mocked past the boundary"'
missing=""
for pat in "Implementation-coupled" "Tautological" "Horizontal slicing" "Reads source instead of running it" "Mocked past the boundary"; do
  grep -qF "$pat" "$GT" || missing="$missing '$pat'"
done
[ -z "$missing" ] \
  && pass "all five anti-patterns are named" \
  || fail "good-tests.md is missing an anti-pattern" "$missing"

tells=$(grep -c '\*The tell:' "$GT" || true)
[ "$tells" -eq 5 ] \
  && pass "every anti-pattern carries its tell (5)" \
  || fail "every anti-pattern must carry a tell" "found $tells, expected 5"

# --- 3. the definition itself, not just the failures -------------------------
if grep -qiE 'through the public interface, not the' "$GT" && grep -qiE 'reads like a specification' "$GT"; then
  pass "it says what a good test IS, not only what to avoid"
else
  fail "good-tests.md must define a good test positively" \
       "a list of anti-patterns alone tells a writer what not to do and nothing about what to do"
fi

# Seams are /en-plan's decision; restating them here would fork the rule.
if grep -qiE 'en-plan.*seams|seams.*en-plan' "$GT" && ! grep -qE '^\- \*\*Prefer a seam' "$GT"; then
  pass "it defers the seam rules to /en-plan rather than forking them"
else
  fail "good-tests.md must defer seam selection to /en-plan"
fi

# --- 4. the deliberate duplication does not drift ----------------------------
# The peer runs as a subprocess and is given the brief's text as its prompt, so
# a pointer would be one it cannot follow. The brief therefore restates the
# anti-patterns, and this is the assertion that keeps the two in step.
drift=""
for pat in "Tautological" "Horizontal slicing" "read source instead of running it"; do
  grep -qiF "$pat" "$BRIEF" || drift="$drift '$pat'"
done
[ -z "$drift" ] \
  && pass "the peer brief's testing rubric names the same anti-patterns" \
  || fail "the peer brief has drifted from good-tests.md" \
          "missing:$drift — the peer sees only the brief, so what is absent there is not reviewed"

grep -qiE 'duplication is deliberate|pointer to this file would be a' "$GT" \
  && pass "the duplication is named as deliberate, with its reason" \
  || fail "good-tests.md must say why the peer brief repeats it" \
          "an unexplained second copy reads as drift to whoever edits next"

report
