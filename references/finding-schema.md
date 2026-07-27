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
  ]
}
```

## Field semantics

| Field | Required | Notes |
|---|---|---|
| `verdict` | yes | Top-level decision. `approve` = nothing material; `revise` = walk findings; `reject` = pause and surface to user. |
| `peer_mode` | yes when peer-call | Echo of the mode the host passed in (`cross-agent` or `single-agent-fallback`). Reviewer agents that aren't peer calls omit this field. |
| `summary` | yes | 2–3 sentences. The host renders this in progress reports verbatim. |
| `findings` | yes | Array; can be empty when verdict = approve. |
| `findings[].severity` | yes | See `references/severity.md`. |
| `findings[].confidence` | yes | Integer 1–10. <5 should be suppressed unless severity is P0. |
| `findings[].title` | yes | Short title; appears in lists. |
| `findings[].location` | yes | `<file>:<line>` for code; `<section>` for docs; `global` for cross-file. |
| `findings[].why_it_matters` | yes | 1–2 sentence rationale. |
| `findings[].suggested_fix` | yes | Concrete description of what the host should do. **Description, not action.** |
| `findings[].autofix_class` | optional | When the reviewer is confident in the routing; otherwise host classifies. See `references/severity.md`. |
| `findings[].u_id` | optional | Plan unit ID this finding relates to (e.g., `U3`). Used by `en-build` per-unit dispatch. |
| `findings[].covers_requirement` | optional | Foundation requirement ID this finding relates to (e.g., `R7`). Used by traceability lints. |
| `findings[].finding_id` | recommended | Stable id used by `/en-plan`'s resolution log (`peer_review_resolutions:`). Peer can supply one; if absent, the host mints `<iteration>-<index>` (e.g. `1-3` = third finding from iteration 1). Required for re-review iterations to track applied/deferred/disagreed status across passes. |

## Validation rules the host applies

1. JSON must parse. If not, retry once with a "respond with valid JSON only" suffix; on second failure, log and skip.
2. `verdict` must be one of the three enum values.
3. Every `severity` must be in `{P0, P1, P2, P3}`.
4. `confidence` must be an integer 1–10.
5. Findings with `confidence < 5` and `severity != P0` are suppressed silently (per the §6.4 invariant: "Confidence ≥ 7 surfaces in main report; 5–6 surfaces with caveat; <5 suppressed unless severity would be P0").

## Multi-persona synthesis

When `en-review` runs multiple persona agents and aggregates their findings:

- Findings are merged, deduped (by location + title similarity), and re-classified.
- Same finding from two personas → boost confidence (+1, capped at 10).
- The synthesis layer emits a single envelope with the same shape, plus a `personas` field listing which personas contributed:

```json
{
  "verdict": "...",
  "summary": "...",
  "personas": ["correctness", "testing", "security"],
  "findings": [...]
}
```

## Two-source reconciliation (EN11)

When the cross-agent peer runs alongside the host personas (the `/en-review` default), every raw finding carries a `source`, and the two sets reconcile into **reconciliation records**. The full algorithm, including the conflict-before-corroboration ordering and the partition invariant, lives in `references/persona-dispatch.md`; this file defines the shapes.

| Field | Required | Meaning |
|---|---|---|
| `findings[].source` | yes when a peer ran | `host` or `peer`. Which side produced this raw finding. Omit when no peer ran (all findings are host). |
| `reconciliation[].bucket` | yes | `corroborated` \| `peer-only` \| `host-only` \| `conflicting` |
| `reconciliation[].sources` | yes | Array of contributing sides. `["host","peer"]` for corroborated and conflicting; a single-element array otherwise. **An array, not the scalar `source`** — a corroborated record represents both sides and a scalar cannot express that. |
| `reconciliation[].canonical` | yes | The finding object presented to the user. Selected highest-severity, then highest-confidence, then host-source. |
| `reconciliation[].contributing` | yes | `[{source, finding_id}]` for every raw finding folded into this record. Summing these across all records MUST equal the raw finding count (the partition invariant). |
| `reconciliation[].confidence` | yes | Post-boost confidence: `+2` for cross-source corroboration, `+1` for same-source overlap, capped at 10. |
| `reconciliation[].conflict` | yes | `true` only for the `conflicting` bucket. Conflicting records are **never auto-applied**. |

```json
{
  "verdict": "revise",
  "summary": "...",
  "personas": ["correctness", "testing"],
  "peer_decision": {"peer": "on", "reason": "default-on", "peer_mode": "cross-agent",
                    "effort": "medium", "model_alias": null},
  "findings": [ { "source": "peer", "finding_id": "p-1", "severity": "P1", "...": "..." } ],
  "reconciliation": [
    {"bucket": "corroborated", "sources": ["host", "peer"],
     "canonical": { "severity": "P1", "location": "src/auth.ts:42", "...": "..." },
     "contributing": [{"source": "host", "finding_id": "c-2"},
                      {"source": "peer", "finding_id": "p-1"}],
     "confidence": 10, "conflict": false}
  ]
}
```

`peer_decision` is defined once in `references/peer-model-policy.md` section (e); the envelope echoes it verbatim so callers never re-derive it.

## Examples

### Clean review

```json
{
  "verdict": "approve",
  "peer_mode": "cross-agent",
  "summary": "Plan is well-scoped, U-IDs are consistent, and the test strategy is appropriate. No findings.",
  "findings": []
}
```

### Substantive findings

```json
{
  "verdict": "revise",
  "peer_mode": "single-agent-fallback",
  "summary": "Two correctness concerns and one missing test scenario. Auth handling is solid; the issues are in the refresh-token path.",
  "findings": [
    {
      "severity": "P1",
      "confidence": 9,
      "title": "Refresh token race when two requests arrive within the rotation window",
      "location": "src/auth/refresh.ts:42",
      "why_it_matters": "Rotation invalidates the prior token; concurrent refresh produces a 401 for the second caller.",
      "suggested_fix": "Serialize refresh per-user with a lock or use a single-flight cache keyed on user_id.",
      "autofix_class": "manual",
      "u_id": "U4"
    },
    {
      "severity": "P2",
      "confidence": 7,
      "title": "Missing test for expired-token path",
      "location": "tests/auth/refresh.test.ts",
      "why_it_matters": "Coverage gap on the most-likely production path.",
      "suggested_fix": "Add a test that simulates a clock skew of 6 minutes against a 5-minute-TTL token.",
      "autofix_class": "manual",
      "u_id": "U4"
    }
  ]
}
```
