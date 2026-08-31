#!/usr/bin/env bash
# Drift guards for en-plan test-scenario specificity gate (EN03 U1).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan test-scenarios gate"

TEMPLATE="$REPO_ROOT/skills/en-build/references/templates/plan-template.md"
EN_PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
# doc-lints.md is carried by the skills that enforce the lint catalogue.
# en-sweep is the canonical one: it names the reference in its own flow.
# This previously read en-build's copy, which was payload en-build never
# reached, so the assertion broke the moment that copy was dropped.
DOCLINTS="$REPO_ROOT/skills/en-sweep/references/doc-lints.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

# --- plan-template documents the categories + escape ---
if grep -qiE "happy path" "$TEMPLATE" && grep -qiE "edge case" "$TEMPLATE" && grep -qiE "error / failure|error/failure" "$TEMPLATE" && grep -qiE "[Ii]ntegration" "$TEMPLATE"; then
  pass "plan-template documents the four test-scenario categories"
else
  fail "plan-template must document happy/edge/error/integration categories"
fi
if grep -qiE "Test expectation:.* none" "$TEMPLATE"; then
  pass "plan-template documents the 'Test expectation: none' escape"
else
  fail "plan-template must document the non-feature escape hatch"
fi

# --- en-plan pre-write check ---
if grep -qiE "Pre-write plan-quality review" "$EN_PLAN"; then
  pass "en-plan has a pre-write plan-quality review"
else
  fail "en-plan must have a pre-write plan-quality review"
fi
if grep -qiE "Test-scenario completeness|feature-bearing unit" "$EN_PLAN"; then
  pass "en-plan pre-write check covers test-scenario completeness"
else
  fail "en-plan pre-write check must cover test-scenario completeness"
fi

# --- lint rule exists + dispatched ---
if grep -qF "check_plan_unit_test_scenarios" "$LINT" && grep -qF "unit.test-scenarios" "$LINT"; then
  pass "unit.test-scenarios rule defined + emits"
else
  fail "unit.test-scenarios rule must be defined"
fi
if grep -qF 'check_plan_unit_test_scenarios "$file"' "$LINT"; then
  pass "unit.test-scenarios is dispatched in the per-file check run"
else
  fail "unit.test-scenarios must be dispatched"
fi

# --- doc-lints documents it ---
if grep -qF "unit.test-scenarios" "$DOCLINTS"; then
  pass "doc-lints catalogs unit.test-scenarios"
else
  fail "doc-lints must catalog unit.test-scenarios"
fi

# --- foundation D37 ---
if grep -qE "^- \*\*D37\." "$FOUNDATION"; then
  pass "foundation records D37"
else
  fail "foundation must record D37"
fi

# --- functional: flags a thin feature unit, not a config unit with escape ---
TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT
mkdir -p "$TMP/docs/plans/active"
cat > "$TMP/docs/plans/active/EN99-improvement_x.md" <<'EOF'
---
type: plan
plan_id: EN99
plan_type: improvement
status: open
---
### U1. Thin feature
- **Risk:** medium
- **Category:** feature
- **Gated:** false
- **Test scenarios:**
  - tests pass
- **Verification:** green

### U2. Config only
- **Risk:** low
- **Category:** other
- **Gated:** false
- **Test expectation:** none — config-only
- **Verification:** green

### U3. Good feature
- **Risk:** medium
- **Category:** feature
- **Gated:** false
- **Test scenarios:**
  - Happy path: input A -> action -> outcome B
  - Edge case: empty input -> no-op
  - Error path: invalid input -> raises
- **Verification:** green
EOF
out=$(cd "$TMP" && bash "$LINT" --scope docs/plans/active/EN99-improvement_x.md 2>&1)
if echo "$out" | grep -q "unit.test-scenarios.*Unit U1"; then
  pass "flags a thin feature unit (U1)"
else
  fail "must flag a thin feature unit (U1)"
fi
if echo "$out" | grep -q "unit.test-scenarios.*Unit U2"; then
  fail "must NOT flag a non-feature unit with the escape (U2)"
else
  pass "does not flag a non-feature unit with the escape (U2)"
fi
if echo "$out" | grep -q "unit.test-scenarios.*Unit U3"; then
  fail "must NOT flag a well-specified feature unit (U3)"
else
  pass "does not flag a well-specified feature unit (U3)"
fi
# --- severity is P2 (advisory), never P1 ---
if echo "$out" | grep "unit.test-scenarios" | grep -q "\[P2\]"; then
  pass "unit.test-scenarios is P2 advisory"
else
  fail "unit.test-scenarios must be P2 advisory"
fi

report
