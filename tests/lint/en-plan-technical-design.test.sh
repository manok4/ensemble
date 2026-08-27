#!/usr/bin/env bash
# Drift guards for the technical-design load-bearing audit (EN03 U3).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan technical-design audit"

EN_PLAN="$REPO_ROOT/skills/en-plan/SKILL.md"
TEMPLATE="$REPO_ROOT/shared/references/templates/plan-template.md"

# --- audit documented in en-plan ---
if grep -qiE "Technical-design load-bearing audit" "$EN_PLAN"; then
  pass "en-plan documents the technical-design audit"
else
  fail "en-plan must document the technical-design audit"
fi

# --- triggers enumerated ---
if grep -qiE "3 new/changed components|≥3 new" "$EN_PLAN" && grep -qiE "state machine" "$EN_PLAN" && grep -qiE "data-flow stages" "$EN_PLAN"; then
  pass "en-plan enumerates the architecture-complexity triggers"
else
  fail "en-plan must enumerate the complexity triggers"
fi

# --- pre-write verifies presence when a trigger fired ---
if grep -qiE "missing section with a fired trigger is .*incomplete|Verify the section is present when a trigger fired" "$EN_PLAN"; then
  pass "pre-write verifies section presence when a trigger fired"
else
  fail "pre-write must verify section presence when triggered"
fi

# --- self-gating: not required / not added when no trigger ---
if grep -qiE "[Ss]elf-gating" "$EN_PLAN" && grep -qiE "must not be added as boilerplate|not required" "$EN_PLAN"; then
  pass "self-gating: no section required/added when no trigger fires"
else
  fail "must be self-gating (no boilerplate when no trigger)"
fi

# --- template has the optional Technical design section, trigger-gated ---
if grep -qiE "^## Technical design" "$TEMPLATE"; then
  pass "plan-template has the Technical design section"
else
  fail "plan-template must have the Technical design section"
fi
if grep -qiE "ONLY when an architecture-complexity trigger fires|Omit this section entirely on simpler plans" "$TEMPLATE"; then
  pass "template marks Technical design as trigger-gated / omit-when-simple"
else
  fail "template must mark Technical design as trigger-gated"
fi

report
