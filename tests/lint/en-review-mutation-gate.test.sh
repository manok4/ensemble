#!/usr/bin/env bash
# Drift guards for the EN08 en-review transparency + mutation gate.
# Two field failures on a --lite interactive run: (1) the fail-closed lite gate
# silently overrode --lite (full roster, no reason surfaced); (2) the agent
# implemented findings wholesale, past the mode's mutation boundary. EN08 pins
# both as auditable contract: a mandatory lite_gate: outcome line (every run)
# and a recorded applied_fixes[] mutation boundary.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review mutation gate"

SKILL="$REPO_ROOT/skills/en-review/SKILL.md"
DIFFSIG="$REPO_ROOT/references/diff-signal-detection.md"

# === U1: lite-gate transparency ===

# --- exactly-one lite_gate: line on EVERY run, all three outcomes ---
if grep -qF "lite_gate: applied" "$SKILL" \
   && grep -qF "lite_gate: overridden" "$SKILL" \
   && grep -qF "lite_gate: not-requested" "$SKILL" \
   && grep -qiE "EVERY run emits exactly ONE .?lite_gate" "$SKILL"; then
  pass "lite_gate: line is mandatory on every run with applied/overridden/not-requested"
else
  fail "SKILL must require exactly one lite_gate: line per run (applied|overridden|not-requested)"
fi

# --- never a silent override ---
if grep -qiE "never a silent override" "$SKILL"; then
  pass "silent lite-gate override forbidden"
else
  fail "SKILL must state the override is never silent"
fi

# --- canonical reason enum present in BOTH files ---
enum_ok=1
for rid in "unknown-line-count" "exec-lines-out-of-range" "uncounted-files" "risk-signal" "conditional-persona:"; do
  grep -qF "$rid" "$SKILL" || enum_ok=0
  grep -qF "$rid" "$DIFFSIG" || enum_ok=0
done
if [ "$enum_ok" -eq 1 ]; then
  pass "canonical override-reason enum mirrored in SKILL and diff-signal-detection"
else
  fail "the override-reason enum must appear in both SKILL.md and diff-signal-detection.md"
fi

# --- deterministic multi-reason grammar (order, dedup, separator, persona encoding) ---
grammar_ok=1
grep -qiE "canonical order|fixed canonical order|fixed table order" "$SKILL" || grammar_ok=0
grep -qiE "dedup" "$SKILL" || grammar_ok=0
grep -qiE "comma\+space" "$SKILL" || grammar_ok=0
grep -qiE "alphabetically.sorted.*\+.*joined" "$SKILL" || grammar_ok=0
grep -qF "conditional-persona:performance+security" "$SKILL" || grammar_ok=0
if [ "$grammar_ok" -eq 1 ]; then
  pass "multi-reason grammar is deterministic (order, dedup, separator, +-joined sorted personas)"
else
  fail "SKILL must define the canonical multi-reason grammar"
fi

# --- structured envelope field; markdown line derived from it ---
if grep -qE '"lite_gate": \{"outcome"' "$SKILL" && grep -qiE "DERIVED from that object|derived from it" "$SKILL"; then
  pass "envelope carries structured lite_gate object; markdown line derives from it"
else
  fail "the JSON envelope must carry the structured lite_gate object and the line must derive from it"
fi

# --- markdown-summary example shows a lite_gate line ---
if sed -n '/## Markdown summary/,/## Reference files/p' "$SKILL" | grep -qF "lite_gate:"; then
  pass "markdown-summary example includes a lite_gate line"
else
  fail "the markdown-summary example must include a lite_gate line"
fi

report
