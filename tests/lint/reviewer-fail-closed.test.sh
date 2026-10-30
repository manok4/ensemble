#!/usr/bin/env bash
# tests/lint/reviewer-fail-closed.test.sh
#
# EN24 U2. A review persona that could not open the diff file or a reference
# its prompt named used to return an empty findings array, which synthesis
# reads as "looked, found nothing": a clean pass from a reviewer that never
# saw the code. The persona now reports `"status": "incomplete"` with the
# paths it could not read, and en-review drops it by name, without a retry
# (a retry cannot make a missing file readable).
#
# The rule lives in three places the model reads, and each is asserted here:
# the shared finding schema (five byte-identical carriers), the reviewer's own
# return section, and en-review's synthesis and failure protocol.
#
# NEGATIVE CONTROLS (run by hand 2026-10-29, each turned the test red):
#   - deleted the `incomplete` row from persona-dispatch.md's failure protocol
#   - edited one finding-schema.md copy only
#   - restored the unscoped "Return an empty findings array when you find
#     nothing." in dimension-reviewer.md

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="a reviewer that cannot read its inputs fails closed"
cd "$REPO_ROOT"

# --- the schema: five carriers, identical, each documenting both fields ---
n=$(ls skills/*/references/finding-schema.md | wc -l | tr -d ' ')
assert_eq 5 "$n" "finding-schema.md has five carriers"
sums=$(for f in skills/*/references/finding-schema.md; do cksum < "$f"; done | sort -u | wc -l | tr -d ' ')
assert_eq 1 "$sums" "every finding-schema.md copy is byte-identical"
S=skills/en-review/references/finding-schema.md
grep -q '^| `status` | optional |' "$S" && grep -q 'absent means `complete`' "$S" \
  && pass "schema documents status, absent meaning complete" \
  || fail "schema documents status, absent meaning complete"
grep -q '^| `unreadable` |' "$S" && pass "schema documents unreadable" || fail "schema documents unreadable"
grep -q '"status": "complete | incomplete"' "$S" && pass "schema example carries status" || fail "schema example carries status"
grep -q 'never with `verdict: approve`' "$S" && pass "schema forbids approve on an incomplete response" \
  || fail "schema forbids approve on an incomplete response"

# --- the reviewer: reports unreadable inputs; empty findings only after reading ---
R=skills/en-review/agents/dimension-reviewer.md
grep -q '"status": "incomplete"' "$R" && grep -q '"unreadable"' "$R" \
  && pass "dimension-reviewer returns incomplete with the unreadable paths" \
  || fail "dimension-reviewer returns incomplete with the unreadable paths"
grep -q 'Return an empty findings array when you read your inputs and find nothing' "$R" \
  && pass "the empty-findings rule is scoped to a review that read its inputs" \
  || fail "the empty-findings rule is scoped to a review that read its inputs"
grep -q 'Return an empty findings array when you find nothing' "$R" \
  && fail "the unscoped empty-findings sentence is gone" "an empty array from an unread diff reads as a clean pass" \
  || pass "the unscoped empty-findings sentence is gone"

# --- en-review: drops it by name, never retries ---
P=skills/en-review/references/persona-dispatch.md
row=$(grep '^| One persona returns `incomplete` |' "$P")
assert_contains "$row" "no retry" "failure protocol: incomplete persona is dropped with no retry"
assert_contains "$row" "unreadable" "failure protocol: the unreadable paths are named"
grep -q '^1\. \*\*Validate each response\*\*.*`"status": "incomplete"`' "$P" \
  && pass "synthesis step 1 treats incomplete as a failed persona" \
  || fail "synthesis step 1 treats incomplete as a failed persona"

report
