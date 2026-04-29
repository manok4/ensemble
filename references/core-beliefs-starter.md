# Core beliefs — templated starter

Optional `docs/core-beliefs.md` for projects that want to encode agent-first operating principles. Seeded by `/en-foundation` (Standard / Deep depth) when the user opts in. After seeding, the user owns the file — `/en-foundation` does not regenerate it.

> **Optional file.** Lightweight projects skip this. Standard / Deep projects benefit when the team has a strong opinion on how agents should behave that diverges from Ensemble defaults.

## Substitution variables

| Variable | Source |
|---|---|
| `{{PROJECT_NAME}}` | foundation `project:` |
| `{{TODAY}}` | `YYYY-MM-DD` |

## Template body

```markdown
---
project: {{PROJECT_NAME}}
type: core-beliefs
created: {{TODAY}}
updated: {{TODAY}}
---

# {{PROJECT_NAME}} — core beliefs

> Operating principles for agents (and humans) working in this codebase. These
> override Ensemble defaults where they conflict. Edit freely; this file is
> not regenerated.

## What we believe

### 1. The repository is the system of record

If knowledge isn't in the repo, the agent can't see it. Slack discussions,
design conversations in chat, decisions made in someone's head — all illegible.
Capture decisions before moving on.

### 2. Map, not encyclopedia

`AGENTS.md`, `CLAUDE.md`, and `docs/foundation.md` point to deeper sources.
SKILL.md follows the same principle. A doc that tries to be everything ends up
being nothing.

### 3. Failure means a missing capability

When a skill fails, ask "what capability is missing?" not "how do I retry?"
Encode the missing piece (a learning, a reference, a lint, a persona) so the
next run catches it.

### 4. Boring tech is easier for agents

Composability and API stability beat novelty. If a "boring" library does the
job, prefer it. If working around an opaque upstream library costs more than
reimplementing a focused subset, reimplement.

### 5. Three similar lines is better than premature abstraction

Don't extract a helper for one caller. Don't introduce a generic for one type.
Wait for 4+ duplicates AND non-trivial complexity AND likely-evolves-together.

### 6. Pay debt continuously

`/en-garden` runs on every PR merge. Small focused cleanup PRs. Auto-merge
when `/en-review` is clean. Never let cleanup become a once-a-quarter project.

### 7. Throughput changes the merge philosophy

In a fast agent-driven loop, blocking gates that would be sensible at human
pace become counterproductive. Test flakes get re-run; corrections are cheap;
PRs are short-lived. Document the chosen merge philosophy in `AGENTS.md`.

## What we don't believe

### 1. ~~Iron-law TDD as a global gate~~

Per-unit Execution Note (test-first / characterization-first / pragmatic) lives
in plans. `/en-build` honors the note; user can override.

### 2. ~~50-agent reviewer zoo~~

We use 4 always-on reviewers + 3 conditional. Adding more agents past this is a
sign that the existing personas need clearer remits, not that we need more
personas.

### 3. ~~Heavy AskUserQuestion ritual~~

Recommendation + 2–4 options + one-line rationale. No decision-brief format.
Reserve heavy questioning for genuinely opaque trade-offs.

### 4. ~~Marketing language in code, commits, or artifacts~~

"Blazingly fast", "magnificent", "100% secure" — never. State facts. Untested
claims belong in PR descriptions or get deleted.

## Project-specific beliefs

<add anything specific to this project — coding style preferences,
architectural opinions, agent-behavior preferences that differ from
defaults, etc.>

- ...

## How to use this file

- Read at the start of any non-trivial session (auto-loaded into agent
  context if cited from `AGENTS.md`).
- When a belief is violated by code or process, surface as a P1 finding.
- Update when a belief changes. Add a `## YYYY-MM-DD` note at the bottom
  documenting what changed and why.
```

## Notes on generation

- This file is **opt-in.** `/en-foundation` asks: "Do you want a `docs/core-beliefs.md` seeded for agent-first operating principles? (yes / skip — recommended for Standard / Deep projects only)".
- The "What we believe" section reflects Ensemble defaults — the user can edit, expand, or delete sections as they like after seeding.
- The "What we don't believe" section is meant to be project-specific in style; the seeded list is illustrative.
- `/en-garden` does **not** edit this file — it's user-owned after seeding.
- `bin/ensemble-lint` validates frontmatter only; doesn't enforce content.

## When to seed

- **Standard / Deep projects** — recommended. Encodes operating principles legibly.
- **Lightweight projects** — skip. The principles in `AGENTS.md` are sufficient.
- **Retrofit (`--retrofit` mode)** — ask the user; default skip. The team likely already has its own beliefs encoded elsewhere.
