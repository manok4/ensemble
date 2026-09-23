#!/usr/bin/env bash
# tests/lint/en-plan-linear-intake.test.sh
#
# EN19 U5 and U6: /en-plan takes a Linear identifier, either as the request
# (plan from a triaged issue, publish onto it) or with --resume (amend a
# published plan in place). Both are model-followed MCP flows, so this file can
# only guard the prose; the transforms they lean on are tested for real in
# tests/linear-plan/.
#
# The clauses that matter most are the re-checks immediately before a write.
# Both flows read Linear, spend a whole review cycle, then write back: without
# a fresh read in between, an edit or a started build in that window is
# silently overwritten.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan linear intake"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"
INTAKE="$REPO_ROOT/skills/en-plan/references/linear-intake.md"
PUB="$REPO_ROOT/skills/en-plan/references/linear-publish.md"

has()   { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }
section() { awk -v h="$2" 'index($0, h) == 1 {f=1; next} f && /^## /{exit} f' "$1"; }

assert_file_exists "$INTAKE" "the intake reference exists"

# --- 1. routing ----------------------------------------------------------------
source_step=$(awk '/^4\. \*\*Source the request/{f=1} f&&/^5\. \*\*/{exit} f' "$SKILL")
assert_contains "$source_step" 'references/linear-intake.md' \
  "en-plan's source-the-request step routes an identifier to the intake reference"
has "$INTAKE" 'mode comes from `plan_store`, never from the argument.s shape' \
  "the mode comes from plan_store, as it does in /en-build"
has "$INTAKE" 'Under `local` an identifier refuses' "an identifier under plan_store: local refuses"
has "$INTAKE" 'plan_store --allowed local,linear' "plan_store is read through the fail-closed config reader"

# --- 2. plan from an issue (U5) -------------------------------------------------
ISSUE=$(section "$INTAKE" '## An issue as the request')
[ -n "$ISSUE" ] && pass "the issue-as-request section exists" || fail "the issue-as-request section exists"
for clause in 'team is not `linear_team`' 'already has sub-issues' 'started, completed or canceled'; do
  assert_contains "$ISSUE" "$clause" "admission refuses when: $clause"
done
assert_contains "$ISSUE" 'every line prefixed' "the original request is quoted as a blockquote"
assert_contains "$ISSUE" '## Implementation units' "and the prose says why: the report's own headings cannot open a section"
assert_contains "$ISSUE" 'linear_issue: <IDENT>' "the plan carries linear_issue from the start"
assert_contains "$ISSUE" 'Re-check immediately before publish' "the issue is re-fetched immediately before publish"
assert_contains "$ISSUE" 'now has sub-issues' "the re-check refuses when sub-issues appeared during review"
assert_contains "$ISSUE" 'writing nothing' "and refuses before any write"
assert_contains "$ISSUE" 'instead of creating a parent' "publish updates the issue in place, no second parent"
re_check=$(printf '%s\n' "$ISSUE" | grep -n 'Re-check immediately' | head -1 | cut -d: -f1)
publish=$(printf '%s\n' "$ISSUE" | grep -n 'Publish onto the issue' | head -1 | cut -d: -f1)
if [ -n "$re_check" ] && [ -n "$publish" ] && [ "$re_check" -lt "$publish" ]; then
  pass "the re-check comes before the publish"
else
  fail "the re-check comes before the publish" "re-check=${re_check:-none} publish=${publish:-none}"
fi
has "$PUB" 'authored from an issue' "the idempotency protocol names the issue-as-parent case"

report
