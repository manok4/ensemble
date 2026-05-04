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

Cites TD42 which doesn't exist in tech-debt-tracker.
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

# --- logging.unstructured: opt-in via .ensemble/config.local.yaml --------------
# When structured_logging_required is true, console.log in tracked TS source
# should fire P2 advisory. Logs in dev paths (tests/, scripts/) should not fire.
setup_minimum
mkdir -p "$TMP/.ensemble" "$TMP/src" "$TMP/tests"
cat > "$TMP/.ensemble/config.local.yaml" <<'EOF'
observability:
  structured_logging_required: true
  logging_dev_paths:
    - "tests/**"
    - "scripts/**"
EOF
cat > "$TMP/src/auth.ts" <<'EOF'
export function login() {
  console.log("user logged in");
}
EOF
cat > "$TMP/tests/auth.test.ts" <<'EOF'
console.log("test fixture setup");
EOF
# Initialize git so ensemble-lint's `git ls-files` finds the source files
cd "$TMP" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init
cd - >/dev/null
assert_rule_fires "logging.unstructured" "console.log in src/ when structured_logging_required: true"
# Verify the dev path didn't fire — re-run and check the output doesn't mention tests/
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -q "tests/auth.test.ts" \
   && echo "$output" | grep -q "logging.unstructured"; then
  fail "logging.unstructured fired on tests/ path (should be exempt)"
else
  pass "logging.unstructured exempts logging_dev_paths"
fi

# When structured_logging_required is false (or missing), no console.log findings.
setup_minimum
mkdir -p "$TMP/.ensemble" "$TMP/src"
cat > "$TMP/.ensemble/config.local.yaml" <<'EOF'
observability:
  structured_logging_required: false
EOF
cat > "$TMP/src/auth.ts" <<'EOF'
console.log("nothing wrong with this");
EOF
cd "$TMP" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init
cd - >/dev/null
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -q "logging.unstructured"; then
  fail "logging.unstructured fired when structured_logging_required: false" "$(echo "$output" | head -3)"
else
  pass "logging.unstructured silent when opt-in is off"
fi

# --- architecture.fitness: invokes bin/check-fitness when present ---------------
# When fitness.enabled is true, ensemble-lint runs bin/check-fitness and
# surfaces its JSON-lines output as findings.
setup_minimum
mkdir -p "$TMP/.ensemble" "$TMP/bin" "$TMP/src"
cat > "$TMP/.ensemble/config.local.yaml" <<'EOF'
fitness:
  enabled: true
  check_command: bin/check-fitness
EOF
cat > "$TMP/bin/check-fitness" <<'CHECKER'
#!/usr/bin/env bash
# Mock checker — emits one JSON-lines finding regardless of input.
cat <<'JSON'
{"rule": "architecture.layer-violation", "file": "src/types/user.ts", "line": 12, "severity": "P1", "message": "Layer 'Types' imports from 'Service'", "remediation": "Move helper down to a lower layer"}
JSON
exit 1
CHECKER
chmod +x "$TMP/bin/check-fitness"
mkdir -p "$TMP/src/types"
cat > "$TMP/src/types/user.ts" <<'EOF'
export type User = { id: string };
EOF
cd "$TMP" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init
cd - >/dev/null
assert_rule_fires "architecture.layer-violation" "bin/check-fitness output surfaced as lint finding"

# When fitness.enabled is true but checker is missing, surface advisory.
setup_minimum
mkdir -p "$TMP/.ensemble"
cat > "$TMP/.ensemble/config.local.yaml" <<'EOF'
fitness:
  enabled: true
EOF
assert_rule_fires "architecture.fitness-checker-missing" "fitness enabled but checker missing"

# --- learnings.bootstrap-unvalidated: fires for old unvalidated bootstrap entries ----
# Bootstrapped patterns with requires_validation: true and bootstrap_run > 30 days
# old surface as P3 advisory.
setup_minimum
mkdir -p "$TMP/docs/learnings/patterns"
# Old bootstrap entry (>30 days)
cat > "$TMP/docs/learnings/patterns/old-pattern-2026-03-01.md" <<'EOF'
---
title: Old bootstrapped pattern
date: 2026-03-01
category: patterns
problem_type: maintainability
component: utils
applies_when: forever
tags: []
related: []
confidence: 6
status: active
source: bootstrap
bootstrap_run: 2026-03-01
requires_validation: true
---

# Old pattern
EOF
echo "- [\`old-pattern-2026-03-01.md\`](../learnings/patterns/old-pattern-2026-03-01.md) — fixture" >> "$TMP/docs/generated/learning-index.md"
assert_rule_fires "learnings.bootstrap-unvalidated" "stale unvalidated bootstrap entries"

# Recent bootstrap entry (<30 days) should NOT fire the rule.
setup_minimum
mkdir -p "$TMP/docs/learnings/patterns"
TODAY=$(date -u +%Y-%m-%d)
cat > "$TMP/docs/learnings/patterns/fresh-pattern-${TODAY}.md" <<EOF
---
title: Fresh bootstrapped pattern
date: ${TODAY}
category: patterns
problem_type: maintainability
component: utils
applies_when: forever
tags: []
related: []
confidence: 6
status: active
source: bootstrap
bootstrap_run: ${TODAY}
requires_validation: true
---

# Fresh pattern
EOF
echo "- [\`fresh-pattern-${TODAY}.md\`](../learnings/patterns/fresh-pattern-${TODAY}.md) — fixture" >> "$TMP/docs/generated/learning-index.md"
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -q "learnings.bootstrap-unvalidated"; then
  fail "bootstrap rule fired on fresh entry (should require >30 days)"
else
  pass "bootstrap rule silent on fresh entries"
fi

# Validated bootstrap entry (requires_validation: false) should NOT fire even if old.
setup_minimum
mkdir -p "$TMP/docs/learnings/patterns"
cat > "$TMP/docs/learnings/patterns/validated-2025-12-01.md" <<'EOF'
---
title: Validated bootstrap entry
date: 2025-12-01
category: patterns
problem_type: maintainability
component: utils
applies_when: forever
tags: []
related: []
confidence: 8
status: active
source: bootstrap
bootstrap_run: 2025-12-01
requires_validation: false
---

# Validated
EOF
echo "- [\`validated-2025-12-01.md\`](../learnings/patterns/validated-2025-12-01.md) — fixture" >> "$TMP/docs/generated/learning-index.md"
result=$(run_lint)
output="${result%%|||*}"
if echo "$output" | grep -q "learnings.bootstrap-unvalidated"; then
  fail "bootstrap rule fired on validated entry"
else
  pass "bootstrap rule silent once entry is validated"
fi

report
