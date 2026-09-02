#!/usr/bin/env bash
# tests/lint/test-harness-integrity.test.sh
#
# The suites in this repo are the only thing standing behind a large body of
# prose specification. A suite that cannot fail is worse than no suite: it
# reports green and is counted as coverage.
#
# Two ways that happened here, both found by peer review rather than by the
# tests themselves:
#
#   1. An assertion placed in the last component of a pipeline. bash runs that
#      in a subshell, so pass/fail counter updates are discarded — the failure
#      prints and the suite still reports every assertion passing.
#   2. A `report` call omitted, so the exit status never reflects the failures.
#
# This checks the harness itself, mechanically, for both.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="test harness integrity"

# --- no assertion inside a pipeline subshell ---------------------------------
# A `{` or `(` opening the final stage of a pipeline, anywhere a pass/fail could
# land inside it.
offenders=""
for t in "$REPO_ROOT"/tests/*/*.test.sh; do
  awk '
    /\| *[({] *$/ { inblock=1; start=NR; next }
    inblock && /^[)}]/ { inblock=0; next }
    inblock && /(^|[^a-z_])(pass|fail) "/ { print FILENAME ":" start; inblock=0 }
  ' "$t"
done > /tmp/_harness_offenders.$$ 2>/dev/null
offenders=$(cat /tmp/_harness_offenders.$$); rm -f /tmp/_harness_offenders.$$

if [ -z "$offenders" ]; then
  pass "no assertion runs inside a pipeline subshell"
else
  fail "no assertion runs inside a pipeline subshell" \
       "$(echo "$offenders" | sed "s|$REPO_ROOT/||" | tr '\n' ' ')"
fi

# --- every suite calls report ------------------------------------------------
# Without it the exit status ignores the failures entirely.
missing=""
for t in "$REPO_ROOT"/tests/*/*.test.sh; do
  grep -q '^report$' "$t" || missing="$missing $(basename "$t")"
done
if [ -z "$missing" ]; then
  pass "every suite calls report"
else
  fail "every suite calls report" "$missing"
fi

# --- every suite sources the shared harness ----------------------------------
nosrc=""
for t in "$REPO_ROOT"/tests/*/*.test.sh; do
  grep -q 'tests/lib/assert.sh' "$t" || nosrc="$nosrc $(basename "$t")"
done
if [ -z "$nosrc" ]; then
  pass "every suite sources tests/lib/assert.sh"
else
  fail "every suite sources tests/lib/assert.sh" "$nosrc"
fi

# --- no platform-specific hashing --------------------------------------------
# The BSD hash flag is macOS-only; a parity suite that dies on the hash never reaches the
# comparison it exists for. hash_file in the shared lib covers all three spellings.
# Character classes so this pattern cannot match itself.
#
# Comment lines are stripped first. The pattern matched a suite's own comment
# explaining WHY it uses hash_file instead of the platform spelling — so the rule
# forbade documenting itself, and the only way to comply was to leave the reason
# out. A guard that its own explanation trips is measuring the prose, not the code.
badhash=""
for f in "$REPO_ROOT"/tests/*/*.test.sh; do
  [ -f "$f" ] || continue
  sed 's/[[:space:]]*#.*$//' "$f" | grep -q 'md[5] -q\|md[5]sum ' && badhash="$badhash $f"
done
if [ -z "$badhash" ]; then
  pass "no suite calls a platform-specific hash directly"
else
  fail "no suite calls a platform-specific hash directly" \
       "$(echo $badhash | sed "s|$REPO_ROOT/||g")"
fi

report
