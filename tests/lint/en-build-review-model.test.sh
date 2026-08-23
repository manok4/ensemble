#!/usr/bin/env bash
# Drift guards for en-build branch-level review model (FR01 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build review model"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
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

# Branch-level review invokes /en-review with a MANDATORY cross-agent peer plus
# the host personas (D46, superseding the former --peer-only). The peer carries
# implementer != reviewer; the personas are fresh-context sub-agents that add the
# host-only standards/testing/maintainability findings --peer-only discarded.
if grep -qF -- "/en-review --peer " "$SKILL" && grep -qiE "cross-agent" "$SKILL"; then
  pass "post-build review calls /en-review --peer (cross-agent peer + host personas)"
else
  fail "post-build review must call /en-review --peer"
fi
# Guard the regression directly: the post-build step must NOT go back to peer-only.
if grep -qF -- "/en-review --peer-only --mode headless --base" "$SKILL"; then
  fail "post-build review reverted to --peer-only (drops host-only findings; see D46)"
else
  pass "post-build review does not use --peer-only"
fi
# The cross-agent property is still mandatory, not merely nice to have.
if grep -qiE 'peer is \*\*mandatory\*\*|cross-agent peer is \*\*mandatory\*\*' "$SKILL"; then
  pass "post-build review states the cross-agent peer is mandatory"
else
  fail "post-build review must state the cross-agent peer is mandatory"
fi

# --peer-only itself must SURVIVE in en-review: /en-loop still depends on it.
if grep -qF -- "--peer-only" "$EN_REVIEW"; then
  pass "en-review still documents --peer-only (used by /en-loop)"
else
  fail "en-review must keep --peer-only; /en-loop depends on it"
fi
if grep -qiE "skip persona detection and dispatch|sole reviewer.*peer|peer.*sole reviewer" "$EN_REVIEW"; then
  pass "en-review --peer-only still skips host personas (peer is sole reviewer)"
else
  fail "en-review --peer-only must skip host personas"
fi
# the peer machinery lives in en-review (build-peer-prompt referenced there)
if grep -qF "ensemble-build-peer-prompt" "$EN_REVIEW"; then
  pass "en-review owns the peer-dispatch machinery"
else
  fail "en-review must own the peer-dispatch machinery"
fi
# en-review-host-fallback recorded when no peer
if grep -qiE "en-review-host-fallback" "$EN_REVIEW"; then
  pass "en-review records host-fallback reviewer when no peer"
else
  fail "en-review must record host-fallback reviewer when no peer"
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
