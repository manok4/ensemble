# Foundation discovery questions

The Q&A library `/en-foundation` draws from. **One question per turn; multiple-choice preferred where natural.**

> **Depth scaling.** Lightweight projects skip the data/architecture/security tiers; Standard does most; Deep does all.

## §1 Executive — product identity & problem

| Q | Notes |
|---|---|
| What is this product, in one sentence? | Foundation §1 first paragraph |
| Who is it for (primary user)? | One short answer |
| What's the smallest version that's still valuable? | Anchors scope |
| What changes if this exists vs doesn't? | Surfaces real value |
| Why now? | Surfaces forcing function (or absence) |

## §2 Goals & §14 Risks

| Q | Notes |
|---|---|
| What are the top 3–6 goals? | Append G-IDs as user lists |
| What's explicitly out of scope? | Non-goals |
| What's the top risk? | Seeds §14 |
| What's the most aspirational thing — even if we drop it later? | Surfaces scope ambition |

## §3 Users & roles

| Q | Notes |
|---|---|
| Just one user role, or multiple? | Branches: solo vs multi-actor |
| For multi-actor: name and one-line description for each? | A-IDs assigned |
| Any external stakeholders? | E.g., admins, ops, partners |

## §5 Functional Requirements

| Q | Notes |
|---|---|
| What are the must-have capabilities? | R-IDs assigned as user lists |
| For each: an acceptance example (Given/When/Then)? | AE-IDs assigned |
| Are there should-have capabilities for v1? | More R-IDs |
| What capabilities are explicitly out of scope? | Non-goals |

## §6 User Experience

| Q | Notes |
|---|---|
| What are the top 3–5 user flows? | F-IDs assigned |
| Any non-standard interaction patterns? | Surfaces UX choices |
| Mobile? Web? Both? Native? | Platform shape |

## §7 Technical Direction

| Q | Notes |
|---|---|
| Language constraint? | TS, Python, Go, etc. |
| Framework constraint? | React, Next.js, Rails, etc. |
| Database constraint? | Postgres, SQLite, etc. |
| Hosting constraint? | Vercel, Cloudflare, AWS, self-host |
| Auth constraint? | Clerk, Auth0, custom, none |
| Any sacred cows? | Things that can't change |

## §8 Data Architecture (Standard / Deep)

| Q | Notes |
|---|---|
| What are the top entities? | Foundation §8.1 |
| Single-tenant, multi-tenant, or per-row tenancy? | Foundation §8.2 |
| Migration strategy? | Foundation §8.3 |
| Data residency / compliance constraints? | Privacy, GDPR, HIPAA |

## §9 Architecture intent (Standard / Deep)

| Q | Notes |
|---|---|
| Top-level component shape (services, modules)? | §9.1 |
| Layer rules — what can call what? | §9.2 |
| External integrations on day 1? | §9.3 |

## §10 API Surface

| Q | Notes |
|---|---|
| Public API (REST, GraphQL, RPC)? | §10.1 |
| Internal contracts to lock down? | §10.2 |

## §11 Deployment & Infra (Deep)

| Q | Notes |
|---|---|
| Deploy target and topology? | Single-region, multi-region, edge, etc. |
| CI/CD constraints? | GitHub Actions, etc. |
| Observability stack? | Logging, metrics, tracing |

## §13 Security & Privacy (Deep)

| Q | Notes |
|---|---|
| Auth model? | Token, session, JWT, OAuth |
| Permission boundaries? | Roles, ABAC, RBAC |
| Sensitive data handling? | Encryption at rest/in transit, PII |

## Approval check

Before writing the foundation:

> "Here's a structured summary of what we've discovered. Ready to write `docs/foundation.md`? (y/n, or call out anything to revise)"

## Question style guidelines

- **One per turn.** Don't bundle.
- **Multiple-choice when natural.** Open-ended when the answer is genuinely free-form.
- **Default to short answers.** Push back on rambling answers.
- **Watch for redundancy.** If `repo-research` already surfaced the stack, don't ask "what stack?" — confirm with: "The repo uses TypeScript + Bun. Confirm or change?"
- **Skip rituals.** No "Are you ready?" or "Tell me more about..."

## Depth-scaled question count

| Depth | Total questions across foundation discovery |
|---|---|
| Lightweight | 8–12 |
| Standard | 18–28 |
| Deep | 30–45 |

If question count is exceeding the band, surface it: "We're at 25 questions; want to wrap and write a draft, or keep going?"
