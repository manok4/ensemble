#!/usr/bin/env bash
# Drift guards for the three new conditional reviewers (EN02 U4).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review new reviewers"

PERSONA="$REPO_ROOT/references/persona-dispatch.md"
EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
SIGNAL="$REPO_ROOT/references/diff-signal-detection.md"

# --- three reviewer agent files exist with the standard shape ---
for r in api-contract reliability frontend-races; do
  f="$REPO_ROOT/agents/$r-reviewer.md"
  if [ -f "$f" ] && grep -qE "^name: $r-reviewer" "$f" && grep -qF "finding-schema.md" "$f"; then
    pass "$r-reviewer agent exists with standard shape"
  else
    fail "$r-reviewer agent missing or wrong shape"
  fi
  # uses the anchor model + quote-the-line
  if grep -qF "first_evidence" "$f" && grep -qE "\{0,25,50,75,100\}" "$f"; then
    pass "$r-reviewer uses anchor model + first_evidence"
  else
    fail "$r-reviewer must use the anchor model + first_evidence"
  fi
done

# --- conditional roster expanded to 6 ---
if grep -qiE "Conditional \(6\)" "$PERSONA" && grep -qiE "Conditional \(6\)" "$EN_REVIEW"; then
  pass "conditional roster expanded to 6 in persona-dispatch + en-review"
else
  fail "conditional roster must be expanded to 6"
fi

# --- the three appear in the persona-dispatch roster ---
for r in api-contract-reviewer reliability-reviewer frontend-races-reviewer; do
  if grep -qF "$r" "$PERSONA"; then
    pass "$r in persona-dispatch roster"
  else
    fail "$r must be in persona-dispatch roster"
  fi
done

# --- dual expression: brief dimension (non-adversarial) vs host persona (adversarial) ---
if grep -qiE "dimension in the peer brief|peer-brief dimension" "$PERSONA"; then
  pass "conditionals documented as peer-brief dimensions vs host personas"
else
  fail "conditionals must be documented as dual-expression"
fi

# --- signal source notes the conditional reviewers ---
if grep -qiE "Conditional-reviewer signals" "$SIGNAL" && grep -qF "api-contract" "$SIGNAL"; then
  pass "diff-signal-detection notes the conditional-reviewer signals"
else
  fail "diff-signal-detection must note the conditional-reviewer signals"
fi
