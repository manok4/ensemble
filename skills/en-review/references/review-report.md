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
  ]
}
```

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
```

One `###` section per severity present, P0 first, each finding carrying its U-ID, personas, confidence, location, why and fix.
