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

# --- 3. amend in place (U6) ------------------------------------------------------
resume_step=$(awk '/^3\. \*\*Resume or create/{f=1} f&&/^4\. \*\*/{exit} f' "$SKILL")
assert_contains "$resume_step" 'references/linear-intake.md' \
  "en-plan's resume step routes an identifier to the intake reference"
AMEND=$(section "$INTAKE" '## Amend in place')
[ -n "$AMEND" ] && pass "the amend section exists" || fail "the amend section exists"
assert_contains "$AMEND" 'unless it is Agent Ready or earlier' "only a parent at Agent Ready or earlier is amendable"
printf '%s' "$AMEND" | tr '\n' ' ' | grep -q 'In Progress, In Review and Done' \
  && pass "In Progress, In Review and Done refuse" || fail "In Progress, In Review and Done refuse"
assert_contains "$AMEND" 'tracked or not' "any existing local file for the plan_id refuses, tracked or not"
assert_contains "$AMEND" 'ensemble-linear-plan" materialize intake-readback.json' "the published plan is materialized through the script"
assert_contains "$AMEND" 'never renumbered or reused' "U-IDs are never renumbered or reused"
assert_contains "$AMEND" 'canceled ones included' "a new U-ID goes above every sub-issue's, canceled included"
assert_contains "$AMEND" 'Re-check immediately before updating Linear' "a fresh read-back is taken immediately before the update"
assert_contains "$AMEND" 'verify intake.md fresh-readback.json' "and compared with the intake copy through verify"
assert_contains "$AMEND" '**Cancel**' "removed units are canceled, not deleted"
amend_line() { printf '%s\n' "$AMEND" | grep -n -- "$1" | head -1 | cut -d: -f1; }
m=$(amend_line 'Materialize the published plan'); r=$(amend_line 'Revise and review'); c=$(amend_line 'Re-check immediately'); u=$(amend_line 'Update in place')
if [ -n "$m" ] && [ -n "$r" ] && [ -n "$c" ] && [ -n "$u" ] && [ "$m" -lt "$r" ] && [ "$r" -lt "$c" ] && [ "$c" -lt "$u" ]; then
  pass "the amend steps read materialize, review, re-check, update, in that order"
else
  fail "the amend steps read materialize, review, re-check, update, in that order" "m=${m:-} r=${r:-} c=${c:-} u=${u:-}"
fi
has "$PUB" 'cancels removed ones' "the idempotency protocol names the amend case"

report
