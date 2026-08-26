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
EN_LOOP="$REPO_ROOT/skills/en-loop/SKILL.md"
VERIFY="$REPO_ROOT/shared/bin/ensemble-verify-peer-evidence"

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
# ...and /en-loop must ACTUALLY still use it. Asserting only that the string
# survives somewhere in en-review would pass even if en-loop silently flipped to
# --peer, which is precisely the scope D46 excludes (checkpoints fire every N
# iterations in an unattended loop, where a persona roster per checkpoint
# multiplies cost). Assert the real invocation, not the flag's existence.
if grep -qF -- "/en-review --peer-only --mode headless" "$EN_LOOP"; then
  pass "/en-loop checkpoint still invokes /en-review --peer-only (D46 scope)"
else
  fail "/en-loop must keep --peer-only at checkpoints" "D46 scopes the --peer change to /en-build only"
fi
if grep -qF -- "/en-review --peer " "$EN_LOOP"; then
  fail "/en-loop switched to --peer" "D46 deliberately excludes /en-loop; cost compounds in an unattended loop"
else
  pass "/en-loop has not adopted --peer"
fi

# The claim that reviewer semantics and the step 10.5 audit gate are UNCHANGED
# needs a guard of its own, otherwise a future change could redefine them while
# the prose assertions above still pass.
for rv in "cross-agent" "single-agent-fallback" "en-review-host-fallback"; do
  if grep -qF -- "$rv" "$SKILL"; then
    pass "reviewer value still documented in en-build: $rv"
  else
    fail "en-build dropped a reviewer value: $rv"
  fi
done
if grep -qF -- "single-agent-fallback" "$VERIFY" && grep -qF -- "cross-agent" "$VERIFY"; then
  pass "audit gate still recognizes the cross-agent / fallback reviewer values"
else
  fail "audit gate no longer recognizes the documented reviewer values"
fi
if grep -qF -- "--require-simplify" "$SKILL" && grep -qiE "branch_review_pass.*(missing|failed)|missing.*branch_review_pass" "$SKILL"; then
  pass "step 10.5 still fails the build on a missing/failed branch review"
else
  fail "step 10.5 must still fail on a missing or failed branch review under --require-simplify"
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

# --- D46 amends D35, and the skill points at the amendment ---
if grep -qE "^- \*\*D46\." "$FOUNDATION" && grep -qiE "amends D35" "$FOUNDATION"; then
  pass "foundation records D46 amending D35"
else
  fail "foundation must record D46 as amending D35"
fi
if grep -qF "D35, amended by D46" "$SKILL"; then
  pass "en-build description cites the amending decision, not just D35"
else
  fail "en-build description must cite D46 alongside D35 (stale decision label misleads maintainers)"
fi

# --- --no-peer skips the branch-level review ---
if grep -qE "\`--no-peer\`.*post-build branch-level" "$SKILL"; then
  pass "--no-peer documented for post-build branch-level review"
else
  fail "--no-peer must be documented for the post-build review"
fi
