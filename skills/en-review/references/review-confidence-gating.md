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

### Interactive / headless modes

Each filtered finding is appended to `docs/plans/tech-debt-tracker.md` as a TD entry. Format per `references/tech-debt-tracker-format.md`, plus a marker line:

```markdown
### TD<N>. <Finding title>

Filed by /en-review (confidence <N>) — sub-threshold; surfaced for later review.

**Location:** `<file>:<line>`
**Persona:** <reviewer-agent>
**Severity:** <P1-P3>
**Why it matters:** <quoted from finding>
**Suggested fix:** <if any>

> [pasted finding body]
```

The TD-ID is auto-incremented (same as user-filed entries). The `Filed by /en-review` marker lets `/en-sweep`'s tech-debt-hygiene checks distinguish auto-filed entries from human-filed ones.

### Report-only mode

No mutations allowed. Sub-threshold findings appear in the JSON envelope under a separate key:

```json
{
  "verdict": "approve | revise | reject",
  "findings": [...],                  // ≥ threshold
  "sub_threshold_findings": [...],    // < threshold; not filed (caller decides)
  ...
}
```

Callers like `/en-sweep` (which invokes `/en-review` in `report-only`) can decide what to do with sub-threshold findings — typically they're discarded since `/en-sweep` is itself producing a doc-only PR.

## What persona agents must emit

Every reviewer agent finding **must include** `confidence: 1-10`. Per `references/finding-schema.md`. If a finding is missing the field, `/en-review` treats it as confidence `5` (middle of range) and applies the threshold, so missing-confidence findings get filtered by default. This forces agents to express confidence explicitly rather than implicitly defaulting to "always surface."

## P0 special case

P0 findings (security vulnerabilities, data-loss risks, broken correctness invariants) always surface, regardless of confidence. The confidence rating still appears in the finding so the user knows whether to verify before acting:

- **High-confidence P0** → user fixes immediately
- **Low-confidence P0** → flagged with `low_confidence: true`; user verifies the claim before fixing

Filtering a P0 to TD would be silently downgrading a potential blocker. Never do that.

## Tuning

If review output feels noisy, raise the threshold to `8` or `9`. If the team feels they're missing real findings, lower to `6`. The number is meant to be tuned per-project based on the persona-agent precision observed in practice.

The `~/.ensemble/analytics/review.jsonl` log (when enabled) records each run's `findings_count`, `filtered_count`, and `filed_to_td_count` so you can calibrate.
