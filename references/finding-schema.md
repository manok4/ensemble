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
      "confidence": 75,
      "first_evidence": "<verbatim motivating line with file:line — REQUIRED at confidence 75/100>",
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
| `findings[].severity` | yes | See `references/severity.md`. Orthogonal to `confidence`. |
| `findings[].confidence` | yes | One of 5 discrete anchors `{0, 25, 50, 75, 100}` (see Confidence anchors below). Not a free 1–10 scale. |
| `findings[].first_evidence` | yes at anchor 75/100 | The verbatim motivating line with `file:line`. **A finding at anchor 75 or 100 without `first_evidence` is demoted to 50.** Optional below 75. |
| `findings[].title` | yes | Short title; appears in lists. |
| `findings[].location` | yes | `<file>:<line>` for code; `<section>` for docs; `global` for cross-file. |
| `findings[].why_it_matters` | yes | 1–2 sentence rationale. |
| `findings[].suggested_fix` | yes | Concrete description of what the host should do. **Description, not action.** |
| `findings[].autofix_class` | optional | When the reviewer is confident in the routing; otherwise host classifies. See `references/severity.md`. |
| `findings[].u_id` | optional | Plan unit ID this finding relates to (e.g., `U3`). Used by `en-build` per-unit dispatch. |
| `findings[].covers_requirement` | optional | Foundation requirement ID this finding relates to (e.g., `R7`). Used by traceability lints. |
| `findings[].finding_id` | recommended | Stable id used by `/en-plan`'s resolution log (`peer_review_resolutions:`). Peer can supply one; if absent, the host mints `<iteration>-<index>` (e.g. `1-3` = third finding from iteration 1). Required for re-review iterations to track applied/deferred/disagreed status across passes. |

## Confidence anchors

`confidence` is one of **5 discrete anchors**, each tied to a behavioral criterion the model can honestly apply — not a continuous 1–10 scale (which invites false precision):

| Anchor | Name | Criterion | Report decision |
|---|---|---|---|
| `0` | Not confident | False positive or pre-existing | suppress silently |
| `25` | Somewhat | Might be real but unverified | suppress silently |
| `50` | Moderately | Verified real but nitpick / narrow edge / minimal impact | suppressed from primary findings (filed as TD) UNLESS P0 |
| `75` | Highly | Will affect users/callers in normal usage; **requires `first_evidence`** | actionable |
| `100` | Certain | Verifiable from code alone (compile error, type mismatch, definitive logic bug, quoted standards violation) | actionable |

**Quote-the-line gate.** A finding at anchor `75` or `100` MUST carry a non-empty `first_evidence` (the verbatim motivating line + `file:line`). A 75/100 finding missing `first_evidence` is **demoted to 50**. This is the primary false-positive control.

## Validation rules the host applies

1. JSON must parse. If not, retry once with a "respond with valid JSON only" suffix; on second failure, log and skip.
2. `verdict` must be one of the three enum values.
3. Every `severity` must be in `{P0, P1, P2, P3}`.
4. `confidence` must be one of `{0, 25, 50, 75, 100}`.
5. Apply the quote-the-line gate: demote any 75/100 finding lacking `first_evidence` to 50.
6. The confidence gate suppresses findings below anchor 75 from primary output — **EXCEPT P0 at anchor 50+** (critical-but-uncertain must never be silently dropped). Suppressed-but-real findings (anchor 50) are filed as TD entries, not discarded.

## Multi-persona synthesis

When `en-review` runs multiple persona agents and aggregates their findings:

- Findings are merged, deduped (by location + title similarity), and re-classified.
- **Cross-reviewer corroboration:** when ≥2 independent reviewers flag the same fingerprint, promote one anchor (`50→75→100`). Promotion never bypasses the quote-the-line gate (a promoted 75/100 still needs `first_evidence`). The `fast-pass` pseudo-reviewer is the orchestrator's own read, not independent — it never counts toward promotion.
- Same location flagged for incompatible reasons → leave both, mark `conflict: true` for user judgment.
- The synthesis layer emits a single envelope with the same shape, plus a `personas` field listing which personas contributed:

```json
{
  "verdict": "...",
  "summary": "...",
  "personas": ["correctness", "testing", "security"],
  "findings": [...]
}
```

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
