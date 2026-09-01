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
VERIFY="$REPO_ROOT/skills/en-build/scripts/ensemble-verify-peer-evidence"

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

# --- D52: there is no per-unit peer pass at all ---
# D35 gave ordinary units a branch-level review and kept a per-unit pass for
# destructive/gated ones; D52 removes that exception. Peer involvement is
# exactly once per build, at step 10.3, after /en-simplify. Guarded as an
# ABSENCE because the failure mode is reintroduction: a per-unit pass would
# put the peer back in the inner loop without anything noticing.
# Keyed on CONTENT, not the letter. The loop was renumbered when 9e's removal
# left a gap, and a letter-keyed check would have gone red on the renumber while
# staying green if a per-unit peer came back under a different letter.
if grep -qiE "^     - \*\*9[a-z]\..*per-unit peer|^     - \*\*9[a-z]\..*Outside Voice" "$SKILL"; then
  fail "no step in the unit loop may run a peer pass" \
       "D52 moved peer review to 10.3; the branch-level review covers every unit"
else
  pass "no step in the unit loop runs a peer pass"
fi

if grep -qiE "dedicated per-unit (Outside Voice )?peer pass" "$SKILL"; then
  fail "no unit class may claim a dedicated per-unit peer pass" \
       "destructive and gated units are covered by the branch-level review like every other unit"
else
  pass "no unit class claims a dedicated per-unit peer pass"
fi

# --- the user-facing safety gates are NOT peer review and must survive ---
# This is the pair that makes the removal safe to read: peer review left the
# inner loop, the typed confirmations did not.
if grep -qF 'run unit U<N>' "$SKILL" && grep -qiE 'y/skip/abort' "$SKILL" \
   && grep -qiE 'No flag disables' "$SKILL"; then
  pass "destructive and gated units keep their typed and y/skip/abort confirmations"
else
  fail "the universal safety gates must survive the per-unit peer removal" \
       "those are user confirmations, not peer review, and D52 does not touch them"
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
# Checked in the BODY, not the description. Decision labels are maintainer
# provenance with no triggering value, and every character of a description
# competes with all 16 other skills for Codex's 8,000-char initial-list budget
# (see TD2). The body is read in full once the skill is selected.
if grep -qF "D52" "$SKILL"; then
  pass "en-build cites the decision currently in force"
else
  fail "en-build must cite D52 (a stale decision label misleads maintainers)"
fi

# --- D52 is recorded, and says what it costs ---
# A decision that removes a safety pass without naming the trade is one nobody
# can re-litigate later on the evidence.
if grep -qE "^- \*\*D52\." "$FOUNDATION" \
   && grep -qiE "D52.*(supersedes D35|amends D46)" "$FOUNDATION" \
   && grep -qiE "What this costs" "$FOUNDATION"; then
  pass "foundation records D52, its supersession, and its cost"
else
  fail "foundation must record D52 with what it supersedes and what it costs"
fi

# --- --no-peer skips the branch-level review ---
if grep -qE "\`--no-peer\`.*post-build branch-level" "$SKILL"; then
  pass "--no-peer documented for post-build branch-level review"
else
  fail "--no-peer must be documented for the post-build review"
fi

# --- D52 residue sweep across every file en-build carries ---
# The clauses above check SKILL.md's flow. This catches the same claim surviving
# somewhere the flow does not read: the flag table said "--no-peer ... Destructive/
# gated units still get their mandatory per-unit peer pass", CONTRACT.md promised
# the pass to callers, peer-brief.md told the peer it was "the only review they
# get", and recursion-guard.md said en-build proceeds without a per-unit pass it
# no longer has. Four files, none of them the flow, all read by somebody.
residue=""
for pat in "mandatory per-unit peer" "dedicated per-unit peer" "max-per-unit-iterations" \
           "still get their" "per-unit peer pass is the"; do
  hits=$(grep -rilF "$pat" "$REPO_ROOT/skills/en-build" 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')
  [ -n "$hits" ] && residue="$residue [$pat: $hits]"
done
[ -z "$residue" ] \
  && pass "no file en-build carries still promises a per-unit peer pass" \
  || fail "no file en-build carries still promises a per-unit peer pass" "$residue"

report
