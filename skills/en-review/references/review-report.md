# What `/en-review` returns

Read at the output-report step. This file is the **single owner of the envelope shape**: `references/finding-schema.md` defines the base finding and verdict, and everything `/en-review` adds on top is defined here and nowhere else.

## JSON envelope shape

```json
{
  "verdict": "approve | revise | reject",
  "summary": "<2-3 sentence overall>",
  "personas": ["correctness", "testing", "maintainability", "standards", "security"],
  "host_model": "<the resolver's model for dimension-reviewer> | null",
  "mode": "interactive | headless | report-only",
  "lite_gate": {"outcome": "applied | overridden | not-requested", "reasons": []},
  "verification_pass": {"outcome": "clean | new-findings | not-run", "reason": "no-p0-p1-addressed | peer-failure | null", "finding_ids": []},
  "diff_base": "main",
  "diff_files_count": 12,
  "lint_findings_count": 0,
  "applied_safe_auto_count": 3,
  "applied_fixes": [
    {"finding_id": "rev-1-2", "tier": "safe_auto", "files": ["src/auth/refresh.ts"]},
    {"finding_id": "rev-1-5", "tier": "safe_auto", "files": ["src/lib/redis.ts"]},
    {"finding_id": "rev-1-8", "tier": "safe_auto", "files": ["tests/auth/refresh.test.ts"]}
  ],
  "findings": [
    {
      "severity": "P1",
      "confidence": 9,
      "title": "...",
      "location": "src/auth/refresh.ts:42",
      "personas": ["correctness", "security"],
      "why_it_matters": "...",
      "suggested_fix": "...",
      "autofix_class": "manual",
      "applied": false
    }
  ],
  "sub_threshold_findings": []
}
```

`sub_threshold_findings[]` holds the findings below the confidence threshold, in the same shape as `findings[]`. It is present in every mode and is never filed as tech debt (`references/review-confidence-gating.md`).

## Mandatory outcome lines

**Four lines, one rule: EVERY run emits exactly ONE of each, and every line is DERIVED from its structured envelope object, never composed independently.** A missing line is then always distinguishable from a decision that went the quiet way, which is the whole point (D42): a gate that can override silently is not auditable.

| Line | Forms |
|---|---|
| `lite_gate:` | `lite_gate: applied` · `lite_gate: overridden (<reasons>)` · `lite_gate: not-requested` |
| `peer_decision:` | `peer_decision: <peer> (<reason>, effort=<tier>)`, e.g. `peer_decision: degraded (dropped-effort-fragment, effort=high)`. `<reason>` is a member of the closed enum in `references/peer-model-policy.md` (e). |
| `review_fixes:` | `review_fixes: applied <N> (<finding-ids with tiers>)` · `review_fixes: none` · `review_fixes: none (report-only)` |
| `verification_pass:` | `verification_pass: clean` · `verification_pass: new-findings (<id>/<severity>, …)` · `verification_pass: not-run (<reason>)`, where `<reason>` is `no-p0-p1-addressed` or `peer-failure` |

**`lite_gate: overridden (<reasons>)`.** `<reasons>` uses the **canonical override-reason identifiers from `references/diff-signal-detection.md`** (`risk-signal`, `conditional-persona:<names>`), deduplicated, in that fixed canonical order, comma+space separated, with exactly one space before the paren. Persona names in `conditional-persona:` are alphabetically sorted and `+`-joined. Example: `lite_gate: overridden (risk-signal, conditional-persona:performance+security)`. The envelope's `reasons` array holds the same identifiers in the same canonical order, empty for `applied` and `not-requested`.

**`review_fixes: applied <N> (…)`.** `<N>` MUST equal the count of unique `applied_fixes[]` entries. The list is DERIVED from the array: finding IDs in ascending ID order, each rendered `<finding_id>/<tier>`, comma+space separated. The markdown summary below shows the line for the envelope above. Both `none` forms require `applied_fixes` to be `[]`.

## Markdown summary

Always emit a markdown summary alongside the JSON, even in `headless`/`report-only`. Example:

```markdown
## Code review — FR07-auth-rotation

**Verdict:** revise (3 findings)
**Personas fired:** correctness, testing, maintainability, standards, security (host_model: opus)
**Pre-flight lint:** clean
**Auto-applied:** 3 safe_auto fixes
lite_gate: not-requested
review_fixes: applied 3 (rev-1-2/safe_auto, rev-1-5/safe_auto, rev-1-8/safe_auto)
verification_pass: not-run (no-p0-p1-addressed)

### High (P1)

- **U3 — Refresh token race in concurrent path** (correctness, security; conf 9)
  - `src/auth/refresh.ts:42`
  - Two requests can race during rotation; second invalidates the first.
  - Fix: serialize per-user via singleFlight cache.

### Below threshold (2, not filed)

- Retry loop swallows the last error (correctness; conf 5) — `src/auth/refresh.ts:88`
- Test name does not match the fixture (testing; conf 4) — `tests/auth/refresh.test.ts:12`
```

One `###` section per severity present, P0 first, each finding carrying its U-ID, personas, confidence, location, why and fix. Then **Below threshold**, one line per `sub_threshold_findings[]` entry (title, personas and confidence, location), so a user can defer one by name; omit the section when the list is empty.
