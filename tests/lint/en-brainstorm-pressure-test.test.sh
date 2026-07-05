#!/usr/bin/env bash
# Drift guards for the en-brainstorm Product pressure test (EN05 U1).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm pressure test"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
SOCRATIC="$REPO_ROOT/references/socratic-questions.md"

# --- pressure test step exists, before approaches ---
pt_line=$(grep -n "Product pressure test" "$SKILL" | head -1 | cut -d: -f1)
appr_line=$(grep -n "Propose 2.3 approaches\|Propose.*approaches" "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$pt_line" ] && [ -n "$appr_line" ] && [ "$pt_line" -lt "$appr_line" ]; then
  pass "en-brainstorm has a Product pressure test step before approaches"
else
  fail "Product pressure test must precede the propose-approaches step (pt=$pt_line appr=$appr_line)"
fi

# --- self-gating (fires only on real gaps; zero on a well-framed opening) ---
if grep -qiE "self-gating" "$SKILL" && grep -qiE "only those that actually exist|earns .*zero" "$SKILL"; then
  pass "pressure test is self-gating (fires only on real gaps)"
else
  fail "pressure test must be self-gating"
fi

# --- internal analysis, open-ended probes, not a checklist/menu ---
if grep -qiE "internal analysis" "$SKILL" && grep -qiE "open-ended probes" "$SKILL" && grep -qiE "never a pre-flight checklist|not a menu|never a checklist" "$SKILL"; then
  pass "probes are internal analysis surfaced open-ended (not a menu/checklist)"
else
  fail "pressure test probes must be open-ended internal analysis, not a checklist"
fi

# --- durability gap is Deep-only ---
if grep -qiE "Durability gap.*Deep|Deep / strategic scope only|Deep / strategic only" "$SKILL"; then
  pass "durability gap is scoped to Deep/strategic"
else
  fail "durability gap must be Deep-only"
fi

# --- probe-surfaces-uncertainty records an explicit assumption ---
if grep -qiE "explicit assumption" "$SKILL"; then
  pass "uncertainty is recorded as an explicit assumption, not skipped"
else
  fail "a probe surfacing uncertainty must record an explicit assumption"
fi

# --- all five gap names present in BOTH SKILL.md and socratic-questions ---
gaps_ok=1
for g in "Evidence" "Specificity" "Counterfactual" "Attachment" "Durability"; do
  grep -qiE "${g} gap|\*\*${g}\*\*" "$SKILL" || gaps_ok=0
  grep -qiE "\*\*${g}\*\*|${g} gap|${g}" "$SOCRATIC" || gaps_ok=0
done
if [ "$gaps_ok" -eq 1 ]; then
  pass "all five rigor gaps appear in SKILL.md and socratic-questions"
else
  fail "all five rigor gaps must appear in both SKILL.md and socratic-questions"
fi

# --- socratic-questions has the Product rigor gaps section ---
if grep -qE "^## Product rigor gaps" "$SOCRATIC"; then
  pass "socratic-questions documents the Product rigor gaps section"
else
  fail "socratic-questions must document the Product rigor gaps section"
fi

report
