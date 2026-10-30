#!/usr/bin/env bash
# tests/lint/peer-resolution-evidence.test.sh
#
# EN24 U8. A host could mark a peer finding `disagreed` on the strength of
# something the peer never saw: a verbal decision, a team convention. The
# finding then vanished from the next pass's "do not re-flag" list with no one
# but the host having judged it. Now a `disagreed` rationale must cite something
# the peer could read, and evidence outside that makes the entry `escalated`,
# which reaches the user through a question the run already asks. It never adds
# a stop and never blocks promotion or the build.
#
# Lint checks the enum and that a rationale is present, not whether it cites
# evidence: judging prose with a regex would be a guard that fails for the
# wrong reasons. What is asserted here is that every enum site knows the new
# status and that the routing text says where an escalation goes.
#
# NEGATIVE CONTROLS (run by hand 2026-10-29, each turned the test red):
#   - removed rule 2 (`escalated`) from one peer-contract.md copy
#   - removed "or escalated" from en-review's prompt builder only (two asserts
#     go red: its own phrase, and its identity with en-test-audit's copy)
#   - deleted the "never adds a stop" sentence from finalize-loop.md

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="rejecting a peer finding needs evidence"
cd "$REPO_ROOT"

# --- the contract: eight carriers, the enum and the four rules ---
for c in skills/*/references/peer-contract.md; do
  grep -qF '`applied` · `deferred` · `disagreed` · `superseded` · `escalated`' "$c" \
    && pass "$c: the status enum includes escalated" \
    || fail "$c: the status enum includes escalated"
done
C=skills/en-plan/references/peer-contract.md
grep -qE '^1\. A `disagreed` rationale cites something the peer could read' "$C" \
  && pass "rule 1: disagreed cites readable evidence" || fail "rule 1: disagreed cites readable evidence"
grep -qE '^2\. .*the status is `escalated`' "$C" \
  && pass "rule 2: evidence the peer cannot read makes it escalated" || fail "rule 2: evidence the peer cannot read makes it escalated"
grep -qE '^3\. .*never lowers the severity silently' "$C" \
  && pass "rule 3: no silent severity downgrade" || fail "rule 3: no silent severity downgrade"
grep -qE '^4\. Context is not added to an artifact only to satisfy a reviewer' "$C" \
  && pass "rule 4: no context added only for the reviewer" || fail "rule 4: no context added only for the reviewer"

# --- every other enum site ---
for t in skills/en-plan/references/templates/plan-template.md skills/en-foundation/references/templates/plan-template.md; do
  grep -qF 'status: applied | deferred | disagreed | superseded | escalated' "$t" \
    && pass "$t: the resolution schema lists escalated" || fail "$t: the resolution schema lists escalated"
done
for l in bin/ensemble-lint skills/en-setup/references/templates/ensemble-lint; do
  grep -qF 'Use one of: applied, deferred, disagreed, superseded, escalated' "$l" \
    && pass "$l: the lint enum includes escalated" || fail "$l: the lint enum includes escalated"
done
for b in skills/*/scripts/ensemble-build-peer-prompt; do
  grep -qF 'marks applied, deferred, disagreed or escalated' "$b" \
    && pass "$b: the peer is told not to re-flag an escalation" \
    || fail "$b: the peer is told not to re-flag an escalation"
done
# script-parity lists the builder as a per-artifact variant, so nothing else
# holds the two code-review copies together.
cmp -s skills/en-review/scripts/ensemble-build-peer-prompt skills/en-test-audit/scripts/ensemble-build-peer-prompt \
  && pass "en-review and en-test-audit build the same code-review prompt" \
  || fail "en-review and en-test-audit build the same code-review prompt" "the two code-review builders have diverged"
grep -qF '`applied | deferred | disagreed | superseded | escalated`' skills/en-build/references/build-preflight.md \
  && pass "en-build pre-flight counts escalated as resolved" || fail "en-build pre-flight counts escalated as resolved"
grep -qF 'lists open escalations' skills/en-build/references/build-preflight.md \
  && pass "en-build pre-flight lists escalations without prompting" || fail "en-build pre-flight lists escalations without prompting"

# --- en-plan's routing: three paths, none adding a stop ---
F=skills/en-plan/references/finalize-loop.md
grep -qF 'An escalation never adds a stop' "$F" \
  && pass "finalize-loop: an escalation never adds a stop" || fail "finalize-loop: an escalation never adds a stop"
grep -qF 'listed in that question' "$F" \
  && pass "finalize-loop: path 1 joins a question already asked" || fail "finalize-loop: path 1 joins a question already asked"
grep -qF 'stays `escalated` and does not block' "$F" \
  && pass "finalize-loop: path 2 stays escalated and does not block" || fail "finalize-loop: path 2 stays escalated and does not block"
grep -qF 'non-interactive run' "$F" \
  && pass "finalize-loop: path 3 covers non-interactive runs" || fail "finalize-loop: path 3 covers non-interactive runs"
grep -qF '| Disagree without evidence the peer could read |' skills/en-plan/references/peer-brief.md \
  && pass "en-plan's routing table routes an unevidenced disagreement" || fail "en-plan's routing table routes an unevidenced disagreement"
for s in skills/en-review/references/mutation-protocol.md skills/en-foundation/SKILL.md; do
  grep -qF '`escalated`' "$s" && grep -qF 'references/peer-contract.md' "$s" \
    && pass "$s: points escalations at the contract" || fail "$s: points escalations at the contract"
done

# --- lint accepts escalated with a rationale and refuses it without one ---
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/docs/plans/active"
mk() {  # <rationale line or empty>
  cat > "$TMP/docs/plans/active/EN90-improvement_esc.md" <<EOF
---
type: plan
plan_type: improvement
plan_id: EN90
title: Escalation fixture
status: open
location: active
created: 2026-10-29
covers_requirements: []
requirements_pending: false
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: Convention not followed
    status: escalated
$1
---

# EN90
EOF
}
mk '    rationale: team convention on X, user to confirm'
out=$(cd "$TMP" && "$REPO_ROOT/bin/ensemble-lint" --scope docs/plans/active 2>&1)
assert_not_contains "$out" "peer-review-resolutions.schema" "lint accepts escalated with a rationale"
mk ''
out=$(cd "$TMP" && "$REPO_ROOT/bin/ensemble-lint" --scope docs/plans/active 2>&1)
assert_contains "$out" "has status 'escalated' but no rationale" "lint refuses escalated without a rationale"

report
