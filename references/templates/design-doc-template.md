# Template — `docs/designs/YYYY-MM-DD-<topic>-design.md`

Used by `/en-brainstorm` to write the output of an exploration session: 2–3 approaches, trade-offs, recommendation, devil's advocate pass.

## Substitution variables

| Variable | Source |
|---|---|
| `{{TODAY}}` | `YYYY-MM-DD` at generation time |
| `{{TOPIC}}` | Slug derived from the conversation topic |
| `{{TITLE}}` | One-line title from the conversation synthesis |

## Template body

```markdown
---
type: design
created: {{TODAY}}
topic: {{TITLE}}
status: open
related_plan:
---

# {{TITLE}}

## Problem

<2-3 sentences: what we're trying to figure out, what triggered it, what's at stake.>

## Constraints and context

- <constraint or context point>
- ...

## Approaches considered

### A. <Approach name>

**Sketch:** <one paragraph>

**Pros:**
- ...

**Cons:**
- ...

### B. <Approach name>

(same shape)

### C. <Approach name>

(same shape; usually 2–3 approaches; sometimes 4 if the space is large)

## Recommendation

**Approach <X>** — <one-paragraph rationale>.

## Devil's advocate

What's wrong with the recommendation? Honest stress-test:

- ...
- ...

## Why we're proceeding anyway (if applicable)

- ...

## Open questions

- ...

## Next steps

- Run `/en-foundation` if this is a new product.
- Run `/en-plan` if this is a feature in an existing project.
- Run `/en-learn capture --from-conversation` if a synthesis worth filing emerged.
```

## Generation notes

- One question per turn during the conversation; multiple-choice preferred where natural.
- Web research via `web-research` agent is **optional** — only when the user explicitly wants it or when prior art would materially change the recommendation.
- The `related_plan:` frontmatter field is filled in later by `en-plan` when a plan is created from this design.
- The design doc is informational, not load-bearing. `en-foundation` and `en-plan` consume it; nothing else does. Once the work ships, the design can be archived (move to `docs/designs/archive/`) — the durable insight should have moved into a learning by then.

## Capture-from-synthesis reflex (D21)

`en-brainstorm` ends with a soft prompt:

> "This conversation produced [a non-obvious connection / a comparison across approaches / an extracted lesson]. Capture as a learning?"

If the user accepts → invoke `/en-learn capture --from-conversation` with the design doc as input. The learning lands in `docs/learnings/decisions/` or `patterns/` depending on the synthesis type.

If the user declines → no-op. The design doc stays.

## Lint rules

`bin/ensemble-lint` checks:

- Frontmatter schema (Appendix C.2) — `type: design`, `created`, `topic`, `status`, `related_plan` all present.
- `status:` value in `{open, accepted, superseded}`.
- `related_plan:` resolves to a plan if non-empty.
- No-absolute-paths.

## When the design moves to `superseded`

When a plan ships that addresses the design's question, `en-learn` may flip the design's `status:` to `accepted` (the recommended approach was implemented) or `superseded` (a different approach was chosen — note in `replaced_by:` which plan).

`/en-learn` does this as part of its post-ship sweep when it sees `related_plan:` populated and the plan moved to `completed/`.
