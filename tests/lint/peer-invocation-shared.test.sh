#!/usr/bin/env bash
# Every skill that invokes a peer must go through bin/ensemble-peer-invoke, so the
# timeout wrapper, failure classification and peer_decision emission have ONE
# implementation rather than one per skill (D41: executable contract, not prose).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Repointed from en-build: D52 left it dispatching no peer and delegating
# simplification to /en-simplify, so it carries none of this machinery. The
# path now names the skill that owns it.
TEST_NAME="shared peer invocation"

# --- 1. every peer-invoking skill routes through the helper ---
missing=""
# en-cross-review dropped 2026-09-01: merged into /en-review as its --peer mode.
for skill in en-plan en-foundation en-review; do
  f="$REPO_ROOT/skills/$skill/SKILL.md"
  grep -qF "ensemble-peer-invoke" "$f" || missing="$missing $skill"
done
if [ -z "$missing" ]; then
  pass "en-plan, en-foundation and en-review all route through ensemble-peer-invoke"
else
  fail "these skills bypass ensemble-peer-invoke:$missing"
fi

# --- 2. NEGATIVE CONTROL: no skill hand-rolls the raw peer invocation any more ---
raw=""
for f in "$REPO_ROOT"/skills/*/SKILL.md; do
  # a bare "$PEER_CMD $PEER_FORMAT $PEER_TURNS" invocation is the hand-rolled form
  if grep -qE '\$PEER_CMD \$PEER_FORMAT \$PEER_TURNS' "$f"; then
    raw="$raw $(basename "$(dirname "$f")")"
  fi
done
if [ -z "$raw" ]; then
  pass "no skill hand-rolls a raw \$PEER_CMD invocation"
else
  fail "hand-rolled peer invocation found in:$raw" "route it through bin/ensemble-peer-invoke"
fi

# --- 3. the helper still owns what the skills stopped restating ---
INVOKE="$REPO_ROOT/skills/en-review/scripts/ensemble-peer-invoke"
if grep -qF "peer-failed:timeout" "$INVOKE" \
   && grep -qF "peer-failed:auth" "$INVOKE" \
   && grep -qF "_epi_timeout_bin" "$INVOKE"; then
  pass "helper owns timeout, auth and unknown classification"
else
  fail "skills/en-review/scripts/ensemble-peer-invoke must own the timeout wrapper and failure classification"
fi

report
