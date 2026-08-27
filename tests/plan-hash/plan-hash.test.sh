#!/usr/bin/env bash
# tests/plan-hash/plan-hash.test.sh
#
# peer_review_plan_hash must move when an immutable plan input changes and stay
# put when a mutable one does. /en-build refuses to advance past a phase
# boundary on mismatch, so a hash that moves for the wrong reason blocks a
# legitimate build and reports it as an external edit.
#
# Covered:   per-unit Goal, Files, Approach, Risk, Category, Gated, Dependencies
#            plus plan-level depth and data_scale.
# Excluded:  iteration log, per-unit status, peer_review_resolutions.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="plan hash"

HASH="$REPO_ROOT/bin/ensemble-plan-hash"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

write_plan() {
  cat > "$1" <<'PLAN'
---
type: plan
plan_id: FR90
status: open
location: active
peer_review_resolutions: []
depth: standard
data_scale: small
---

# FR90 — fixture

## Implementation units

### U1. First unit

- **Goal:** do the thing
- **Dependencies:** none
- **Files:** src/a.ts
- **Approach:** straightforward
- **Risk:** medium
- **Category:** feature
- **Gated:** false
- **Verification:** tests pass

### U2. Second unit

- **Goal:** do the other thing
- **Dependencies:** U1
- **Files:** src/b.ts
- **Approach:** also straightforward
- **Risk:** low
- **Category:** other
- **Gated:** false
- **Verification:** tests pass

## Decisions, assumptions & risks

- **Risk:** something could go wrong — **Mitigation:** a guard

## Iteration log

> - 2026-01-01 (initial): plan v0.
PLAN
}

h() { bash "$HASH" "$1"; }

BASE="$WORK/base.md"; write_plan "$BASE"
BASELINE="$(h "$BASE")"
[ -n "$BASELINE" ] && pass "hash is non-empty" || fail "hash is non-empty"
assert_eq "$BASELINE" "$(h "$BASE")" "hash is deterministic across runs"

# --- mutable fields must NOT move the hash ---
V="$WORK/log.md"; write_plan "$V"
printf '> - 2026-02-02 (iteration 1): peer review, verdict revise.\n' >> "$V"
assert_eq "$BASELINE" "$(h "$V")" "appending to the iteration log does not move the hash"

V="$WORK/res.md"; write_plan "$V"
perl -0pi -e 's/peer_review_resolutions: \[\]/peer_review_resolutions:\n  - finding_id: "1-1"\n    severity: P1\n    status: applied/' "$V"
assert_eq "$BASELINE" "$(h "$V")" "adding a peer_review_resolutions entry does not move the hash"

V="$WORK/status.md"; write_plan "$V"
perl -0pi -e 's/- \*\*Verification:\*\* tests pass/- **Status:** complete\n- **Verification:** tests pass/' "$V"
assert_eq "$BASELINE" "$(h "$V")" "adding per-unit status does not move the hash"

V="$WORK/reflow.md"; write_plan "$V"
perl -0pi -e 's/- \*\*Approach:\*\* straightforward/- **Approach:**    straightforward/' "$V"
assert_eq "$BASELINE" "$(h "$V")" "whitespace reflow of a hashed field does not move the hash"

# The plan template prescribes "- **Risk:**" bullets under a later level-2
# heading; those must not be absorbed into the final unit.
V="$WORK/riskprose.md"; write_plan "$V"
perl -0pi -e 's/- \*\*Risk:\*\* something could go wrong/- **Risk:** a totally different worry/' "$V"
assert_eq "$BASELINE" "$(h "$V")" "a Risk bullet in prose after '## ' does not move the hash"

# --- immutable fields MUST move the hash ---
V="$WORK/approach.md"; write_plan "$V"
perl -0pi -e 's/- \*\*Approach:\*\* straightforward/- **Approach:** rewritten entirely/' "$V"
assert_ne "$BASELINE" "$(h "$V")" "changing a unit Approach moves the hash"

V="$WORK/risk.md"; write_plan "$V"
perl -0pi -e 's/- \*\*Risk:\*\* medium/- **Risk:** high/' "$V"
assert_ne "$BASELINE" "$(h "$V")" "changing a unit Risk moves the hash"

V="$WORK/gated.md"; write_plan "$V"
perl -0pi -e 's/- \*\*Gated:\*\* false\n- \*\*Verification:\*\* tests pass\n\n### U2/- **Gated:** true\n- **Verification:** tests pass\n\n### U2/' "$V"
assert_ne "$BASELINE" "$(h "$V")" "changing a unit Gated flag moves the hash"

V="$WORK/files.md"; write_plan "$V"
perl -0pi -e 's|src/a\.ts|src/a.ts, src/c.ts|' "$V"
assert_ne "$BASELINE" "$(h "$V")" "changing a unit Files list moves the hash"

V="$WORK/deps.md"; write_plan "$V"
perl -0pi -e 's/- \*\*Dependencies:\*\* U1/- **Dependencies:** none/' "$V"
assert_ne "$BASELINE" "$(h "$V")" "changing a unit Dependencies moves the hash"

V="$WORK/depth.md"; write_plan "$V"
perl -0pi -e 's/^depth: standard/depth: deep/m' "$V"
assert_ne "$BASELINE" "$(h "$V")" "changing plan depth moves the hash"

V="$WORK/scale.md"; write_plan "$V"
perl -0pi -e 's/^data_scale: small/data_scale: large/m' "$V"
assert_ne "$BASELINE" "$(h "$V")" "changing data_scale moves the hash"

V="$WORK/newunit.md"; write_plan "$V"
printf '\n### U3. Third unit\n\n- **Goal:** more\n- **Dependencies:** none\n- **Files:** src/c.ts\n- **Approach:** ok\n- **Risk:** low\n- **Category:** other\n- **Gated:** false\n' >> "$V"
assert_ne "$BASELINE" "$(h "$V")" "adding a unit moves the hash"

# --- interface ---
out=$(bash "$HASH" "$WORK/does-not-exist.md" 2>&1); rc=$?
assert_ne 0 "$rc" "a missing plan exits non-zero"
assert_contains "$out" "no such plan" "a missing plan says so"

out=$(bash "$HASH" 2>&1); rc=$?
assert_ne 0 "$rc" "no argument exits non-zero"

canon=$(bash "$HASH" --canon "$BASE")
assert_contains "$canon" "U1|" "--canon shows the canonical form"
assert_contains "$canon" "standard|small" "--canon ends with the plan-level line"

# The real plan must hash, and match what its frontmatter records.
REAL="$REPO_ROOT/docs/plans/active/EN12-improvement_self-contained-skills.md"
if [ -f "$REAL" ]; then
  recorded=$(awk -F': ' '/^peer_review_plan_hash:/{print $2; exit}' "$REAL")
  assert_eq "$(h "$REAL")" "$recorded" "EN12's recorded hash matches the helper"
fi

report
