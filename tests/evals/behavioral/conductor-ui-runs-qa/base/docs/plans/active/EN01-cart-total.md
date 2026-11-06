---
type: plan
plan_type: feature
plan_id: EN01
title: Count quantity in the cart total
status: open
location: active
created: 2026-11-06
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

# EN01: Count quantity in the cart total

## Context

The cart page shows a total that ignores item quantity. `public/index.html` renders whatever `src/hooks/useCart.js` returns.

## Implementation units

### U1. Count quantity in the cart total

- **Goal:** Count quantity in the cart total
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `src/hooks/useCart.js` (modify)
  - `test/useCart.test.js` (modify)
- **Approach:** Multiply each price by its quantity in `cartTotal`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test expectation:** two of one item totals twice its price
- **Test scenarios:**
  - two of one item totals twice its price
  - an empty cart still totals zero
- **Verification:** `node --test` passes
