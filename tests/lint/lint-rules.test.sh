#!/usr/bin/env bash
# Per-rule lint tests. Each rule has at least one fixture that should fire it.
# We test rules NOT already covered by tests/golden/frontmatter/ to keep the
# suite minimally redundant.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="lint rules"

LINT="$REPO_ROOT/bin/ensemble-lint"

# Setup: tempdir mirroring repo layout
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

setup_minimum() {
  rm -rf "$TMP"/*
  mkdir -p "$TMP/docs/plans/active" "$TMP/docs/plans/completed" "$TMP/docs/learnings/bugs" "$TMP/docs/learnings/patterns" "$TMP/docs/learnings/decisions" "$TMP/docs/learnings/sources" "$TMP/docs/generated" "$TMP/docs/designs"
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
fr_id: FR50
title: Path absolute test
status: active
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
fr_id: FR50
title: Backtick path test
status: active
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
fr_id: FR50
title: Broken R-ID test
status: active
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
fr_id: FR50
title: Broken U-ID test
status: active
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
fr_id: FR50
title: Broken FR test
status: active
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
fr_id: FR50
title: Broken TD test
status: active
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR50

Cites TD42 which doesn't exist in tech-debt-tracker.
EOF
assert_rule_fires "cross-link.broken-td" "missing TD entry"

# --- id-stability.fr-collision ---
setup_minimum
cat > "$TMP/docs/plans/active/FR42-a.md" <<EOF
---
type: plan
fr_id: FR42
title: First
status: active
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
fr_id: FR50
title: Test
status: active
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
cat > "$TMP/docs/learnings/patterns/test-2026-04-29.md" <<EOF
---
title: Test
date: 2026-04-29
category: patterns
problem_type: correctness
component: test
applies_when: never
tags: []
related: []
confidence: 5
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

report
