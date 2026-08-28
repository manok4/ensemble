#!/usr/bin/env bash
# Per-rule lint tests. Each rule has at least one fixture that should fire it.
# We test rules NOT already covered by tests/golden/frontmatter/ to keep the
# suite minimally redundant.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="lint rules"

LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"

# Setup: tempdir mirroring repo layout
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

setup_minimum() {
  rm -rf "$TMP"/*
  mkdir -p "$TMP/docs/plans/active" "$TMP/docs/plans/completed" "$TMP/docs/learnings/sources" "$TMP/docs/generated" "$TMP/docs/designs"
  cat > "$TMP/docs/generated/plan-index.md" <<EOF
---
type: learning-index
generated: true
generator: en-learn
updated: 2026-04-29
total_entries: 0
---
EOF
  cat > "$TMP/docs/generated/learning-index.md" <<EOF
---
type: learning-index
generated: true
generator: en-learn
updated: 2026-04-29
total_entries: 0
---
EOF
  cat > "$TMP/docs/foundation.md" <<EOF
---
project: Test
type: foundation
status: draft
created: 2026-04-29
updated: 2026-04-29
owner: Test
depth: standard
---

# Test foundation

## 5. Functional Requirements

### R1. First requirement

### R2. Second requirement
EOF
}

run_lint() {
  pushd "$TMP" >/dev/null
  local output rc
  output=$("$LINT" --scope docs/ 2>&1)
  rc=$?
  popd >/dev/null
  echo "$output|||$rc"
}

assert_rule_fires() {
  local rule="$1"
  local label="$2"
  local result
  result=$(run_lint)
  local output="${result%%|||*}"
  local rc="${result##*|||}"

  if [ "$rc" -ne 0 ] && echo "$output" | grep -qF "$rule"; then
    pass "$label fires $rule"
  else
    fail "$label should fire $rule" "rc=$rc, output: $(echo "$output" | head -5)"
  fi
}

# --- path.absolute ---
setup_minimum
cat > "$TMP/docs/plans/active/FR50-test.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR50
title: Path absolute test
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50

This plan references /Users/somebody/code/foo.ts (an absolute path) outside backticks.
EOF
assert_rule_fires "path.absolute" "absolute path outside backticks"

# Path absolute INSIDE backticks should NOT fire (regression test for our backtick fix)
setup_minimum
cat > "$TMP/docs/plans/active/FR50-test.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR50
title: Backtick path test
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50

This plan references \`/Users/somebody/code/foo.ts\` inside backticks; should NOT trigger path.absolute.
EOF
result=$(run_lint)
output="${result%%|||*}"
rc="${result##*|||}"
if [ "$rc" -eq 0 ] || ! echo "$output" | grep -qF "path.absolute"; then
  pass "absolute path inside backticks does NOT fire path.absolute"
else
  fail "absolute path inside backticks should not fire" "$(echo "$output" | grep path.absolute)"
fi

# --- cross-link.broken-r ---
setup_minimum
cat > "$TMP/docs/plans/active/FR50-test.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR50
title: Broken R-ID test
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50

Cites R99 which doesn't exist in foundation.md.
EOF
assert_rule_fires "cross-link.broken-r" "missing R-ID"

# --- cross-link.broken-u ---
setup_minimum
cat > "$TMP/docs/plans/active/FR50-test.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR50
title: Broken U-ID test
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50

### U1. Real unit

This unit references U7 which doesn't have a declaration in this plan.
EOF
assert_rule_fires "cross-link.broken-u" "missing U-ID"

# --- cross-link.broken-fr ---
setup_minimum
cat > "$TMP/docs/plans/active/FR50-test.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR50
title: Broken FR test
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50

This plan cites FR99 which doesn't exist as a plan file.
EOF
assert_rule_fires "cross-link.broken-fr" "missing FR plan file"

# --- cross-link.broken-td ---
setup_minimum
cat > "$TMP/docs/plans/tech-debt-tracker.md" <<EOF
---
type: tech-debt-tracker
generated: false
created: 2026-04-29
updated: 2026-04-29
---

# Tech debt tracker

## Open

### TD1. Real entry
EOF
cat > "$TMP/docs/plans/active/FR50-test.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR50
title: Broken TD test
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50

## Tracked debt

- **Resolves:** TD42
EOF
assert_rule_fires "cross-link.broken-td" "missing TD entry"

# --- id-stability.fr-collision ---
setup_minimum
cat > "$TMP/docs/plans/active/FR42-a.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR42
title: First
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR42 — first
EOF
cat > "$TMP/docs/plans/completed/FR42-b.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR42
title: Collision
status: completed
location: completed
created: 2026-04-29
covers_requirements: []
requirements_pending: true
---

# FR42 — collision
EOF
assert_rule_fires "id-stability.fr-collision" "duplicate FR id across plans"

# --- index-coverage.plan-missing ---
setup_minimum
cat > "$TMP/docs/plans/active/FR50-test.md" <<EOF
---
type: plan
plan_type: feature
fr_id: FR50
title: Test
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50
EOF
# plan-index.md is empty so the new plan is missing
assert_rule_fires "index-coverage.plan-missing" "plan not in plan-index.md"

# --- index-coverage.learning-missing ---
setup_minimum
cat > "$TMP/docs/learnings/test-2026-04-29.md" <<EOF
---
title: Test
applies_when: never
date: 2026-04-29
category: patterns
tags: []
related: []
status: active
---

# Test
EOF
assert_rule_fires "index-coverage.learning-missing" "learning not in learning-index.md"

# --- generated.missing-marker ---
setup_minimum
cat > "$TMP/docs/generated/synthetic.md" <<EOF
# Generated file without proper marker
EOF
assert_rule_fires "generated.missing-marker" "generated/ file lacks frontmatter marker"

# --- freshness.architecture-90 ---
setup_minimum
cat > "$TMP/docs/architecture.md" <<EOF
---
project: Test
type: architecture
status: seed
created: 2025-01-01
updated: 2025-01-01
last_drift_check: 2025-01-01
freshness_target_days: 30
---

# Architecture (very stale)
EOF
assert_rule_fires "freshness.architecture-90" "architecture >90 days stale"

# --- length.agents-md-over-150 ---
setup_minimum
{
  cat <<EOF
---
project: Test
type: agent-map
host: any
created: 2026-04-29
updated: 2026-04-29
target_length_lines: 100
---

EOF
  for i in $(seq 1 200); do echo "Line $i — filler content to exceed the 150-line ceiling."; done
} > "$TMP/AGENTS.md"
assert_rule_fires "length.agents-md-over-150" "AGENTS.md over 150 lines"

# --- length.claude-md-over-80 ---
setup_minimum
{
  cat <<EOF
---
project: Test
type: agent-map
host: claude-code
created: 2026-04-29
updated: 2026-04-29
target_length_lines: 60
references: ./AGENTS.md
---

> See [AGENTS.md](./AGENTS.md) for the project map and shared agent guidance.

EOF
  for i in $(seq 1 100); do echo "Line $i — filler content to exceed the 80-line ceiling."; done
} > "$TMP/CLAUDE.md"
assert_rule_fires "length.claude-md-over-80" "CLAUDE.md over 80 lines"

# --- Custom plan_id_prefix: EN -------------------------------------------------
# Foundation declares plan_id_prefix: EN. A plan named EN01-feature_test.md with
# plan_id: EN01 should lint clean. A plan citing EN99 (no such file) should fire
# cross-link.broken-fr (the rule code is preserved for back-compat).
setup_minimum
# Override foundation to advertise the EN prefix.
sed -i.bak 's/^depth: standard$/depth: standard\nplan_id_prefix: EN/' "$TMP/docs/foundation.md" && rm -f "$TMP/docs/foundation.md.bak"
cat > "$TMP/docs/plans/active/EN01-feature_test.md" <<EOF
---
type: plan
plan_type: feature
plan_id: EN01
title: First EN-prefixed plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# EN01

Body. Cites EN99 which doesn't exist.
EOF
echo "- [\`EN01-feature_test.md\`](../plans/active/EN01-feature_test.md) — fixture" >> "$TMP/docs/generated/plan-index.md"
assert_rule_fires "cross-link.broken-fr" "EN-prefix plan citing missing EN99"

# Same plan without the broken cite should NOT fire id-stability.fr-format
# (regression: plan_id 'EN01' must be accepted as valid 2-letter prefix + 2-digit number).
setup_minimum
sed -i.bak 's/^depth: standard$/depth: standard\nplan_id_prefix: EN/' "$TMP/docs/foundation.md" && rm -f "$TMP/docs/foundation.md.bak"
cat > "$TMP/docs/plans/active/EN01-feature_test.md" <<EOF
---
type: plan
plan_type: feature
plan_id: EN01
title: Clean EN-prefixed plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# EN01
EOF
echo "- [\`EN01-feature_test.md\`](../plans/active/EN01-feature_test.md) — fixture" >> "$TMP/docs/generated/plan-index.md"
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -qF "id-stability.fr-format"; then
  fail "EN01 should be accepted as valid plan_id format" "$(echo "$output" | grep id-stability.fr-format)"
else
  pass "EN01 accepted as valid <PREFIX><NN> plan_id"
fi

# --- unit.risk-class: new-style plan missing Risk fires P1 ---
setup_minimum
cat > "$TMP/docs/plans/active/FR60-no-risk.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR60
title: No-risk-field plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
---

# FR60

### U1. First unit

- **Goal:** do something
- **Files:** src/foo.ts
- **Approach:** straightforward
EOF
assert_rule_fires "unit.risk-class" "new-style plan with unit missing Risk:"

# --- unit.risk-class: invalid value fires ---
setup_minimum
cat > "$TMP/docs/plans/active/FR61-bad-risk.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR61
title: Bad-risk plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
---

# FR61

### U1. First unit

- **Goal:** do something
- **Risk:** kinda-risky
- **Files:** src/foo.ts
- **Approach:** straightforward
EOF
assert_rule_fires "unit.risk-class" "invalid Risk: enum value"

# --- unit.risk-class: legacy plan (no peer_review_resolutions field) gets P3 advisory only ---
setup_minimum
cat > "$TMP/docs/plans/active/FR62-legacy.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR62
title: Legacy plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR62

### U1. Pre-spec unit

- **Goal:** do something
- **Files:** src/foo.ts
- **Approach:** straightforward
EOF
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -q '\[P3\] unit.risk-class'; then
  pass "legacy plan missing Risk fires P3 advisory (not P1)"
else
  fail "legacy plan should fire P3 unit.risk-class advisory" "$(echo "$output" | grep risk-class)"
fi
if echo "$output" | grep -q '\[P1\] unit.risk-class'; then
  fail "legacy plan should NOT fire P1 unit.risk-class" "$(echo "$output" | grep -E '\[P1\] unit.risk-class')"
else
  pass "legacy plan does NOT fire P1 unit.risk-class"
fi

# --- unit.risk-class + unit.gated-flag: clean fixture passes ---
setup_minimum
cat > "$TMP/docs/plans/active/FR63-clean.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR63
title: Clean fixture
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
---

# FR63

### U1. Clean unit

- **Goal:** do something
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** straightforward
EOF
result=$(run_lint)
output="${result%%|||*}"
rc="${result##*|||}"
if [ "$rc" -eq 0 ] || ! echo "$output" | grep -qE 'unit\.(risk-class|gated-flag|category-enum)'; then
  pass "clean new-style plan fires no risk/gated/category violations"
else
  fail "clean fixture unexpectedly fired" "$(echo "$output" | grep -E 'unit\.')"
fi

# --- unit.category-enum: bad category fires ---
setup_minimum
cat > "$TMP/docs/plans/active/FR64-bad-cat.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR64
title: Bad-category plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
---

# FR64

### U1. Unit

- **Goal:** do something
- **Risk:** medium
- **Category:** newfangled
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** ok
EOF
assert_rule_fires "unit.category-enum" "invalid Category: enum"

# --- phase-invariant.dependency-vs-risk: low depends on destructive fires ---
setup_minimum
cat > "$TMP/docs/plans/active/FR65-bad-deps.md" <<EOF
---
type: plan
plan_type: improvement
plan_id: FR65
title: Phase-invariant-violating plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
---

# FR65

### U1. Drop the table

- **Goal:** drop legacy_users
- **Risk:** destructive
- **Category:** drop
- **Gated:** false
- **Dependencies:** none
- **Files:** migrations/0001_drop.sql
- **Approach:** DROP TABLE

### U2. Add a docstring

- **Goal:** add comment to module
- **Risk:** low
- **Category:** observability
- **Gated:** false
- **Dependencies:** U1
- **Files:** src/foo.py
- **Approach:** add docstring referring to dropped table
EOF
assert_rule_fires "phase-invariant.dependency-vs-risk" "low-risk depends on destructive"

# --- phase-invariant.dependency-vs-risk: same-tier or descending order does NOT fire ---
setup_minimum
cat > "$TMP/docs/plans/active/FR66-good-deps.md" <<EOF
---
type: plan
plan_type: improvement
plan_id: FR66
title: Phase-invariant-respecting plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
---

# FR66

### U1. Add docstring

- **Goal:** docs
- **Risk:** low
- **Category:** observability
- **Gated:** false
- **Dependencies:** none
- **Files:** src/foo.py
- **Approach:** straightforward

### U2. Drop the table

- **Goal:** cleanup
- **Risk:** destructive
- **Category:** drop
- **Gated:** false
- **Dependencies:** U1
- **Files:** migrations/0001_drop.sql
- **Approach:** DROP TABLE
EOF
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -q "phase-invariant.dependency-vs-risk"; then
  fail "phase-invariant fired on valid descending-risk dependency" "$(echo "$output" | grep phase-invariant)"
else
  pass "phase-invariant silent on valid risk-tier dependency (low → destructive)"
fi

# --- peer-review-resolutions.schema: missing required field fires ---
setup_minimum
cat > "$TMP/docs/plans/active/FR67-bad-res.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR67
title: Bad-resolution-entry plan
status: draft
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_verdict: revise
peer_review_resolutions:
  - finding_id: 1-1
    severity: P1
    status: applied
    title: Race in refresh path
---

# FR67

### U1. Unit

- **Goal:** stuff
- **Risk:** medium
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** ok
EOF
assert_rule_fires "peer-review-resolutions.schema" "resolution entry missing iteration"

# --- peer-review-resolutions.schema: deferred without rationale fires ---
setup_minimum
cat > "$TMP/docs/plans/active/FR68-no-rationale.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR68
title: Deferred-without-rationale plan
status: draft
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_verdict: revise
peer_review_resolutions:
  - finding_id: 1-2
    iteration: 1
    severity: P2
    title: Edge case
    status: deferred
---

# FR68

### U1. Unit

- **Goal:** stuff
- **Risk:** medium
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** ok
EOF
assert_rule_fires "peer-review-resolutions.schema" "deferred entry without rationale"

# --- peer-review-resolutions.schema: clean entry passes ---
setup_minimum
cat > "$TMP/docs/plans/active/FR69-clean-res.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR69
title: Clean-resolution plan
status: draft
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_verdict: revise
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: Race in refresh path
    status: applied
  - finding_id: 1-2
    iteration: 1
    severity: P2
    title: Edge case
    status: deferred
    rationale: lower confidence; tracked in TD12
---

# FR69

### U1. Unit

- **Goal:** stuff
- **Risk:** medium
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** ok
EOF
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -q "peer-review-resolutions.schema"; then
  fail "schema rule fired on clean resolution entries" "$(echo "$output" | grep peer-review-resolutions)"
else
  pass "schema rule silent on well-formed resolution entries"
fi

# --- frontmatter.invalid-enum: peer_review_verdict bad value ---
setup_minimum
cat > "$TMP/docs/plans/active/FR70-bad-verdict.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR70
title: Bad-verdict plan
status: draft
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_verdict: maybe
peer_review_resolutions: []
---

# FR70

### U1. Unit

- **Goal:** stuff
- **Risk:** medium
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** ok
EOF
assert_rule_fires "frontmatter.invalid-enum" "invalid peer_review_verdict"

# --- frontmatter.invalid-enum: data_scale bad value ---
setup_minimum
cat > "$TMP/docs/plans/active/FR71-bad-scale.md" <<EOF
---
type: plan
plan_type: feature
plan_id: FR71
title: Bad-scale plan
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
data_scale: enormous
---

# FR71

### U1. Unit

- **Goal:** stuff
- **Risk:** medium
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** ok
EOF
assert_rule_fires "frontmatter.invalid-enum" "invalid data_scale"

# --- unit.risk-class: a "## " heading closes the units section ---
# Regression: extract_units only reset at the next `### U<N>`, so the final unit
# stayed open to end-of-file and absorbed the "- **Risk:** … — **Mitigation:** …"
# bullets the plan template prescribes under "## Decisions, assumptions & risks".
# A well-formed plan then reported its last unit's risk as an invalid enum.
setup_minimum
cat > "$TMP/docs/plans/active/FR70-risk-section.md" <<EOF
---
type: plan
plan_type: improvement
plan_id: FR70
title: Risk section after final unit
status: open
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
peer_review_resolutions: []
---

# FR70 — Risk section after final unit

## Implementation units

### U1. Only unit

- **Goal:** stuff
- **Risk:** medium
- **Category:** feature
- **Gated:** false
- **Files:** src/foo.ts
- **Approach:** ok
- **Test expectation:** none — fixture
- **Verification:** lint clean

## Decisions, assumptions & risks

- **Risk:** the copies drift out of sync — **Mitigation:** a byte-parity test in CI
- **Assumption:** hosts resolve relative reads against the skill directory
EOF
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -qF "unit.risk-class"; then
  fail "a '## ' heading closes the units section" "$(echo "$output" | grep -F 'unit.risk-class' | head -2)"
else
  pass "a '## ' heading closes the units section"
fi

# --- cross-link.broken-td: only a Resolves: field is a citation ---
# The rule matched every \bTD[0-9]+\b in every file, so creating the tracker
# turned prose that merely names the syntax into P1 errors: foundation.md's
# "cites them as `Resolves: TD7` in unit metadata" and a spec's sample output
# "1 deferred to TD8". Neither cites anything. The rule's own definition
# (references/tech-debt-tracker-format.md:147) scopes it to `Resolves: TD<n>`.
make_tracker() {
  cat > "$TMP/docs/plans/tech-debt-tracker.md" <<EOF
---
type: tech-debt-tracker
generated: false
created: 2026-04-29
updated: 2026-04-29
---

# Tech debt tracker

## Open

### TD1. A real entry

- **Severity:** P2
- **Logged:** 2026-04-29

## Resolved
EOF
}

# Fires: a genuine citation of a TD-ID with no entry.
setup_minimum
make_tracker
cat >> "$TMP/docs/foundation.md" <<EOF

## Tracked debt

- **Resolves:** TD99
EOF
assert_rule_fires "cross-link.broken-td" "a Resolves: field naming a missing TD"

# Does not fire: prose naming the syntax, and sample output mentioning a TD-ID.
setup_minimum
make_tracker
cat >> "$TMP/docs/foundation.md" <<EOF

- **Q19.** \`en-plan\` cites them as \`Resolves: TD98\` in unit metadata.

Sample run output:

    Peer review: verdict revise. Applied 2 of 3 findings (1 deferred to TD97).
EOF
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -qF "cross-link.broken-td"; then
  fail "prose and sample output are not TD citations" "$(echo "$output" | grep -F 'broken-td' | head -2)"
else
  pass "prose and sample output are not TD citations"
fi

# Does not fire: a real citation that resolves.
setup_minimum
make_tracker
cat >> "$TMP/docs/foundation.md" <<EOF

- **Resolves:** TD1
EOF
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -qF "cross-link.broken-td"; then
  fail "a Resolves: field naming an existing TD is clean" "$(echo "$output" | grep -F 'broken-td' | head -2)"
else
  pass "a Resolves: field naming an existing TD is clean"
fi

report
