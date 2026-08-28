# `/en-learn --bootstrap-patterns` — seeding patterns from an existing codebase

How `/en-learn`'s Mode F seeds `docs/learnings/patterns/` for retrofit projects.

## When this fires

- Manually: `/en-learn --bootstrap-patterns` — typically run once during the State-2 retrofit flow, after `/en-foundation --retrofit` has settled `docs/foundation.md` and `docs/architecture.md`.
- Optionally during `/en-setup`: see `skills/en-setup/SKILL.md` step 9a (offer to run after recommending `/en-foundation --retrofit`).
- **Never** auto-fires from any other skill. Bootstrap is opt-in and one-time per project.

## What it produces

5–10 entries in `docs/learnings/patterns/<slug>-<date>.md`. Each entry is a *forward-looking convention* drawn from existing code — not a captured bug fix or synthesis moment.

Distinguished from organic capture entries by frontmatter:

```yaml
---
title: <pattern title>
applies_when: <one-line trigger>
date: <YYYY-MM-DD>
category: patterns
tags: [<tag>, <tag>, …]
related: []
status: active
source: bootstrap                # ← marks reconstruction
bootstrap_run: 2026-05-04        # ← run date
requires_validation: true        # ← clears once a human validates
---
```

The `source: bootstrap` + `requires_validation: true` combination tells:

- `/en-learn --refresh` to prompt for validation.
- `/en-cross-review`, `/en-resolve-pr`, `/en-review` to cite these patterns with appropriate epistemic humility (e.g., *"Per `<pattern>`, [bootstrapped — verify before relying on this]"*).
- `bin/ensemble-lint`'s `learnings.bootstrap-unvalidated` rule (P3 advisory) to track how many bootstrapped entries remain unvalidated.

## Research prompt (dispatched to `repo-research`)

```
Identify the strongest 5-10 *durable conventions* in this codebase. A
durable convention is a pattern that:

  - is followed in ≥3 places, with no obvious exceptions
  - reflects a real design choice (not a happen-stance pattern)
  - would be cited by a code reviewer arguing "no, do it this way"
  - lives in source code, not in docs (we already have those)

Look for:
  - File layout patterns (where things live and why)
  - Naming conventions (file names, identifiers, exports)
  - Dependency direction (which layers depend on which)
  - Error handling shape (how errors propagate, where they're caught)
  - Test placement and shape (colocation, naming, fixtures)
  - Common abstractions (helpers, base classes, decorators)
  - Framework idioms specific to this project's stack

Do NOT include:
  - Project history ("we used to do X, now we do Y")
  - Aspirational rules from CLAUDE.md/AGENTS.md (those exist already)
  - Single-instance choices (need ≥3 examples)
  - Style nits handled by linters (formatting, casing)

For each convention, return:
{
  "slug": "kebab-case-identifier",
  "title": "<one-line pattern name>",
  "applies_when": "<when this pattern applies — one line>",
  "pattern": "<the convention itself, 2-4 sentences>",
  "why": "<rationale inferred from the code, 2-3 sentences>",
  "how_to_follow": ["<concrete rule 1>", "<concrete rule 2>", "..."],
  "citations": [
    {"file": "src/path/foo.ts", "line": 42, "snippet": "..."},
    {"file": "src/path/bar.ts", "line": 10, "snippet": "..."},
    {"file": "src/path/baz.ts", "line": 88, "snippet": "..."}
  ],
  "confidence": 6,
  "tags": ["error-handling", "service-layer"],
  "component": "<component or layer>"
}

Return at most 10. Order by strength of evidence (most-cited first).
If fewer than 5 strong conventions exist, return what you found — the
caller will surface a warning.
```

## Entry body shape

Bootstrapped patterns use a different body than capture entries. Capture writes one paragraph plus, rarely, an optional section; a bootstrapped convention is forward-looking and needs to say where it applies and how to follow it:

```markdown
---
<frontmatter as above>
---

# <Pattern title>

## TL;DR

<one-line summary — what's the rule and where it applies>

## Where this applies

- `<file or glob>` — `<one-line context>`
- `<file or glob>` — `<one-line context>`
- (3+ examples; the `citations:` field is the canonical list)

## Pattern

<the convention itself, 2-4 sentences. What you do.>

## Why

<rationale inferred from code, 2-3 sentences. Why this works in this codebase.>

## How to follow it

- <concrete rule 1>
- <concrete rule 2>
- <concrete rule 3>

## Citations

- `<file>:<line>` — `<snippet or commit ref>`
- `<file>:<line>` — `<snippet or commit ref>`
- `<file>:<line>` — `<snippet or commit ref>`

---

> **This pattern was bootstrapped from the codebase on `<date>`.** It's a
> reconstruction, not a captured moment — `requires_validation: true`.
> When you encounter this pattern in `/en-review`, `/en-resolve-pr`, or
> review, validate that it still holds (or update/archive it). Once
> validated, set `requires_validation: false` and bump `confidence` to 8.
```

## Validation flow

A bootstrapped entry stays `requires_validation: true` until a human confirms it. Confirmation happens one of three ways:

1. **Manual edit** — user reviews the entry, edits to set `requires_validation: false` and bumps `confidence: 8`.
2. **`/en-learn --refresh`** — surfaces each bootstrap entry; user picks `validate` / `update` / `archive`. On `validate`, refresh sets the flag clear and bumps confidence.
3. **Cited in a real review** — when `/en-review` or `/en-resolve-pr` cites a bootstrapped pattern in a `declined` verdict and the reviewer agrees, the user runs `/en-learn capture --validate-bootstrap <slug>` to clear the flag with that review event as evidence.

## Anti-patterns

- **Don't run twice.** The skill refuses re-runs unless `--force`. Multiple bootstrap passes generate duplicate entries with similar slugs and confuse the wiki.
- **Don't use bootstrap to reconstruct bugs.** Bug-fix learnings have lossy edges when reconstructed — the *thinking* matters, and that's not in the codebase. Bug capture is `/en-learn capture`'s job, real-time, not bootstrap.
- **Don't bypass the `confidence: 6` default.** Lower confidence is the contract — it tells downstream skills (review, resolve-pr) to cite cautiously. Setting it higher prematurely produces over-confident references that mislead.
- **Don't bootstrap a green-field project.** A fresh project has no real conventions yet — bootstrap will return weak signals. Use `/en-learn capture` from day one instead.

## Cross-link impact

Bootstrap entries:

- Have `related: []` initially (no other entries to link).
- Get back-linked by future capture entries via the always-on cross-ref maintenance.
- Once validated, become normal patterns and lose any visual distinction.

## Lint

New rule `learnings.bootstrap-unvalidated` (P3 advisory) — surfaces a count of bootstrapped entries that haven't been validated yet, after the bootstrap is more than 30 days old. Not a blocker; a reminder that the wiki has unverified content.
