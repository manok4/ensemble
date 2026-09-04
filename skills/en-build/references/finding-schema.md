# Finding schema

Canonical JSON shape returned by every reviewer agent and every Outside Voice peer pass. The host's parsing layer assumes this exact shape.

## Schema

```json
{
  "verdict": "approve | revise | reject",
  "peer_mode": "cross-agent | single-agent-fallback",
  "summary": "<2-3 sentence overall assessment>",
  "findings": [
    {
      "finding_id": "<stable id; peer-supplied or host-minted as `<iteration>-<index>` (e.g. `1-3`)>",
      "severity": "P0 | P1 | P2 | P3",
      "confidence": 1,
      "title": "<short title>",
      "location": "<file:line | section name | 'global'>",
      "why_it_matters": "<1-2 sentence rationale>",
      "suggested_fix": "<concrete change the host could apply — describe, don't apply>",
      "autofix_class": "safe_auto | gated_auto | manual | advisory",
      "u_id": "<U<N> if related to a plan unit, else null>",
      "covers_requirement": "<R<N> if related, else null>"
    }
  ],
  "coverage": {
    "reviewed": "<what the reviewer actually examined>",
    "not_reviewed": "<anything skipped, truncated, or run short on; empty string if none>"
  }
}
```

## Field semantics

| Field | Required | Notes |
|---|---|---|
| `verdict` | yes | Top-level decision. `approve` = nothing material; `revise` = walk findings; `reject` = pause and surface to user. |
| `peer_mode` | yes when peer-call | Echo of the mode the host passed in (`cross-agent` or `single-agent-fallback`). Reviewer agents that aren't peer calls omit this field. |
| `summary` | yes | 2–3 sentences. The host renders this in progress reports verbatim. |
| `findings` | yes | Array; can be empty when verdict = approve. |
| `findings[].severity` | yes | `P0`–`P3` as defined in `references/peer-contract.md`. |
| `findings[].confidence` | yes | Integer 1–10. <5 should be suppressed unless severity is P0. |
| `findings[].title` | yes | Short title; appears in lists. |
| `findings[].location` | yes | `<file>:<line>` for code; `<section>` for docs; `global` for cross-file. |
| `findings[].why_it_matters` | yes | 1–2 sentence rationale. |
| `findings[].suggested_fix` | yes | Concrete description of what the host should do. **Description, not action.** |
| `findings[].autofix_class` | optional | One of the four classes in `references/peer-contract.md`, when the reviewer is confident in the routing; otherwise the host classifies. |
| `findings[].u_id` | optional | Plan unit ID this finding relates to (e.g., `U3`). Used by `en-build` per-unit dispatch. |
| `findings[].covers_requirement` | optional | Foundation requirement ID this finding relates to (e.g., `R7`). Used by traceability lints. |
| `coverage` | recommended | What the reviewer actually examined, and what it did not. A large artifact can exhaust a single-shot peer's attention silently; without this the host cannot tell a thorough `approve` from an exhausted one. Absent → the host treats coverage as unknown, never as complete. |
| `findings[].finding_id` | required | `<pass>-<index>` (e.g. `1-3` = third finding of pass 1). Used by `/en-plan`'s resolution log (`peer_review_resolutions:`). **The peer must reuse the original id when re-raising a finding from `## Previous review context`** — a re-minted id breaks same-finding suppression, which is the mechanism that stops a capped loop from re-litigating settled points. The host still mints one if absent, but cannot recover the linkage. |

## Validation rules the host applies

1. **Recover, then parse, then retry — in that order.** Run the raw response through the ensemble-extract-json helper first: it returns the first *balanced* top-level `{...}`, so markdown fences and prose on either side are recovered locally instead of costing a round trip. It is string-aware (braces inside string literals do not move the depth counter) and validates with `jq` when available, so a balanced-but-invalid body is reported as a failure rather than passed on. Parse what it returns. Only if recovery **or** parsing fails, retry once with a "respond with valid JSON only" suffix; on second failure, log and skip. Callers that invoke a peer through the ensemble-peer-invoke helper get recovery applied to the out-file automatically and need do nothing; an unrecoverable response is left byte-for-byte intact so the retry is never pre-empted.
2. `verdict` must be one of the three enum values.
3. Every `severity` must be in `{P0, P1, P2, P3}`.
4. `confidence` must be an integer 1–10.
5. `coverage.not_reviewed` non-empty → surface it in the run report. Never silently present a partial review as a complete one.
6. Findings with `confidence < 5` and `severity != P0` are suppressed silently (per the §6.4 invariant: "Confidence ≥ 7 surfaces in main report; 5–6 surfaces with caveat; <5 suppressed unless severity would be P0").

## Aggregated envelopes

When `/en-review` runs host personas alongside the peer, the envelope it emits keeps this shape and gains `personas[]`, `peer_decision` (defined in `references/peer-contract.md`) and `reconciliation[]`. Those fields, the bucket semantics and the partition invariant are defined in the persona-dispatch reference that `/en-review` carries; nothing outside `/en-review` produces or parses them.
