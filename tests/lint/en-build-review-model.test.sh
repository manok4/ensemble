#!/usr/bin/env bash
# Drift guards for en-build branch-level review model (FR01 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build review model"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- post-build phase exists ---
if grep -qiE "Post-build phase" "$SKILL"; then
  pass "en-build has a post-build phase"
else
  fail "en-build must have a post-build phase"
fi

# --- post-build invokes en-simplify, then a CROSS-AGENT peer review ---
if grep -qF "/en-simplify" "$SKILL"; then
  pass "post-build invokes en-simplify"
else
  fail "post-build must invoke en-simplify"
fi

# Branch-level review must be the cross-agent peer (implementer != reviewer),
# NOT host-side personas. Require peer dispatch via the prompt helper + PEER_CMD.
if grep -qiE "cross-agent" "$SKILL" && grep -qF "ensemble-build-peer-prompt" "$SKILL" && grep -qF "PEER_CMD" "$SKILL"; then
  pass "post-build review dispatches the cross-agent peer (implementer != reviewer)"
else
  fail "post-build review must dispatch the cross-agent peer, not host personas"
fi

# host-side en-review is only the fallback when no peer is available
if grep -qiE "PEER_AVAILABLE=false.*en-review|en-review-host-fallback" "$SKILL"; then
  pass "host-side en-review is the no-peer fallback only"
else
  fail "host-side en-review should be the no-peer fallback only"
fi

# --- review-verdict trailer emitted with units_covered ---
if grep -qF "review-verdict:" "$SKILL" && grep -qF "units_covered" "$SKILL"; then
  pass "post-build emits review-verdict with units_covered"
else
  fail "post-build must emit review-verdict with units_covered"
fi

# --- end-of-build audit uses branch-coverage ---
if grep -qF -- "--branch-coverage" "$SKILL"; then
  pass "end-of-build audit uses --branch-coverage"
else
  fail "end-of-build audit must use --branch-coverage"
fi

# --- ordinary per-unit loop does NOT do per-unit simplify/peer ---
# 9d should be a single verification gate (not gate 1 / gate 2 simplifier sandwich)
if grep -qE "9e\. Conditional per-unit peer review \(destructive / gated units ONLY\)" "$SKILL"; then
  pass "per-unit peer review restricted to destructive/gated units"
else
  fail "per-unit peer review must be restricted to destructive/gated units"
fi

# --- destructive/gated still require a dedicated per-unit peer pass ---
if grep -qiE "destructive.*MUST get a dedicated per-unit|dedicated per-unit Outside Voice peer pass" "$SKILL"; then
  pass "destructive/gated units keep a mandatory per-unit peer pass"
else
  fail "destructive/gated units must keep a mandatory per-unit peer pass"
fi

# --- foundation records D35 (supersedes D29) ---
if grep -qE "^- \*\*D35\." "$FOUNDATION" && grep -qiE "D29\..*SUPERSEDED|SUPERSEDED by D35" "$FOUNDATION"; then
  pass "foundation records D35 and marks D29 superseded"
else
  fail "foundation must record D35 and mark D29 superseded"
fi

# --- --no-peer skips the branch-level review ---
if grep -qE "\`--no-peer\`.*post-build branch-level" "$SKILL"; then
  pass "--no-peer documented for post-build branch-level review"
else
  fail "--no-peer must be documented for the post-build review"
fi
