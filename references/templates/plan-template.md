# Template — `docs/plans/active/FR<NN>-<name>.md`

Used by `/en-plan` to create a feature/component/refactor implementation plan with stable U-IDs.

## Substitution variables

| Variable | Source |
|---|---|
| `{{FR_ID}}` | Auto-incremented from highest existing FRXX across `active/` and `completed/` |
| `{{TITLE}}` | Discovered from user input |
| `{{TODAY}}` | `YYYY-MM-DD` at generation time |
| `{{COVERS_REQUIREMENTS}}` | List of R-IDs the plan addresses (or `[]` with `requirements_pending: true` for State-2 retrofits) |
| `{{REQUIREMENTS_PENDING}}` | `false` (default); `true` when no foundation R-IDs exist yet |
| `{{RELATED_DESIGN}}` | Path to `docs/designs/*.md` if a brainstorm preceded the plan; empty otherwise |
| `{{DEPTH}}` | `lightweight` \| `standard` \| `deep` |

## Template body

```markdown
---
type: plan
fr_id: {{FR_ID}}
title: {{TITLE}}
status: active
location: active
created: {{TODAY}}
shipped:
deepened:
covers_requirements: {{COVERS_REQUIREMENTS}}
requirements_pending: {{REQUIREMENTS_PENDING}}
related_design: {{RELATED_DESIGN}}
peer_review_verdict:
depth: {{DEPTH}}
---

# {{FR_ID}} — {{TITLE}}

## Context

<2-3 sentences: what problem this solves, why now, who asked.>

## Requirements covered

{{COVERS_REQUIREMENTS_PROSE}}

## Out of scope for this plan

- ...

## Approach (high-level)

<one to three paragraphs: the architectural shape of the solution. Decisions live here at the macro level; per-unit tactics live in U-ID sections.>

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. <Goal title>

- **Goal:** <one-line outcome>
- **Requirements covered:** R<N>, AE<N>
- **Dependencies:** <U-IDs that must complete first, or `none`>
- **Files:** <repo-relative paths the unit will touch>
- **Approach:** <how this unit will be implemented>
- **Execution note:** test-first | characterization-first | pragmatic
- **Patterns to follow:** <citations from `docs/learnings/patterns/` if relevant>
- **Test scenarios:**
  - <scenario>
  - <scenario>
- **Verification:** <what counts as done — tests pass + lint + manual check>

### U2. ...

## Risks

- **Risk:** <what could go wrong> — **Mitigation:** <how we handle it>

## Tracked debt

If this plan resolves any tracked debt items, cite them:

- **Resolves:** TD7, TD12

If the plan defers items, file them in `docs/plans/tech-debt-tracker.md` with a back-reference.

## Iteration log

> - {{TODAY}} (initial): plan v0 from `<source>`.
```

## Generation notes

- **Depth scaling:**
  - **Lightweight** — keep Context, Approach (one paragraph), 1–3 units. Drop "Out of scope", "Risks", "Tracked debt" unless content exists.
  - **Standard** — full template; 3–10 units typical.
  - **Deep** — full template; 10+ units; multiple Risk and Approach sub-sections.

- **Unit granularity:**
  - One unit ≈ one logical change that can be peer-reviewed and committed atomically.
  - Tightly-coupled changes batch into one unit; independent concerns become separate units.
  - Complex/sensitive units (auth, payments, migrations) get their own unit even if small.

- **U-ID assignment:**
  - U1, U2, … in plan order.
  - **Never renumber** after the plan is committed. Splitting a unit keeps the original ID; new pieces get new IDs (per `references/stable-ids.md`).

- **Requirements traceability:**
  - Cite R-IDs from `foundation.md`. If `foundation.md` doesn't exist yet (State-2 retrofit), set `covers_requirements: []` and `requirements_pending: true`. Lint upgrades to P1 once foundation has R-IDs.

- **Execution note:**
  - `test-first` — write a failing test, then implementation. Default for new behavior with clear contracts.
  - `characterization-first` — capture current behavior in tests before refactoring legacy code.
  - `pragmatic` — implementation and tests interleave; default for exploratory work and well-tested codebases.
  - Honored by `en-build` per unit; user can override at build time.

- **Files field:**
  - Repo-relative paths only.
  - List the files the unit will touch; OK to include "newly created" files.
  - Glob patterns acceptable for clear cases (`tests/auth/refresh.*.test.ts`).

## Lint rules

`bin/ensemble-lint` checks:

- Frontmatter schema (Appendix C.3) — `type: plan`, `fr_id`, `title`, `status`, `location`, `created`, `covers_requirements`, `requirements_pending`, `related_design`, `peer_review_verdict`.
- `status.location-mismatch` — `status:` matches the directory the file is in (`active/` ↔ `completed/`).
- U-ID stability (`id-stability.u-renumbered`).
- Cross-link integrity for `R<N>`, `AE<N>`, `TD<N>` citations.
- `requirements-traceability.empty-when-foundation-has-r-ids` — if `covers_requirements: []` and `requirements_pending: false` while foundation has R-IDs, fail.

## Lifecycle

1. **Draft** — `en-plan` writes the plan, runs Outside Voice, user iterates. `status: draft`.
2. **Active** — User accepts; plan moves to `active/` with `status: active`.
3. **Building** — `en-build` reads the plan; status stays `active`.
4. **Completed** — `en-learn capture` flips `status: completed`, sets `shipped: <date>`, moves the file to `completed/`.

## Worked excerpt

```markdown
### U3. Implement single-flight cache for refresh-token rotation

- **Goal:** Serialize concurrent refresh requests per user_id so only one rotation fires.
- **Requirements covered:** R7, AE3
- **Dependencies:** U1 (cache lib chosen), U2 (Redis connection wired)
- **Files:**
  - `src/auth/refresh.ts` (new)
  - `src/auth/refresh.test.ts` (new)
  - `src/lib/single-flight.ts` (new)
  - `src/lib/single-flight.test.ts` (new)
- **Approach:** Introduce a `singleFlight<K, V>` helper that keys on user_id and de-dupes concurrent calls. Wrap `rotateRefreshToken()` in this helper. Cache TTL matches token rotation grace window.
- **Execution note:** test-first
- **Patterns to follow:** `docs/learnings/patterns/single-flight-cache-2026-03-20.md`
- **Test scenarios:**
  - Single caller — token rotates, response returned.
  - Two concurrent callers — both get the same token; underlying rotate fires once.
  - Caller after TTL — fresh rotation.
- **Verification:** `bun test src/auth/refresh.test.ts src/lib/single-flight.test.ts` passes; `bun run lint` clean.
```
