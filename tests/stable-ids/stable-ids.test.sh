#!/usr/bin/env bash
# Stable-ID invariant tests. Per foundation §20.2.
#
# Verifies the lint catches violations of:
#   - U-IDs that have been renumbered (declaration in plan changed but citation didn't)
#   - FRXX collisions (two plans claim the same fr_id)
#   - FR format (must be FR<NN> zero-padded)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="stable IDs"

LINT="$REPO_ROOT/bin/ensemble-lint"

setup_repo() {
  local tmp="$1"
  rm -rf "$tmp"
  mkdir -p "$tmp/docs/plans/active" "$tmp/docs/plans/completed" "$tmp/docs/generated"
  cat > "$tmp/docs/foundation.md" <<EOF
---
project: Test
type: foundation
status: draft
created: 2026-04-29
updated: 2026-04-29
owner: Test
depth: standard
---

# Foundation

## 5. Functional requirements

### R1. First requirement
### R2. Second requirement
### R3. Third requirement
EOF
  cat > "$tmp/docs/generated/plan-index.md" <<EOF
---
type: learning-index
generated: true
generator: en-learn
updated: 2026-04-29
total_entries: 0
---
EOF
  cat > "$tmp/docs/generated/learning-index.md" <<EOF
---
type: learning-index
generated: true
generator: en-learn
updated: 2026-04-29
total_entries: 0
---
EOF
}

run_lint() {
  local tmp="$1"
  pushd "$tmp" >/dev/null
  local out rc
  out=$("$LINT" --scope docs/ 2>&1)
  rc=$?
  popd >/dev/null
  echo "$out|||$rc"
}

# --- Test 1: Adding a new unit (U2) doesn't renumber U1 ---
TMP=$(mktemp -d)
setup_repo "$TMP"
cat > "$TMP/docs/plans/active/FR01-test.md" <<EOF
---
type: plan
fr_id: FR01
title: Test
status: active
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---

# FR01 — Test

### U1. First unit

### U2. Second unit (added later)
EOF
# Add to plan-index so we don't trip index-coverage
echo "- [\`FR01-test.md\`](../plans/active/FR01-test.md) — fixture" >> "$TMP/docs/generated/plan-index.md"

result=$(run_lint "$TMP")
output="${result%%|||*}"
rc="${result##*|||}"
if [ "$rc" -eq 0 ] || ! echo "$output" | grep -qF "id-stability"; then
  pass "adding U2 alongside U1 does not trigger id-stability (no renumber)"
else
  fail "appending U2 should not flag id-stability" "$(echo "$output" | grep id-stability)"
fi
rm -rf "$TMP"

# --- Test 2: FR collision is caught ---
TMP=$(mktemp -d)
setup_repo "$TMP"
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
### U1. First unit
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
### U1. Some unit
EOF
echo "- [\`FR42-a.md\`](../plans/active/FR42-a.md) — fixture" >> "$TMP/docs/generated/plan-index.md"
echo "- [\`FR42-b.md\`](../plans/completed/FR42-b.md) — fixture" >> "$TMP/docs/generated/plan-index.md"
result=$(run_lint "$TMP")
output="${result%%|||*}"
rc="${result##*|||}"
assert_ne "0" "$rc" "FR collision triggers non-zero exit"
assert_contains "$output" "id-stability.fr-collision" "FR collision rule fires"
rm -rf "$TMP"

# --- Test 3: FR format (FR1 instead of FR01) is flagged ---
TMP=$(mktemp -d)
setup_repo "$TMP"
cat > "$TMP/docs/plans/active/FR1-test.md" <<EOF
---
type: plan
fr_id: FR1
title: Bad format
status: active
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---
# FR1 — bad format
### U1. Unit
EOF
echo "- [\`FR1-test.md\`](../plans/active/FR1-test.md) — fixture" >> "$TMP/docs/generated/plan-index.md"
result=$(run_lint "$TMP")
output="${result%%|||*}"
assert_contains "$output" "id-stability.fr-format" "FR format rule fires on FR1 (not zero-padded)"
rm -rf "$TMP"

# --- Test 4: U-ID cited in plan but never declared → broken-u ---
TMP=$(mktemp -d)
setup_repo "$TMP"
cat > "$TMP/docs/plans/active/FR05-test.md" <<EOF
---
type: plan
fr_id: FR05
title: Broken U cite
status: active
location: active
created: 2026-04-29
covers_requirements: [R1]
requirements_pending: false
---
# FR05

### U1. Real unit

This unit depends on U99 (which doesn't exist).
EOF
echo "- [\`FR05-test.md\`](../plans/active/FR05-test.md) — fixture" >> "$TMP/docs/generated/plan-index.md"
result=$(run_lint "$TMP")
output="${result%%|||*}"
assert_contains "$output" "cross-link.broken-u" "broken U-ID cite fires cross-link.broken-u"
rm -rf "$TMP"

# --- Test 5: R-ID renumbering breaks downstream cites ---
# Simulates: foundation originally had R1, R2, R3 and a plan cites R3.
# Then someone "renumbers" foundation to R1, R2 only — the plan's cite to R3 is now broken.
TMP=$(mktemp -d)
setup_repo "$TMP"
# Foundation only has R1, R2 (R3 was "removed" by renumbering)
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

# Foundation

## 5. Functional requirements

### R1. First
### R2. Second
EOF
cat > "$TMP/docs/plans/active/FR03-test.md" <<EOF
---
type: plan
fr_id: FR03
title: Cites R3 (which was removed)
status: active
location: active
created: 2026-04-29
covers_requirements: [R3]
requirements_pending: false
---
# FR03

### U1. Implementation of R3

The plan covers R3 — but R3 was renumbered out of the foundation, breaking the cite.
EOF
echo "- [\`FR03-test.md\`](../plans/active/FR03-test.md) — fixture" >> "$TMP/docs/generated/plan-index.md"
result=$(run_lint "$TMP")
output="${result%%|||*}"
assert_contains "$output" "cross-link.broken-r" "renumbered/removed R-ID surfaces broken-r cite"
rm -rf "$TMP"

report
