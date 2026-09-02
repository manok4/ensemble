#!/usr/bin/env bash
# Drift guards for the /en-build agent autonomy contract.
# The contract lives in skills/en-build/SKILL.md ("Agent autonomy contract").
# Shipped via PR #20 + #21; the design spec has been retired.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# The en-qa pre-flow exclusion was named "Playwright bootstrap" until 2026-09-02.
# en-qa stopped being Playwright-locked (it now selects a driver), so the exclusion
# is driver-neutral. The rule is unchanged: a bootstrap offer is pre-flow.
TEST_NAME="en-build autonomy contract"

EN_BUILD="$REPO_ROOT/skills/en-build/SKILL.md"
EN_QA="$REPO_ROOT/skills/en-qa/SKILL.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- en-build has Agent autonomy contract section ---
if grep -qF "Agent autonomy contract" "$EN_BUILD"; then
  pass "en-build has Agent autonomy contract section"
else
  fail "en-build missing Agent autonomy contract section"
fi

# --- en-qa has the mirror ---
if grep -qF "Agent autonomy contract" "$EN_QA"; then
  pass "en-qa has Agent autonomy contract (mirror)"
else
  fail "en-qa missing Agent autonomy contract (mirror)"
fi

# --- Scope-of-the-contract subsection (load-bearing per PR #21 review) ---
if grep -qF "Scope of the contract" "$EN_BUILD"; then
  pass "en-build documents 'Scope of the contract'"
else
  fail "en-build should have 'Scope of the contract' subsection"
fi
if grep -qF "Scope of the contract" "$EN_QA"; then
  pass "en-qa documents 'Scope of the contract'"
else
  fail "en-qa should have 'Scope of the contract' subsection"
fi

# --- en-build scope names "inter-unit main loop" + "Steps 1-8 NOT governed" ---
if grep -qiE "inter-unit main loop" "$EN_BUILD"; then
  pass "en-build scope names 'inter-unit main loop'"
else
  fail "en-build scope should name 'inter-unit main loop' as the window"
fi
if grep -qiE "Steps 1.8 are NOT governed|Steps 1.{1,3}8 are NOT governed" "$EN_BUILD"; then
  pass "en-build scope explicitly names Steps 1-8 as out of scope"
else
  fail "en-build scope should state 'Steps 1-8 are NOT governed by this contract'"
fi

# --- en-qa scope names "already-runnable QA flows" + pre-flow exclusions ---
if grep -qF "already-runnable QA flows" "$EN_QA"; then
  pass "en-qa scope names 'already-runnable QA flows'"
else
  fail "en-qa scope should name 'already-runnable QA flows' as the window"
fi
for pre_flow in "URL discovery" "--system-only" "Test-framework bootstrap"; do
  if grep -qF -- "$pre_flow" "$EN_QA"; then
    pass "en-qa scope documents pre-flow exclusion: $pre_flow"
  else
    fail "en-qa scope missing pre-flow exclusion: $pre_flow"
  fi
done

# --- "exhaustive within scope" phrasing (catches bare "exhaustive" drift) ---
for skill_file in "$EN_BUILD" "$EN_QA"; do
  skill_name=$(basename "$(dirname "$skill_file")")
  if grep -qF "exhaustive within scope" "$skill_file"; then
    pass "$skill_name uses 'exhaustive within scope' phrasing"
  else
    fail "$skill_name should use 'exhaustive within scope' (catches PR #21 review class)"
  fi
done

# --- All seven en-build pause cases enumerated ---
for case_phrase in "Working tree dirty at branch setup" "Plan-review concerns surfaced at start" "risk: destructive.* unit at step 9a" "gated: true.* unit at step 9a" "P4 phase-level confirmation" '`build.pause_between_phases` set' "Failure protocol fires"; do
  if grep -qE "$case_phrase" "$EN_BUILD"; then
    pass "en-build enumerates pause case: $(echo "$case_phrase" | head -c 50)..."
  else
    fail "en-build missing pause case: $(echo "$case_phrase" | head -c 50)..."
  fi
done

# --- All five en-qa pause cases enumerated ---
for case_phrase in "System check fails.* at Phase 1" "Playwright MCP unavailable mid-flow" "Bug found that requires user judgment" "Bug fix breaks Phase 1 checks" "User-initiated abort"; do
  if grep -qE "$case_phrase" "$EN_QA"; then
    pass "en-qa enumerates pause case: $(echo "$case_phrase" | head -c 50)..."
  else
    fail "en-qa missing pause case: $(echo "$case_phrase" | head -c 50)..."
  fi
done

# --- Anti-patterns documented in en-build ---
for anti in "checkpoint before bigger unit" "Working tree is clean, paused" "Should I continue" "Let me verify with the user"; do
  if grep -qF "$anti" "$EN_BUILD"; then
    pass "en-build documents anti-pattern: $(echo "$anti" | head -c 50)..."
  else
    fail "en-build missing anti-pattern: $(echo "$anti" | head -c 50)..."
  fi
done

# --- Forbidden phrases flagged ---
if grep -qF "should I continue" "$EN_BUILD" || grep -qiF "should i continue" "$EN_BUILD" || grep -qF "Should I continue" "$EN_BUILD"; then
  pass "en-build flags 'should I continue' as forbidden"
else
  fail "en-build anti-patterns should mention 'should I continue?'"
fi
if grep -qiF "let me verify" "$EN_BUILD"; then
  pass "en-build flags 'let me verify' as forbidden"
else
  fail "en-build anti-patterns should mention 'let me verify'"
fi

# --- "Right response to LLM uncertainty: advance, not ask" framing ---
if grep -qF "advance, not ask" "$EN_BUILD"; then
  pass "en-build has 'advance, not ask' framing"
else
  fail "en-build should include 'advance, not ask' framing"
fi
if grep -qF "advance, not ask" "$EN_QA"; then
  pass "en-qa has 'advance, not ask' framing"
else
  fail "en-qa should include 'advance, not ask' framing"
fi

# --- "Never inserts agent-initiated checkpoints" in en-build's never-does section ---
if grep -qF "Never inserts agent-initiated checkpoints" "$EN_BUILD"; then
  pass "en-build 'What this skill never does' includes the new prohibition"
else
  fail "en-build 'What this skill never does' should include 'Never inserts agent-initiated checkpoints'"
fi

# --- Note: line format mentioned as the alternative to gating prompts ---
if grep -qF "Note:" "$EN_BUILD" && grep -qF "informational" "$EN_BUILD"; then
  pass "en-build documents Note: line as informational alternative"
else
  fail "en-build should document 'Note:' line as the informational outlet"
fi

# --- Foundation §D33 added ---
if grep -E "^- \*\*D33\." "$FOUNDATION" >/dev/null; then
  pass "foundation §D33 exists (autonomy contract decision entry)"
else
  fail "foundation should have a D33 entry for the autonomy contract"
fi
d33_line=$(grep -E "^- \*\*D33\." "$FOUNDATION")
if echo "$d33_line" | grep -qF "Autonomous execution"; then
  pass "foundation §D33 references autonomous execution contract"
else
  fail "foundation §D33 should mention autonomous execution"
fi
if echo "$d33_line" | grep -qiF "agent-initiated"; then
  pass "foundation §D33 mentions agent-initiated pauses as forbidden"
else
  fail "foundation §D33 should mention agent-initiated pauses as forbidden"
fi

report
