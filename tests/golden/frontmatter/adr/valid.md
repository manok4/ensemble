# Declare each skill's files rather than inferring them by walking references

Inferring a skill's file set by walking its references produced five distinct
classes of false edge, each found only by deleting something and seeing what
broke.

## Decision

Every file a skill reads is listed in its `requires:` block.

## Rejected alternatives

A reachability walker. Rejected after the excess it reported moved 98 → 54 → 14
across three attempts without ever reaching zero.

## Invariants this creates

- Every file a skill reads appears in its `requires:` block.
- A declared file naming an undeclared one is a hole, not an omission.
