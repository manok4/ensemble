---
type: plan
plan_type: improvement
plan_id: FR45
title: Phase-invariant violator
status: open
location: active
created: 2026-04-29
covers_requirements: []
requirements_pending: true
peer_review_resolutions: []
depth: standard
---

# FR45 — Phase invariant violator

### U1. Drop legacy table

- **Goal:** drop the legacy_users table
- **Risk:** destructive
- **Category:** drop
- **Gated:** false
- **Dependencies:** none
- **Files:** migrations/0001_drop.sql
- **Approach:** DROP TABLE legacy_users

### U2. Add docstring referring to dropped table

- **Goal:** documentation update
- **Risk:** low
- **Category:** observability
- **Gated:** false
- **Dependencies:** U1
- **Files:** src/foo.py
- **Approach:** add a comment about the dropped table
