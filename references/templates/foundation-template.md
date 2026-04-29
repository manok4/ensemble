# Template — `docs/foundation.md`

Used by `/en-foundation` to seed the foundation document. Combined PRD + technical direction + initial architectural intent.

> **Depth scaling.** This template is the **deep** version. Lightweight projects can omit Section 9 (Architecture) and trim Sections 11–13. Standard projects keep Sections 1–10 plus 14, skipping 11–13. The skill picks the depth at the start.

## Substitution variables

| Variable | Source |
|---|---|
| `{{PROJECT_NAME}}` | Discovered from user input |
| `{{ONE_LINE_PURPOSE}}` | First synthesis answer in §1 |
| `{{TODAY}}` | `YYYY-MM-DD` at generation time |
| `{{OWNER}}` | User name from git config or asked |
| `{{DEPTH}}` | `lightweight` \| `standard` \| `deep` |

## Template body

```markdown
---
project: {{PROJECT_NAME}}
type: foundation
status: draft
created: {{TODAY}}
updated: {{TODAY}}
owner: {{OWNER}}
depth: {{DEPTH}}
---

# {{PROJECT_NAME}} — Foundation

> {{ONE_LINE_PURPOSE}}

This document combines product requirements, technical direction, and architectural intent. It is the **vision and rationale** at project start, plus durable decisions over time. For *current architectural reality*, see [`architecture.md`](./architecture.md).

---

## 1. Executive Summary

<2-3 paragraphs: what this product is, who it's for, why now, and the highest-level design choices.>

---

## 2. Goals and Non-Goals

### 2.1 Goals (G-IDs)

- **G1.** <one-line goal>
- **G2.** ...

### 2.2 Non-Goals

- ...

---

## 3. Users and Actors

### 3.1 Primary user

- ...

### 3.2 User personas (A-IDs)

- **A1.** <persona name> — <one-line description>
- **A2.** ...

### 3.3 Stakeholders

- ...

---

## 4. Product Decisions (D-IDs)

Append-only list of durable decisions. Each entry: ID, one-line decision, why.

- **D1.** <decision> — <why>
- **D2.** ...

---

## 5. Functional Requirements (R-IDs and Acceptance Examples)

Each requirement has a stable R-ID and at least one acceptance example.

### R1. <requirement title>

<one-paragraph description>

**Acceptance examples:**
- **AE1.** Given <state>, when <action>, then <observable outcome>.
- **AE2.** ...

### R2. ...

---

## 6. User Experience (F-IDs)

Top-level UX flows. Each flow has a stable F-ID and a brief description with screen/state names.

### F1. <flow name>

<one-paragraph description; bullet steps if helpful>

### F2. ...

---

## 7. Technical Direction

### 7.1 Stack

- Language: ...
- Framework: ...
- Database: ...
- Hosting: ...
- Auth: ...

### 7.2 Key technical choices

- ...

### 7.3 Constraints

- ...

---

## 8. Data Architecture

### 8.1 Top-level entities

- <Entity> — <purpose>
- ...

### 8.2 Isolation model

- <single-tenant / multi-tenant / per-row tenancy>
- ...

### 8.3 Migration strategy

- ...

---

## 9. Architecture (intent)

### 9.1 Component diagram

<ASCII or mermaid; high-level only>

### 9.2 Layer rules

- Allowed import directions: ...
- Forbidden cross-cuts: ...

### 9.3 External integrations (intent)

- ...

> The **current** architecture lives in [`architecture.md`](./architecture.md). This section captures architectural *intent*; once features ship, `architecture.md` is the source of truth for what's actually built.

---

## 10. API Surface

### 10.1 Public API

- ...

### 10.2 Internal contracts

- ...

---

## 11. Deployment and Infrastructure

- ...

---

## 12. Observability

- ...

---

## 13. Security and Privacy

- ...

---

## 14. Risks and Open Questions

### 14.1 Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ... | | | |

### 14.2 Open Questions (Q-IDs)

- **Q1.** <question> — <when we'll answer>
- **Q2.** ...

---

## Iteration log

> - {{TODAY}} (initial): wrote foundation v0.
```

## Notes on generation

- The depth-scaled trim:
  - **Lightweight** — keep §1–§7, §10, §14. Drop §8 (data), §9 (architecture), §11 (deploy), §12 (observability), §13 (security).
  - **Standard** — keep §1–§10, §14. Drop §11–§13 unless explicitly relevant.
  - **Deep** — full template.
- `D1`, `R1`, `A1`, etc. are seeded only when the user provides content for them. Empty IDs aren't auto-generated.
- For State-1 (greenfield) projects, the template emits the foundation **and** an `FR01-project-setup` plan in `docs/plans/active/` (per A1/D24).
- For State-2 (retrofit) projects, the template emits the foundation only; existing source code informs §7 (stack), §8 (data), §9 (architecture intent reverse-engineered).

## Per-section discovery questions

`en-foundation` walks the user through each section. Question scaling by depth:

| Section | Lightweight | Standard | Deep |
|---|---|---|---|
| §1 Executive | 1 | 2 | 3 |
| §2 Goals | 2 | 4 | 6 |
| §3 Users | 1 | 2 | 3 |
| §4 Decisions | as-they-arise | as-they-arise | as-they-arise |
| §5 Requirements | 3 | 6 | 10+ |
| §6 UX | 1 | 3 | 5 |
| §7 Stack | 3 | 5 | 7 |
| §8 Data | skipped | 3 | 6 |
| §9 Architecture | skipped | 2 | 5 |
| §10 API | 1 | 2 | 4 |
| §11–§13 | skipped | as-needed | required |
| §14 Risks | 1 | 2 | 4 |

One question per turn. Multiple-choice preferred where natural.

## Lint rules

`bin/ensemble-lint` checks:

- Frontmatter schema (Appendix C.1) — `project`, `type: foundation`, `status`, `created`, `updated`, `owner`, `depth` all present.
- R-IDs append-only (per `id-stability.r-renumbered`).
- All R-IDs cited by plans actually exist (cross-link integrity).
- Foundation length sanity check — body ≤ 5000 lines (soft P3 advisory at 3000).
