---
type: plan
plan_type: feature
plan_id: EN01
title: Rename users.fullname without downtime
status: open
location: active
created: 2026-11-03
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design:
peer_review_verdict:
peer_review_iterations: 0
peer_review_last_run:
peer_review_plan_hash:
peer_review_resolutions: []
depth: standard
data_scale: small
---

# EN01: Rename users.fullname without downtime

## Context

Rename a column.

## Implementation units

### U1. Expand: add display_name

- **Goal:** add the column
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `db/migrations/002_add_display_name.sql` (create)
- **Approach:** add a nullable column.
- **Risk:** medium
- **Category:** migration-additive
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none: schema only
- **Verification:** migration applies

### U2. Dual-write both columns

- **Goal:** write both
- **Requirements covered:** none
- **Dependencies:** U1
- **Files:**
  - `src/users.js` (create)
- **Approach:** write both columns.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none: covered by U3's check
- **Verification:** both columns written

### U3. Drop the old column

- **Goal:** contract
- **Requirements covered:** none
- **Dependencies:** U2
- **Files:**
  - `db/migrations/003_drop_fullname.sql` (create)
- **Approach:** drop fullname.
- **Risk:** destructive
- **Category:** drop
- **Reversibility:** irreversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none: schema only
- **Verification:** column gone
