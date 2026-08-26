#!/usr/bin/env bash
# Behavior guards for the en-brainstorm Product pressure test (EN05 U1, recalibrated).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm pressure test"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
SOCRATIC="$REPO_ROOT/shared/references/socratic-questions.md"

# --- 1. self-gating: a well-framed opening pays no tax ---
if grep -qiE "self-gating" "$SKILL" && grep -qiE "only those that actually exist" "$SKILL" && grep -qiE "earns .*zero" "$SKILL"; then
  pass "pressure test is self-gating (well-framed opening earns zero probes)"
else
  fail "pressure test must be self-gating with an explicit zero-probe case"
fi

# --- 2. probe FORM: open-ended, never a menu; durability is Deep-only ---
if grep -qiE "open-ended probes" "$SKILL" \
   && grep -qiE "never a menu" "$SKILL" \
   && grep -qiE "never a pre-flight checklist" "$SKILL" \
   && grep -qiE "durability.*\(Deep" "$SKILL"; then
  pass "probes are open-ended (not a menu/checklist); durability scoped to Deep"
else
  fail "probe form broken: must be open-ended, not a menu/checklist, durability Deep-only"
fi

# --- 3. the gap catalogue is CANONICAL in socratic-questions, and SKILL does not duplicate the probe text.
#        (Negative control: the old contract mandated the full probes in both files.) ---
cat_ok=1
grep -qE "^## Product rigor gaps" "$SOCRATIC" || cat_ok=0
grep -qiE "concrete thing someone.s already done" "$SOCRATIC" || cat_ok=0   # evidence
grep -qiE "specific person or narrow segment" "$SOCRATIC" || cat_ok=0       # specificity
grep -qiE "current workaround" "$SOCRATIC" || cat_ok=0                      # counterfactual
grep -qiE "smallest version that still delivers real value" "$SOCRATIC" || cat_ok=0  # attachment
grep -qiE "near-term shifts" "$SOCRATIC" || cat_ok=0                        # durability
grep -qiE "one probe (per gap|satisfies one gap)" "$SOCRATIC" || cat_ok=0
# SKILL names the gaps and points at the catalogue, but must NOT restate the probes:
grep -qiE "concrete thing someone.s already done|specific person or narrow segment" "$SKILL" && cat_ok=0
for g in evidence specificity counterfactual attachment durability; do
  grep -qiE "\*\*${g}\*\*" "$SKILL" || cat_ok=0
done
if [ "$cat_ok" -eq 1 ]; then
  pass "gap catalogue canonical in socratic-questions; SKILL names gaps without duplicating probes"
else
  fail "gap catalogue must live once in socratic-questions; SKILL names the five gaps only"
fi

# --- 4. probes are budgeted, not additive; Lightweight capped at one ---
if grep -qiE "count toward the depth question budget" "$SKILL" \
   && grep -qiE "add no separate quota|don.t add a separate quota" "$SKILL" \
   && grep -qF "**at most one**" "$SKILL" && grep -qiE "On \*\*Lightweight\*\*" "$SKILL"; then
  pass "probes count toward the depth budget (no separate quota); Lightweight caps at one"
else
  fail "probe budget broken: must be additive-free and Lightweight-capped"
fi

report
