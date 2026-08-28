---
expect_type: none
expect_path: none
gate_condition_failed: recoverable-from-code
---
The extract-json helper scans for the first balanced top-level object, tracking
depth and honouring string escapes.

Rejected by the capture gate before routing: this describes how the code works,
which a reader recovers by reading it. The router never sees this candidate.
