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

## Assumptions & unverified claims

<Per en-brainstorm's verify-before-claiming rule: any claim that something is ABSENT in the codebase (a missing table/endpoint/dependency/config option) that was not verified against the repo goes here, labeled as an unverified assumption, so `/en-plan` doesn't inherit it as fact. Verified claims can be stated inline in the sections above with a `file:line` pointer. Omit this section if there are no unverified absence-claims.>

- <assumption, e.g. "assumes no retry logic exists on the client (not verified)">

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

If the user accepts → invoke `/en-learn capture --from-conversation` with the design doc as input. Where it lands is `/en-learn`'s call, not this skill's: it routes each capture to a term (`docs/CONTEXT.md`), a decision (`docs/decisions/`), or a solution (`docs/learnings/`), and applies its own capture gate — which may decide the synthesis earns no entry at all.

If the user declines → no-op. The design doc stays.

## Lint rules

`bin/ensemble-lint` checks:

- Frontmatter schema (Appendix C.2) — `type: design`, `created`, `topic`, `status`, `related_plan` all present.
- `status:` value in `{open, accepted, superseded}`.
- `related_plan:` resolves to a plan if non-empty (`cross-link.broken-fr`, P1).
- `status: accepted` or `superseded` requires a non-empty `related_plan:` (P2) — `/en-plan` writes both together, so one without the other is a half-applied close-out.
- No-absolute-paths.

## Close-out: how the design stops being `open`

`/en-plan` closes it, in the same promotion that flips a plan built from this
design to `status: open`. It sets:

- `status: accepted` when the plan carries this design's recommendation, or
  `status: superseded` when planning committed to a different approach, noting
  that plan in `replaced_by:`.
- `related_plan:` to that plan's `plan_id`.

`/en-plan` is the only skill that can tell the two apart, because it is the one
holding both this design's recommendation and what the plan actually commits to.
Close-out happens at plan-open, not at ship: the design's job is to feed
planning, and it is discharged once a plan exists.

**A design that never produces a plan stays `open`, and should.** An unplanned
exploration is still an open question, and `/en-brainstorm`'s resume scan should
keep offering it.

One path does not close a design out: `/en-foundation` mints the bootstrap
`<PREFIX>01-feature_project-setup` plan directly rather than through `/en-plan`.
That plan is repo-init scaffolding, not a design's recommendation, so the gap is
documented rather than papered over.
