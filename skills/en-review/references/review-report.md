# What `/en-review` returns

Read at the output-report step. This file is the **single owner of the envelope shape**: `references/finding-schema.md` defines the base finding and verdict, and everything `/en-review` adds on top is defined here and nowhere else.

## JSON envelope shape

```json
{
  "verdict": "approve | revise | reject",
  "summary": "<2-3 sentence overall>",
  "personas": ["correctness", "testing", "maintainability", "standards", "security"],
  "host_model": "<the resolver's model for dimension-reviewer at the ceiling tier> | null",
  "host_model_evidence": "<the same at the evidence tier, for testing, maintainability, standards, performance> | null",
  "mode": "interactive | headless | report-only",
  "review_tier": {"required": "quick | standard | full", "ran": "quick | standard | full", "reasons": []},
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

`review_tier` is null for any target that is not a branch diff, and for `--verify`. `required` is the run's effective tier, after any raise, and `ran` is what the run reached:

| What ran | `ran` |
|---|---|
| Host lite roster, or a peer given the lite brief, or both | `quick` |
| Peer with the full brief alone, or full host roster alone | `standard` |
| Full host roster and peer, including `single-agent-fallback` | `full` |
| Full host roster where `jq -r .peer_mode_override ~/.ensemble/config.json` is `off` (the user turned the peer off) | `full` |
| Full host roster where `PEER_AVAILABLE=false` for any other reason, such as `cross-agent-only` with no second CLI | `standard` |
| Full host roster and a fresh host session, after a `peer-failed:*` peer | `full` |
| Fresh host session alone, after a `peer-failed:*` peer | `standard` |
| Full host roster after the peer and the fresh host session both failed | `standard` |

`sub_threshold_findings[]` holds the findings below the confidence threshold, in the same shape as `findings[]`. It is present in every mode and is never filed as tech debt (`references/review-confidence-gating.md`).

## Mandatory outcome lines

**Five lines, one rule: EVERY run emits exactly ONE of each, and every line is DERIVED from its structured envelope object, never composed independently.** A missing line is then always distinguishable from a decision that went the quiet way, which is the whole point (D42): a gate that can override silently is not auditable.

| Line | Forms |
|---|---|
| `review_tier:` | `review_tier: <ran> (required <required>; <files> files, <lines> lines; <reasons>)` · `review_tier: none (<ad-hoc-target or verify>)` |
| `lite_gate:` | `lite_gate: applied` · `lite_gate: overridden (<reasons>)` · `lite_gate: not-requested` |
| `peer_decision:` | `peer_decision: <peer> (<reason>, effort=<tier>)`, e.g. `peer_decision: degraded (dropped-effort-fragment, effort=high)`. `<reason>` is a member of the closed enum in `references/peer-model-policy.md` (e). |
| `review_fixes:` | `review_fixes: applied <N> (<finding-ids with tiers>)` · `review_fixes: none` · `review_fixes: none (report-only)` |
| `verification_pass:` | `verification_pass: clean` · `verification_pass: new-findings (<id>/<severity>, …)` · `verification_pass: not-run (<reason>)`, where `<reason>` is `no-p0-p1-addressed` or `peer-failure` |

**`host_context: inherited`.** Add this line to the summary only when a host reviewer ran on a Codex CLI with no `fork_turns`, so a reviewer that saw the session is never read as fresh.

**`lite_gate:` outcomes.** `applied` is any run at lite depth, including a bare `quick` run. `not-requested` is a run with no `--lite` and a tier above `quick`, or an explicit mode on a `quick` diff with no `--lite`.

**`lite_gate: overridden (<reasons>)`.** `size` is a `size-standard`, `over-300-lines` or `over-10-files` tier reason, and `risk-signal` any `risk:<signal>`. `<reasons>` uses these **canonical override-reason identifiers** (`diff-unreadable`, `size`, `risk-signal`, `conditional-persona:<names>`), deduplicated, in that fixed canonical order, comma+space separated, with exactly one space before the paren. Persona names in `conditional-persona:` are alphabetically sorted and `+`-joined. Example: `lite_gate: overridden (risk-signal, conditional-persona:performance+security)`. The envelope's `reasons` array holds the same identifiers in the same canonical order, empty for `applied` and `not-requested`.

**`review_fixes: applied <N> (…)`.** `<N>` MUST equal the count of unique `applied_fixes[]` entries. The list is DERIVED from the array: finding IDs in ascending ID order, each rendered `<finding_id>/<tier>`, comma+space separated. The markdown summary below shows the line for the envelope above. Both `none` forms require `applied_fixes` to be `[]`.

## Markdown summary

Always emit a markdown summary alongside the JSON, even in `headless`/`report-only`. Example:

```markdown
## Code review — FR07-auth-rotation

**Verdict:** revise (3 findings)
**Personas fired:** correctness, testing, maintainability, standards, security (host_model: opus; evidence-tier dimensions: sonnet)
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
