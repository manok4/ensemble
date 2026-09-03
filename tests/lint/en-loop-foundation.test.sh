#!/usr/bin/env bash
# Drift guards for foundation D40 + the en-loop skill-catalog entry (EN06 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-loop foundation"

FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- D40 exists and names en-loop ---
d40="$(grep -E "^- \*\*D40\." "$FOUNDATION" || true)"
if [ -n "$d40" ] && printf '%s' "$d40" | grep -qiE "en-loop"; then
  pass "foundation has D40 naming en-loop"
else
  fail "foundation must add D40 for en-loop"
  report
fi

# --- D40 names the wrap-gnhf engine choice ---
if printf '%s' "$d40" | grep -qiE "wrap.*gnhf|gnhf.*wrap"; then
  pass "D40 records the wrap-gnhf engine choice"
else
  fail "D40 must record wrapping gnhf (not native)"
fi

# --- D40 records the test-gate + checkpoint-review cadence ---
if printf '%s' "$d40" | grep -qiE "test-gate" && printf '%s' "$d40" | grep -qiE "checkpoint|--review-every|en-review"; then
  pass "D40 records the test-gate-per-iteration + checkpoint-review cadence"
else
  fail "D40 must record the test-gate + checkpoint-review cadence"
fi

# --- D40 records the two modes ---
if printf '%s' "$d40" | grep -qiE "Hands-Off" && printf '%s' "$d40" | grep -qiE "Companion"; then
  pass "D40 records the two modes (Hands-Off, Companion)"
else
  fail "D40 must record the Hands-Off and Companion modes"
fi

# --- Integration: 'completion is not acceptance' + evidence-based stop appear in D40 ---
if printf '%s' "$d40" | grep -qiE "completion is not acceptance|completion ≠ acceptance"; then
  pass "D40 states 'completion is not acceptance'"
else
  fail "D40 must state the completion-is-not-acceptance rule"
fi
if printf '%s' "$d40" | grep -qiE "evidence-based stop|evidence-based.*stop-when|evidence-based condition"; then
  pass "D40 requires evidence-based stop conditions"
else
  fail "D40 must require evidence-based stop conditions"
fi

# --- D40 notes the external gnhf dependency surfaced by en-setup ---
if printf '%s' "$d40" | grep -qiE "npm i -g gnhf|en-setup"; then
  pass "D40 notes the gnhf dependency surfaced by en-setup"
else
  fail "D40 must note the external gnhf dependency (en-setup surfaces it)"
fi

# --- Catalog §5.1 table has an en-loop row ---
if grep -qE "^\| *[0-9]+ *\| \`en-loop\`" "$FOUNDATION"; then
  pass "§5.1 skill-summary table has an en-loop row"
else
  fail "§5.1 table must add an en-loop row"
fi

# --- Catalog §5.2.x details subsection for en-loop ---
if grep -qE "^#### 5\.2\.[0-9]+ \`en-loop\`" "$FOUNDATION"; then
  pass "§5.2.x has an en-loop details subsection"
else
  fail "§5.2.x must add an en-loop details subsection"
fi

# --- Catalog header count + en-loop in the orthogonal list ------------------
# The count is worth asserting: it is the cheapest way to notice a skill added
# or removed without the catalog moving. It was asserted as the literal word
# "Fourteen" until 2026-09-03, which is the opposite of that. en-flow and
# en-simplify had been added, both with 5.1 rows, and the sentence still said
# fourteen; the guard did not notice, and anyone correcting the number would
# have been failed by it. A count pinned to a word only ever tests that nobody
# fixed it.
#
# So: derive from skills/ and compare. NUM spells the digits out because the
# sentence does, and a mismatch names both sides rather than just going red.
n=$(find "$REPO_ROOT/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
case "$n" in
  12) word="Twelve" ;;  13) word="Thirteen" ;;  14) word="Fourteen" ;;
  15) word="Fifteen" ;; 16) word="Sixteen" ;;   17) word="Seventeen" ;;
  18) word="Eighteen" ;; 19) word="Nineteen" ;; 20) word="Twenty" ;;
  *)  word="" ;;
esac

intro=$(grep -iE '^[A-Z][a-z]+ skills total:' "$FOUNDATION" | head -1)
if [ -z "$intro" ]; then
  fail "§5 must open with a '<N> skills total:' line" "no such line"
elif [ -z "$word" ]; then
  fail "extend the number-word table in this test" "skills/ holds $n directories"
elif [ "${intro%% skills total:*}" = "$word" ]; then
  pass "§5 header count matches the $n directories in skills/"
else
  fail "§5 header count is stale" "says '${intro%% skills total:*}', skills/ holds $n ($word)"
fi

# Every skill directory must appear in that same sentence. This is what the
# literal-word check could not do: en-flow and en-simplify were missing from the
# list for as long as the count was wrong, and both facts had one cause.
missing=""
for d in "$REPO_ROOT"/skills/*/; do
  name=$(basename "$d")
  short=${name#en-}
  case "$intro" in *"$name"*|*"$short"*) ;; *) missing="$missing $name" ;; esac
done
[ -z "$missing" ] \
  && pass "§5 intro names every skill in skills/" \
  || fail "§5 intro omits a skill that exists" "$missing"

# en-loop specifically, since this file is en-loop's foundation guard.
case "$intro" in
  *en-loop*) pass "§5 intro lists en-loop among the orthogonal skills" ;;
  *) fail "§5 intro must list en-loop among the orthogonal skills" ;;
esac

# The 5.1 table numbers its rows; the numbers must run 1..N with no gap. They
# ran 1..17 across 16 rows until 2026-09-03, skipping 11 where a retired skill
# had been.
nums=$(grep -oE '^\| [0-9]+ \| `en-[a-z-]+`' "$FOUNDATION" | grep -oE '[0-9]+' | tr '\n' ' ')
expect=""; i=1
for _ in $nums; do expect="$expect$i "; i=$((i+1)); done
assert_eq "$nums" "$expect" "the 5.1 table numbers its rows 1..N with no gap"

report
