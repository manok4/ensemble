#!/usr/bin/env bash
# Drift guards for the /en-loop skill (EN06 U1).
# en-loop wraps the gnhf CLI: two modes + Morning Review, a per-iteration
# test-gate worker contract, branch-level checkpoint review, evidence-based
# stop conditions, and safety (never native-fallback, never auto-merge).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-loop skill"

SKILL="$REPO_ROOT/skills/en-loop/SKILL.md"
ANCHOR="$REPO_ROOT/tests/lint/skill-helper-anchor.test.sh"

# --- the skill file exists ---
if [ -f "$SKILL" ]; then
  pass "skills/en-loop/SKILL.md exists"
else
  fail "skills/en-loop/SKILL.md missing"
  report
fi

# --- frontmatter: name + manual-invoke only ---
if grep -qE "^name: en-loop" "$SKILL"; then
  pass "frontmatter names the skill en-loop"
else
  fail "frontmatter must set name: en-loop"
fi
if grep -qE "^disable-model-invocation: true" "$SKILL"; then
  pass "en-loop is manual-invoke only (disable-model-invocation: true)"
else
  fail "en-loop must be manual-invoke only (launches an unattended process)"
fi

# --- helper-resolution preamble present (required by skill-helper-anchor guard) ---
if grep -qF '**Helper resolution.**' "$SKILL"; then
  pass "has the Helper-resolution preamble"
else
  fail "must carry the Helper-resolution preamble (\$ENSEMBLE_ROOT anchoring)"
fi

# --- Happy path: both modes + Morning Review documented ---
modes_ok=1
grep -qiE "### Hands-Off" "$SKILL" || modes_ok=0
grep -qiE "### Companion" "$SKILL" || modes_ok=0
grep -qiE "Morning Review" "$SKILL" || modes_ok=0
if [ "$modes_ok" -eq 1 ]; then
  pass "documents both modes (Hands-Off, Companion) + Morning Review"
else
  fail "must document Hands-Off, Companion, and Morning Review"
fi

# --- Happy path: wraps gnhf via a gnhf launch invocation ---
if grep -qE "gnhf \\\\?$|gnhf --help|gnhf --agent|^gnhf " "$SKILL" && grep -qiE "wrap" "$SKILL"; then
  pass "wraps gnhf with a gnhf launch invocation"
else
  fail "must wrap gnhf and show a gnhf launch invocation"
fi

# --- Edge - gnhf absent: prints npm i -g gnhf and stops; NO native fallback ---
if grep -qF "npm i -g gnhf" "$SKILL"; then
  pass "gnhf-absent preflight prints 'npm i -g gnhf'"
else
  fail "must print 'npm i -g gnhf' when gnhf is absent"
fi
if grep -qiE "do NOT reimplement|not reimplement|no native fallback|do NOT fall back|not fall back" "$SKILL"; then
  pass "explicitly refuses a native / in-session fallback loop"
else
  fail "must refuse to native-fallback when gnhf is absent (wrap-only)"
fi

# --- Edge - checkpoint cadence: per-iteration test-gate + /en-review every --review-every N + at loop end ---
if grep -qiE "test-gate" "$SKILL" && grep -qiE "commit ONLY on green|commit only on green" "$SKILL"; then
  pass "documents the per-iteration test-gate worker contract (commit only on green)"
else
  fail "must document the per-iteration test-gate (commit only on green)"
fi
if grep -qF "/en-review --peer-only --mode headless" "$SKILL" && grep -qF -- "--review-every" "$SKILL"; then
  pass "checkpoint review invokes /en-review --peer-only every --review-every N"
else
  fail "must invoke /en-review --peer-only at checkpoints with --review-every"
fi
if grep -qiE "at loop end" "$SKILL" && grep -qiE "acceptance criteria" "$SKILL"; then
  pass "reviews at loop end; findings become next-iteration acceptance criteria"
else
  fail "must review at loop end and feed findings back as acceptance criteria"
fi

# --- Error path: evidence-based stop condition required; 'looks good' rejected ---
if grep -qiE "evidence-based" "$SKILL" && grep -qiE "looks good" "$SKILL" && grep -qiE "reject" "$SKILL"; then
  pass "requires an evidence-based --stop-when; rejects 'looks good'"
else
  fail "must require an evidence-based --stop-when and reject vague conditions"
fi

# --- Integration - safety: preserve changes, no destructive git, never auto-merge ---
safety_ok=1
grep -qiE "[Ss]afety" "$SKILL" || safety_ok=0
grep -qiE "[Pp]reserve user changes" "$SKILL" || safety_ok=0
grep -qiE "no destructive git|never run destructive git" "$SKILL" || safety_ok=0
grep -qiE "never auto-merge|not auto-merge" "$SKILL" || safety_ok=0
grep -qiE "en-guardrail" "$SKILL" || safety_ok=0
if [ "$safety_ok" -eq 1 ]; then
  pass "safety: preserve changes, no destructive git, never auto-merge, guardrail applies"
else
  fail "must document the full safety list (preserve / no-destructive-git / never-auto-merge / guardrail)"
fi

# --- Integration - host-neutral worker-agent selection (not hardcoded) ---
if grep -qiE "host-neutral" "$SKILL" && grep -qF "host-detect.md" "$SKILL" && grep -qiE "never hardcode" "$SKILL"; then
  pass "worker-agent selection is host-neutral (claude/codex via host-detect)"
else
  fail "must select the worker agent host-neutrally via host-detect (never hardcoded)"
fi

# --- Core rule: host orchestrates, gnhf executes; completion is not acceptance ---
if grep -qiE "host orchestrates" "$SKILL" && grep -qiE "gnhf executes" "$SKILL" && grep -qiE "not acceptance|completion is not|completion ≠ acceptance" "$SKILL"; then
  pass "states the core rule (host orchestrates; gnhf executes; completion != acceptance)"
else
  fail "must state the core rule: host orchestrates, gnhf executes, completion != acceptance"
fi

# --- Positioning: when-to-use vs en-flow, /loop, en-build ---
if grep -qF "vs \`/en-flow\`" "$SKILL" && grep -qF "vs the built-in \`/loop\`" "$SKILL" && grep -qF "vs \`/en-build\`" "$SKILL"; then
  pass "documents positioning vs en-flow, /loop, en-build"
else
  fail "must document positioning vs en-flow, /loop, and en-build"
fi

# --- The skill-helper-anchor drift guard now covers en-loop ---
if grep -qE 'TARGET_SKILLS=.*en-loop' "$ANCHOR"; then
  pass "skill-helper-anchor guard includes en-loop in TARGET_SKILLS"
else
  fail "skill-helper-anchor.test.sh must add en-loop to TARGET_SKILLS"
fi

report
