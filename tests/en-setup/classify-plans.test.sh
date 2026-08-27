#!/usr/bin/env bash
# Tests for bin/ensemble-classify-plans — partitions docs/plans/ into
# conforming vs non-conforming for /en-setup State 2 step 2.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-classify-plans"

CLASSIFY="$REPO_ROOT/shared/bin/ensemble-classify-plans"
[ -x "$CLASSIFY" ] || { fail "missing or not executable: $CLASSIFY"; report; exit 1; }

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

# --- 1. Empty / missing plans/ → empty buckets ---
out=$(bash "$CLASSIFY" "$TMP/nonexistent" 2>&1)
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["conforming"] == [] and d["non_conforming"] == [] and d["tech_debt"] is None
' 2>/dev/null; then
  pass "missing plans/ returns empty buckets"
else
  fail "missing plans/ output unexpected" "$out"
fi

# --- 2. Conforming plan recognized ---
mkdir -p "$TMP/c2/docs/plans/active"
cat > "$TMP/c2/docs/plans/active/EN01-feature_test.md" <<'EOF'
---
type: plan
plan_type: feature
plan_id: EN01
title: Test plan
status: open
location: active
created: 2026-05-04
covers_requirements: []
requirements_pending: true
---

# EN01 — Test plan
EOF
cd "$TMP/c2" && out=$(bash "$CLASSIFY" docs/plans 2>&1) && cd - >/dev/null
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert "docs/plans/active/EN01-feature_test.md" in d["conforming"], d
assert d["non_conforming"] == [], d
' 2>/dev/null; then
  pass "conforming plan classified as conforming"
else
  fail "conforming plan misclassified" "$out"
fi

# --- 3. Non-conforming plan (no frontmatter) ---
mkdir -p "$TMP/c3/docs/plans"
cat > "$TMP/c3/docs/plans/legacy-roadmap.md" <<'EOF'
# Project Roadmap

- Q1: ship auth
- Q2: scale to 10k users
EOF
cd "$TMP/c3" && out=$(bash "$CLASSIFY" docs/plans 2>&1) && cd - >/dev/null
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["conforming"] == [], d
assert "docs/plans/legacy-roadmap.md" in d["non_conforming"], d
' 2>/dev/null; then
  pass "non-conforming plan classified correctly"
else
  fail "non-conforming plan misclassified" "$out"
fi

# --- 4. Non-conforming plan with partial frontmatter ---
mkdir -p "$TMP/c4/docs/plans"
cat > "$TMP/c4/docs/plans/old-plan.md" <<'EOF'
---
title: Old plan
date: 2025-08-15
---

# Old plan from a previous tool
EOF
cd "$TMP/c4" && out=$(bash "$CLASSIFY" docs/plans 2>&1) && cd - >/dev/null
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert "docs/plans/old-plan.md" in d["non_conforming"], d
' 2>/dev/null; then
  pass "plan with partial frontmatter classified as non-conforming"
else
  fail "partial frontmatter misclassified" "$out"
fi

# --- 5. Tech-debt-tracker recognized separately ---
mkdir -p "$TMP/c5/docs/plans"
cat > "$TMP/c5/docs/plans/tech-debt-tracker.md" <<'EOF'
---
type: tech-debt-tracker
generated: false
---
# TD
EOF
cd "$TMP/c5" && out=$(bash "$CLASSIFY" docs/plans 2>&1) && cd - >/dev/null
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert d["tech_debt"] == "docs/plans/tech-debt-tracker.md", d
assert "docs/plans/tech-debt-tracker.md" not in d["conforming"], d
assert "docs/plans/tech-debt-tracker.md" not in d["non_conforming"], d
' 2>/dev/null; then
  pass "tech-debt-tracker.md recognized as separate artifact"
else
  fail "tech-debt-tracker misclassified" "$out"
fi

# --- 6. Mixed bag: conforming + non-conforming + tech debt + unknown subdir ---
mkdir -p "$TMP/c6/docs/plans/active" "$TMP/c6/docs/plans/completed" "$TMP/c6/docs/plans/old-system"
cat > "$TMP/c6/docs/plans/active/EN01-feature_a.md" <<'EOF'
---
type: plan
plan_type: feature
plan_id: EN01
title: A
status: open
location: active
created: 2026-05-04
covers_requirements: []
requirements_pending: true
---
EOF
cat > "$TMP/c6/docs/plans/legacy.md" <<'EOF'
# Legacy
EOF
cat > "$TMP/c6/docs/plans/tech-debt-tracker.md" <<'EOF'
---
type: tech-debt-tracker
---
EOF
cd "$TMP/c6" && out=$(bash "$CLASSIFY" docs/plans 2>&1) && cd - >/dev/null
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert len(d["conforming"]) == 1, d
assert len(d["non_conforming"]) == 1, d
assert "docs/plans/old-system" in d["subdirs"], d
assert d["tech_debt"] == "docs/plans/tech-debt-tracker.md", d
' 2>/dev/null; then
  pass "mixed-bag classification handles all four buckets"
else
  fail "mixed-bag classification unexpected" "$out"
fi

# --- 7. Plans inside completed/ — also classified ---
mkdir -p "$TMP/c7/docs/plans/completed"
cat > "$TMP/c7/docs/plans/completed/legacy-finished.md" <<'EOF'
# A finished plan from the old system
EOF
cd "$TMP/c7" && out=$(bash "$CLASSIFY" docs/plans 2>&1) && cd - >/dev/null
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert "docs/plans/completed/legacy-finished.md" in d["non_conforming"], d
' 2>/dev/null; then
  pass "plans under completed/ classified too"
else
  fail "completed/ plans not classified" "$out"
fi

# --- 8. Plan with most fields but missing covers_requirements/requirements_pending
#         is non-conforming (matches ensemble-lint's required-field set) ---
mkdir -p "$TMP/c8/docs/plans/active"
cat > "$TMP/c8/docs/plans/active/EN02-feature_partial.md" <<'EOF'
---
type: plan
plan_type: feature
plan_id: EN02
title: Partial
status: open
location: active
created: 2026-05-04
---

# EN02 — partial migration
EOF
cd "$TMP/c8" && out=$(bash "$CLASSIFY" docs/plans 2>&1) && cd - >/dev/null
if echo "$out" | python3 -c '
import sys, json
d = json.loads(sys.stdin.read())
assert "docs/plans/active/EN02-feature_partial.md" in d["non_conforming"], d
assert "docs/plans/active/EN02-feature_partial.md" not in d["conforming"], d
' 2>/dev/null; then
  pass "plan missing covers_requirements/requirements_pending classified non-conforming"
else
  fail "partial-fields plan was misclassified as conforming" "$out"
fi

report
