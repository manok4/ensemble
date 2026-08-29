#!/usr/bin/env bash
# tests/lint/skill-description-budget.test.sh
#
# Codex loads skills by progressive disclosure: it starts with every skill's name
# and description, and reads the full SKILL.md only once it selects one. The
# initial list gets "at most 2% of the model's context window, or 8,000 characters
# when the context window is unknown" — and when that budget is exceeded, Codex
# shortens descriptions first, then omits whole skills with a warning.
#   https://learn.chatgpt.com/docs/build-skills.md
#
# So the constrained surface is the DESCRIPTION, not the body. A shortened
# description may fail to trigger its skill, which is a discoverability failure
# and silent from the user's side.
#
# This repo was 1.2x over the budget when measured on 2026-08-29, and the tracker
# had recorded the opposite problem — that bodies were truncated — for three days.
# See TD2.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill description budget"

BUDGET=8000

# The description is a single YAML scalar; take from `description:` to the line
# that closes the quote.
desc_chars() {
  awk '/^description:/{f=1} f{print} f && /"[[:space:]]*$/ && !/^description:[[:space:]]*"$/{exit}' "$1" | wc -c | tr -d ' '
}

total=0
worst=""; worst_n=0
for s in "$REPO_ROOT"/skills/*/SKILL.md; do
  n=$(desc_chars "$s")
  total=$((total + n))
  if [ "$n" -gt "$worst_n" ]; then worst_n=$n; worst=$(basename "$(dirname "$s")"); fi
done

if [ "$total" -le "$BUDGET" ]; then
  pass "combined skill descriptions fit the initial-list budget ($total / $BUDGET chars)"
else
  fail "combined skill descriptions fit the initial-list budget" \
       "$total / $BUDGET chars — over by $((total - BUDGET)); largest is $worst at $worst_n"
fi

# No single skill should dominate the shared budget.
CAP=700
over=""
for s in "$REPO_ROOT"/skills/*/SKILL.md; do
  n=$(desc_chars "$s")
  [ "$n" -gt "$CAP" ] && over="$over $(basename "$(dirname "$s")"):$n"
done
if [ -z "$over" ]; then
  pass "no single description exceeds $CAP chars"
else
  fail "no single description exceeds $CAP chars" "$over"
fi

# Trigger words must be present, since a shortened description still has to match.
# The docs advise front-loading them for exactly this reason.
missing=""
for s in "$REPO_ROOT"/skills/*/SKILL.md; do
  grep -q 'Trigger phrases:' "$s" || missing="$missing $(basename "$(dirname "$s")")"
done
[ -z "$missing" ] && pass "every skill description carries trigger phrases" \
                  || fail "every skill description carries trigger phrases" "$missing"

report
