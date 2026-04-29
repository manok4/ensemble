# Doc lints

The catalog of file-shape checks that `bin/ensemble-lint` enforces. Distinct from `learn --lint` (which audits wiki-graph health). Together they give full coverage.

## Where lint runs

- **`en-review`** — pre-flight check on the diff. Lint failures surface as P1 findings.
- **`en-garden`** — full repo scan on every PR-merge run; opens fix-up PRs.
- **CI** — recommended via `references/ci-templates/lint.yml`.
- **Manually** — `bin/ensemble-lint [--scope docs/]`.

## Rule catalog

### `frontmatter.*` — frontmatter validity

| Rule | Severity | Notes |
|---|---|---|
| `frontmatter.parse-error` | P1 | YAML doesn't parse |
| `frontmatter.missing` | P1 | File lacks frontmatter when its type requires one (foundation, plan, learning, architecture, design, agent-map) |
| `frontmatter.required-field-missing` | P1 | Required field absent for the type (per Appendix C in foundation) |
| `frontmatter.invalid-enum` | P1 | Field value not in allowed enum (e.g., `status: foo`) |
| `frontmatter.date-format` | P1 | Date not `YYYY-MM-DD` |

### `id-stability.*` — ID stability

| Rule | Severity | Notes |
|---|---|---|
| `id-stability.r-renumbered` | P1 | An R-ID in foundation changed; append-only |
| `id-stability.u-renumbered` | P1 | A U-ID in a plan changed; append-only after assignment |
| `id-stability.fr-collision` | P1 | Two plan files share an FRXX number |
| `id-stability.fr-format` | P2 | FRXX number not zero-padded to 2 digits |
| `id-stability.td-renumbered` | P1 | A TD-ID in `tech-debt-tracker.md` changed; append-only |

### `cross-link.*` — cross-link integrity

| Rule | Severity | Notes |
|---|---|---|
| `cross-link.broken-r` | P1 | `(see R<N>)` resolves to nothing in foundation |
| `cross-link.broken-u` | P1 | `(see U<N>)` resolves to nothing in the cited plan |
| `cross-link.broken-fr` | P1 | `(see FR<NN>)` resolves to no plan file |
| `cross-link.broken-path` | P1 | Markdown link to a path that doesn't exist |
| `cross-link.broken-td` | P1 | `(see TD<N>)` or `Resolves: TD<N>` resolves to nothing |

### `status.*` — status correctness

| Rule | Severity | Notes |
|---|---|---|
| `status.location-mismatch` | P1 | `docs/plans/active/*.md` has `status: completed` (or vice versa) |
| `status.architecture-seed-stale` | P2 | `architecture.md` has `status: seed` but `updated:` is >7 days after a feature shipped |

### `path.*` — path discipline

| Rule | Severity | Notes |
|---|---|---|
| `path.absolute` | P1 | `/Users/...`, `C:\\...`, or other absolute path in artifact text |
| `path.windows-separator` | P2 | Backslash separators (use forward slash) |

### `freshness.*` — staleness

| Rule | Severity | Notes |
|---|---|---|
| `freshness.architecture-30` | P2 | `architecture.md` `updated:` >30 days old (or whatever `freshness_target_days` is set to) |
| `freshness.architecture-90` | P1 | `architecture.md` `updated:` >90 days old |
| `freshness.foundation-180` | P2 | `foundation.md` `updated:` >180 days old (advisory only — foundation is mostly stable) |

### `generated.*` — generated-file integrity

| Rule | Severity | Notes |
|---|---|---|
| `generated.missing-marker` | P1 | File in `docs/generated/` lacks `generated: true` frontmatter |
| `generated.human-edit` | P2 | File in `docs/generated/` has commits not authored by `en-learn` or `en-garden` (heuristic; surfaced as advisory) |

### `index-coverage.*` — index coverage

| Rule | Severity | Notes |
|---|---|---|
| `index-coverage.plan-missing` | P1 | A plan file exists but is not in `docs/generated/plan-index.md` |
| `index-coverage.plan-stale-entry` | P1 | `plan-index.md` line points to a non-existent plan file |
| `index-coverage.learning-missing` | P1 | A learning file exists but is not in `docs/generated/learning-index.md` |
| `index-coverage.learning-stale-entry` | P1 | `learning-index.md` line points to a non-existent learning file |

### `claude-md.*` — CLAUDE.md discipline

| Rule | Severity | Notes |
|---|---|---|
| `claude-md.no-cross-ref-line` | P1 | First non-frontmatter line of `CLAUDE.md` isn't the AGENTS.md cross-reference |
| `claude-md.no-shared-content` | P1 | A heading in `CLAUDE.md` (or a content block ≥3 lines) duplicates content in `AGENTS.md` |

### `length.*` — length budgets

| Rule | Severity | Notes |
|---|---|---|
| `length.agents-md-over-150` | P2 | `AGENTS.md` body >150 lines (target 100, hard ceiling 150) |
| `length.claude-md-over-80` | P2 | `CLAUDE.md` body >80 lines (target 60, hard ceiling 80) |

### `requirements-traceability.*` — requirements traceability (per C.3 fallback)

| Rule | Severity | Notes |
|---|---|---|
| `requirements-traceability.empty-when-foundation-has-r-ids` | P1 | A plan has `covers_requirements: []` and `requirements_pending: false` while `foundation.md` has at least one R-ID |
| `requirements-traceability.requirements-pending-no-foundation` | P3 | Plan has `requirements_pending: true` but no foundation exists yet (advisory; reminder to run `/en-foundation`) |

## Output format

JSON-lines, one violation per line:

```json
{
  "rule": "frontmatter.required-field-missing",
  "file": "docs/plans/active/FR03-auth.md",
  "line": null,
  "severity": "P1",
  "message": "Missing required frontmatter field: covers_requirements",
  "remediation": "Add 'covers_requirements: [R<N>, ...]' citing requirements from foundation.md Section 5"
}
```

Plus a markdown summary at the end:

```markdown
## Lint summary

- **Errors (P0):** 0
- **High (P1):** 3
- **Medium (P2):** 5
- **Advisory (P3):** 2

Run `bin/ensemble-lint --fix` to auto-apply mechanical fixes.
```

The `remediation` field is critical — it gives the agent a direct fix path without round-tripping to a human.

## Auto-fix behavior

`bin/ensemble-lint --fix` applies mechanical fixes:

- Repair broken cross-links when the moved-to target is obvious.
- Add missing required frontmatter fields with placeholder values.
- Sync `status:` to match directory location (`active/` ↔ `completed/`).
- Repair `claude-md.no-cross-ref-line` by prepending the line.
- Regenerate `docs/generated/plan-index.md` and `learning-index.md`.
- Bump `updated:` timestamps when content actually changed.

Non-mechanical findings (judgment-required, contradictions, length budget overruns where the user added intentional content) → surfaced for human resolution.

## Configuration

`~/.ensemble/config.json` keys read by lint:

```json
{
  "lint": {
    "freshness_target_days": 30,
    "scope_default": "docs/",
    "fix_skip_rules": []
  }
}
```

`fix_skip_rules` lets a project opt out of specific auto-fixes (rare; usually leave default empty).

## CI integration

Recommended `.github/workflows/ensemble-lint.yml`:

```yaml
name: Ensemble lint
on:
  pull_request:
    paths:
      - 'docs/**'
      - 'AGENTS.md'
      - 'CLAUDE.md'
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bin/ensemble-lint --scope docs/
```

Lint failures fail the PR check.
