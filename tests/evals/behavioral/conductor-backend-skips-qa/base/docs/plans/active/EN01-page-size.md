---
type: plan
plan_type: feature
plan_id: EN01
title: Cap the page size at 100
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

# EN01: Cap the page size at 100

## Context

`clampPageSize` lets a caller ask for more than 100 rows. This service is a JSON API with no web pages.

## Implementation units

### U1. Cap the page size at 100

- **Goal:** Cap the page size at 100
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `app/api/limits.js` (modify)
  - `test/limits.test.js` (modify)
- **Approach:** Cap the value at 100 in `clampPageSize`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test expectation:** a request for 500 returns 100
- **Test scenarios:**
  - a request for 500 returns 100
  - a request for 50 returns 50
- **Verification:** `node --test` passes
