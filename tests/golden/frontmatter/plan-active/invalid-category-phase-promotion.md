---
type: plan
plan_type: improvement
plan_id: EN99
title: A category-induced phase promotion the risk-only check could not see
status: open
location: active
created: 2026-08-29
shipped:
covers_requirements: []
requirements_pending: false
depth: standard
data_scale: small
peer_review_verdict: approve
peer_review_iterations: 1
peer_review_last_run: 2026-08-29
peer_review_plan_hash: 0000000000000000000000000000000000000000000000000000000000000000
peer_review_resolutions: []
---

# EN99 — category-induced phase promotion

Every unit is `risk: medium`, so a risk-only comparison sees a flat plan. But U2
carries a migration category, which `/en-build` classifies as P3, while U1 stays
in P2 — so U1 depends on a unit that runs in a later phase.

## Units

### U1. Depends on the migration

- **Goal:** Read what the migration produced.
- **Requirements covered:** none.
- **Dependencies:** U2.
- **Files:** `src/reader.ts`
- **Approach:** Read the migrated rows.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: reads a migrated row.
  - Edge case: reads an empty table.
- **Verification:** tests pass.

### U2. The migration itself

- **Goal:** Move the rows.
- **Requirements covered:** none.
- **Dependencies:** none.
- **Files:** `migrations/001.sql`
- **Approach:** Move rows to the new shape.
- **Risk:** medium
- **Category:** migration
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: rows land in the new shape.
  - Edge case: an empty table migrates cleanly.
- **Verification:** tests pass.
