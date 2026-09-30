# `/en-review` confidence-gating policy

How sub-threshold findings get filtered and routed.

## The threshold

| Source | Default | Override |
|---|---|---|
| `~/.ensemble/config.json` → `review.confidence_threshold` | `7` | Per-project: `<repo>/.ensemble/config.local.yaml` |

Range: `1` (lowest signal) to `10` (highest). Threshold of `7` means findings rated 7+ surface; 1–6 get filtered.

Why 7 by default: matches industry guidance that AI reviewers should aim for high precision (3 important comments beat 15 nits). A confidence of 7 means the reviewer is reasonably sure this matters. Below that, the noise-to-signal ratio degrades.

## What gets filtered

Each persona-agent finding includes:

```json
{
  "severity": "P1",
  "confidence": 5,        // ← gating field, range 1-10
  "title": "...",
  "location": "src/auth.ts:42",
  ...
}
```

A finding is filtered when:
- `confidence < threshold` AND
- `severity` is **not** `P0` (P0 always surfaces regardless of confidence — security/correctness blockers cannot be silently demoted).

P0 + low confidence is a real case (the reviewer suspects something serious but isn't sure). These surface with a `low_confidence: true` flag so the user knows to verify before acting.

## What happens to filtered findings

**They are reported, never filed.** In every mode, `interactive`, `headless` and `report-only` alike, a filtered finding goes into the envelope's `sub_threshold_findings[]` and the markdown summary's "Below threshold" list, and nowhere else. The threshold exists to filter noise; appending the filtered noise to an append-only tracker undoes the filter.

```json
{
  "verdict": "approve | revise | reject",
  "findings": [...],                  // ≥ threshold
  "sub_threshold_findings": [...],    // < threshold; reported only
  ...
}
```

A sub-threshold finding leaves the side list in exactly two cases:

- **The host verifies it.** The host reads the code and can name the `file:line` where the claim holds. Verification re-grades the finding's confidence to the threshold, and it then routes through the `references/severity.md` matrix like any other, which usually means fixing it on the branch.
- **The user defers it.** In `interactive` mode the user picks it from the summary's "Below threshold" list and asks to defer it. It becomes a TD entry, which follows `references/tech-debt-tracker-format.md`.

`/en-sweep` discards the list, since it is producing a doc-only PR.

## What persona agents must emit

Every reviewer agent finding **must include** `confidence: 1-10`. Per `references/finding-schema.md`. If a finding is missing the field, `/en-review` treats it as confidence `5` (middle of range) and applies the threshold, so missing-confidence findings get filtered by default. This forces agents to express confidence explicitly rather than implicitly defaulting to "always surface."

## P0 special case

P0 findings (security vulnerabilities, data-loss risks, broken correctness invariants) always surface, regardless of confidence. The confidence rating still appears in the finding so the user knows whether to verify before acting:

- **High-confidence P0** → user fixes immediately
- **Low-confidence P0** → flagged with `low_confidence: true`; user verifies the claim before fixing

Filtering a P0 into the side list would silently downgrade a potential blocker. Never do that.

## Tuning

If review output feels noisy, raise the threshold to `8` or `9`. If the team feels they're missing real findings, lower to `6`. The number is meant to be tuned per-project based on the persona-agent precision observed in practice.

The `~/.ensemble/analytics/review.jsonl` log (when enabled) records each run's `findings_count` and `filtered_count` so you can calibrate.
