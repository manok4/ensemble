#!/usr/bin/env bash
# Drift guards for the conditional Decisions/assumptions/risks section (EN03 U2).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan decisions section"

TEMPLATE="$REPO_ROOT/shared/references/templates/plan-template.md"
EN_PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"

# --- section exists in the template ---
if grep -qiE "^## Decisions, assumptions & risks" "$TEMPLATE"; then
  pass "plan-template has the Decisions/assumptions/risks section"
else
  fail "plan-template must have the Decisions, assumptions & risks section"
fi

# --- explicitly optional / omit on trivial plans ---
if grep -qiE "[Oo]ptional .*omit|omit entirely on trivial" "$TEMPLATE"; then
  pass "section is explicitly optional (omit on trivial plans)"
else
  fail "section must be explicitly optional"
fi

# --- covers the four content types ---
if grep -qiE "\*\*Decision:\*\*" "$TEMPLATE" && grep -qiE "\*\*Alternative:\*\*" "$TEMPLATE" && grep -qiE "\*\*Assumption:\*\*" "$TEMPLATE" && grep -qiE "\*\*Risk:\*\*" "$TEMPLATE"; then
  pass "section covers decision / alternative / assumption / risk"
else
  fail "section must cover decision / alternative / assumption / risk"
fi

# --- en-plan instructs population, conditionally ---
if grep -qiE "Decisions / assumptions / risks capture|Decisions, assumptions & risks" "$EN_PLAN"; then
  pass "en-plan instructs capture into the section"
else
  fail "en-plan must instruct capture into the section"
fi
if grep -qiE "Omit the section entirely" "$EN_PLAN"; then
  pass "en-plan says omit the section when nothing substantive"
else
  fail "en-plan must say to omit when nothing substantive (no boilerplate)"
fi

# --- lands there instead of unit Approach fields ---
if grep -qiE "rather than burying it in unit .Approach|rather than scattered" "$EN_PLAN"; then
  pass "decisions land in the section, not scattered in Approach fields"
else
  fail "en-plan must route decisions to the section, not Approach fields"
fi

report
