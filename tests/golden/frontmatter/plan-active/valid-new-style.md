---
type: plan
plan_type: feature
plan_id: FR43
title: New-style test plan
status: open
location: active
created: 2026-04-29
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design:
peer_review_verdict: approve
peer_review_iterations: 1
peer_review_last_run: 2026-04-29
peer_review_plan_hash: abc123def456
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P2
    title: Add edge-case test
    status: applied
depth: standard
data_scale: small
---

# FR43 — New-style test plan

Body.

## Implementation units

### U1. Add helper

- **Goal:** introduce a small helper
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Dependencies:** none
- **Files:** src/helper.ts
- **Approach:** add a function

### U2. Use helper

- **Goal:** wire helper into the main path
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Dependencies:** U1
- **Files:** src/main.ts
- **Approach:** call the helper
