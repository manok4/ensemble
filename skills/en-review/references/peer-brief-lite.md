# Peer review brief — lite

The brief for a `/en-review --lite` run: a quick fix the user wants read once with
care, not studied. The full brief is `references/peer-brief.md`; this one keeps the
dimensions a quick fix can fail on and drops the rest. The wire format both ends
share is `references/peer-contract.md`. The brief is handed out only when the risk
gate in `references/diff-signal-detection.md` passed, so a change touching auth,
payments, schema, secrets or bulk data never arrives here.

## What the peer is asked

This is a lite review of a small, low-risk change. Read the diff once, carefully,
and report only what is wrong, not what could be nicer. Do not comment on test
quality, maintainability or performance unless the diff plainly breaks a test or
adds an obvious hot-path cost. An empty findings list with `coverage` naming the
two dimensions below is a valid, expected result.

### correctness

| Category | Examples |
|---|---|
| **Logic errors** | Wrong condition, swapped operands, inverted boolean, missing case |
| **Edge cases** | Empty input, boundary values, off-by-one in loop bounds or slices |
| **Error propagation** | Swallowed exception, ignored return value, missing cleanup |
| **Regression risk** | The change alters behaviour a caller, a test or a persisted value depends on |
| **Incomplete fix** | The bug is fixed at one site and the same pattern remains at a sibling site in the diff |

### standards (visible in the diff)

| Category | Examples |
|---|---|
| **Naming and placement** | New identifier or file breaks the convention its neighbours follow |
| **Commit message** | Not `<type>(<scope>): <subject>`, or the subject does not describe the change |
| **Path conventions** | Absolute or machine-specific paths in artifacts |

## Where a finding points

Use `<file>:<line>` for code, or `global` when it is about the change as a whole.

## What this skill does with the findings

Routing is the same as for the full brief: severity, confidence and autofix class per
`references/severity.md`; sub-threshold findings file per
`references/review-confidence-gating.md`. The effort tier resolves `low` per
`references/peer-model-policy.md` unless its `high` rung fired, in which case this
brief is not used at all.
