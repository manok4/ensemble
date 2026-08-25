#!/usr/bin/env bash
# Guards against step-number drift in en-plan.
# A numeric "step N" reference silently rots when a step is inserted; that shipped as a real
# bug where the peer-reject-override path pointed at the peer-review loop instead of the flip.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan step references"

SKILL="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- 1. no numeric step cross-references anywhere ---
hits=$(grep -oE "step [0-9]+" "$SKILL" | wc -l | tr -d ' ')
if [ "$hits" -eq 0 ]; then
  pass "no numeric 'step N' cross-references (they rot on insertion)"
else
  fail "found $hits numeric step reference(s); use step names instead" "$(grep -noE '.{0,40}step [0-9]+.{0,25}' "$SKILL" | head -5)"
fi

# --- 2. flat, gap-free, correctly-ordered step numbering (no 11a-style wedges) ---
nums=$(grep -oE "^[0-9]+\. \*\*" "$SKILL" | grep -oE "^[0-9]+")
expected=1; seq_ok=1
for n in $nums; do
  [ "$n" -eq "$expected" ] || seq_ok=0
  expected=$((expected + 1))
done
if [ "$seq_ok" -eq 1 ] && [ "$expected" -gt 1 ]; then
  pass "process steps are flat and sequential 1..$((expected - 1))"
else
  fail "process step numbering must be flat and sequential" "got: $(echo $nums | tr '\n' ' ')"
fi

# --- 3. the override path names the flip and the commit, and never the review loop ---
override=$(grep -F "proceed anyway" "$SKILL")
if printf '%s' "$override" | grep -qF "status-flip step" \
   && printf '%s' "$override" | grep -qF "auto-commit step" \
   && ! printf '%s' "$override" | grep -qiE "Outside Voice|review loop"; then
  pass "peer-reject override routes to the status flip + auto-commit, not back into review"
else
  fail "peer-reject override must route to the status-flip and auto-commit steps"
fi

report
