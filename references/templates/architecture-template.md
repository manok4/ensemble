# Template — `docs/architecture.md`

Used by `/en-foundation` to seed the initial architecture document. After seeding, `en-learn` (event-driven, on every material change) and `en-garden` (drift-driven, on every PR merge) keep it current.

> **Intent vs reality.** `foundation.md` captures intent (what we set out to build). `architecture.md` captures reality (what the code actually looks like). On a brand-new project, these align; the gap grows as the project diverges from the original plan.

## Substitution variables

| Variable | Source |
|---|---|
| `{{PROJECT_NAME}}` | `foundation.md` `project:` |
| `{{TODAY}}` | `YYYY-MM-DD` at generation time |
| `{{INITIAL_COMPONENTS}}` | Detected from foundation §9 (Architecture) and any code already in the repo |
| `{{INITIAL_LAYER_RULES}}` | Detected from foundation §9 if present; else placeholder "to be defined" |

## Template body

```markdown
---
project: {{PROJECT_NAME}}
type: architecture
status: seed
created: {{TODAY}}
updated: {{TODAY}}
last_drift_check: {{TODAY}}
freshness_target_days: 30
---

# {{PROJECT_NAME}} — architecture

> Status: **seed**. This document was initialized by `/en-foundation`. It will be flipped to `active` after the first feature ships and `en-learn` validates it against shipped reality.

This file captures the **current architectural reality** of the project. For *intent* (the original vision and durable decisions), see [`foundation.md`](./foundation.md). For *changes over time*, see [`docs/learnings/decisions/`](./learnings/decisions/).

## Components

| Component | Responsibility | Key files | Notes |
|---|---|---|---|
{{INITIAL_COMPONENTS}}

## Layer rules

{{INITIAL_LAYER_RULES}}

Allowed import directions:

- *(seed: to be defined as the codebase emerges)*

Forbidden cross-cuts:

- *(seed: to be defined)*

## Data flows

### Primary request lifecycle

*(seed: to be filled in once routes/handlers exist)*

### Async pipelines

*(seed: to be filled in once workers/queues exist)*

## External integrations

| Integration | Purpose | Auth | Failure mode |
|---|---|---|---|
| *(none yet)* | | | |

## Infrastructure

| Resource | Type | Purpose | Notes |
|---|---|---|---|
| *(seed)* | | | |

## Database entities

| Entity | Purpose | Relationships |
|---|---|---|
| *(seed)* | | |

## Auth and trust boundaries

*(seed: define when auth is implemented)*

## Open architectural questions

*(seed: from foundation §15 Risks and §16 Open Questions)*

---

> **Maintenance.** `en-learn` updates the relevant section after every material structural change ships. `en-garden` checks this file for drift on every PR merge to `main` and opens fix-up PRs when components, dependencies, or boundaries diverge from the documented state. Cosmetic refactors and pure test additions do not trigger updates.
>
> Material changes (per `references/architecture-update-rules.md`):
> - New / removed component, service, module, package
> - Changed component boundary or layer
> - New / removed external integration
> - New infrastructure (queue, cache, worker, datastore)
> - Database schema additions/removals at the entity level
> - Auth, permission, or trust-boundary changes
```

## Notes on generation

- For a State-1 (greenfield) project, `{{INITIAL_COMPONENTS}}` is sparse — usually one row or empty. The seed flips to `active` once the first plan ships.
- For a State-2 retrofit, `{{INITIAL_COMPONENTS}}` is populated by `repo-research` — scan the existing codebase for top-level directories under `src/`, identify each as a component, and infer responsibility from the contents.
- Layer rules in foundation §9 (if present) seed the section. If foundation doesn't specify, leave placeholder.
- Set `status: seed` on first creation. `en-learn` flips to `active` after the first material update.

## Lint rules

`bin/ensemble-lint` checks:

- `architecture.frontmatter-required` — `status`, `created`, `updated`, `last_drift_check`, `freshness_target_days` all present (P1).
- `architecture.freshness` — `updated:` within `freshness_target_days` (default 30) → green; up to 90 → P2 advisory; >90 → P1.
- `architecture.status-valid` — `status:` is `seed` or `active`; nothing else (P1).
- `architecture.no-absolute-paths` — no `/Users/...` in component file lists (P1).

## Update protocol

When `en-learn` updates this file:

1. Identify the affected section.
2. Apply surgical edits — never regenerate the whole doc.
3. Bump `updated: YYYY-MM-DD`.
4. If first material update after seeding → flip `status: seed` to `status: active`.
5. Append `## [<date>] arch-update | <one-line summary>` to `docs/learnings/log.md`.

When `en-garden` updates this file (drift-driven):

1. Open a doc-only PR with the surgical edit.
2. PR title: `chore(arch): document <what changed>`.
3. PR body cites the source-PR SHA that introduced the drift.
4. Auto-merge after `en-review` clears.
