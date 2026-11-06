# Diff-signal detection

Shared reading of a change's risk surface and frontend reach, consumed by `/en-fix` (risk surface at triage and on the real diff), `/en-qa` (browser-phase detector) and `/en-review` (what a conditional persona's keyword means). One definition so the skills can't drift apart. `ensemble-review-tier` owns review depth; this file does not decide it.

> **Fail-closed is the contract.** Every classification below defaults to the *safe, do-more* answer when any input is unknown. "No risk" and "no-frontend" are privileges a diff earns by being unambiguous; ambiguity revokes them.

## Inputs

Compute from the diff under review (`git diff <base>...HEAD`, or the staged/working set when no base):

- `FRONTEND_FILES` — changed files that can change what a user sees or does in a browser, read as below.
- `RISK_SIGNALS` — risk-surface patterns present in the diff (paths or content) below.

## Frontend / UI patterns (drives en-qa browser phase)

A changed file is a **candidate** if its path matches any of:

- Extensions: `.tsx`, `.jsx`, `.vue`, `.svelte`, `.astro`
- `.css`, `.scss`, `.sass`, `.less`, styled-components / CSS-in-JS files
- Directory segments: `components/`, `ui/`, `pages/`, `views/`, `app/` (Next.js app router), `src/routes/` (SvelteKit), `templates/`, `public/`, `static/`, `assets/`
- HTML files: `.html`, `.htm`
- Client entrypoints: `main.tsx`, `index.tsx`, `App.tsx`, and framework equivalents

**A path match is a candidate, not an answer.** Read each changed file and ask whether it can change what a user sees or does in a browser:

- **Not a frontend file:** a match that means something else, such as a backend handler under `app/api/` whose response no page reads differently, `static/robots.txt`, or a `templates/` folder that renders no page.
- **A frontend file with no match:** client code a page depends on, such as `src/hooks/useCart.ts`, a client store, or a client API wrapper. Also a backend change to a response a page displays.
- **Unsure what it affects:** a frontend file. This is where fail-closed applies.

## Risk-surface patterns (drives en-fix's plan check)

A diff has a **risk signal** when changed paths or changed lines touch any of:

- **Auth / authz:** `auth`, `login`, `session`, `token`, `password`, `oauth`, `permission`, `rbac`, `acl`, middleware guarding routes.
- **Payments / money:** `payment`, `billing`, `charge`, `invoice`, `stripe`, `refund`, commission/disbursement logic.
- **Migrations / schema:** `migrations/`, `alembic/`, `schema`, `ALTER`, `DROP`, `CREATE TABLE`, model/entity field definitions.
- **External effects:** outbound HTTP, email/SMS/webhook/Slack sends, third-party API clients, queue producers.
- **Secrets / config:** `.env` handling, secret/key material, security headers (CORS, CSP), cookie config.
- **Data mutation at scale:** bulk `UPDATE`/`DELETE`, backfills, ETL writes.

**A pattern names a concept, not a substring.** Read each hit and ask whether it refers to that concept:

- **Not a signal:** another meaning of the word, such as `max_tokens`, a lexer token or a design token for `token`, `author` for `auth`, `oracle` for `acl`, or a database client's `session`.
- **Not a signal:** a word that appears only in a comment, in documentation, or in a test's name or description.
- **Still a signal:** a string literal, because SQL, URLs and header names live in strings. Also a path segment, and a test that asserts the surface's behaviour.
- **Unsure what it refers to:** a signal. This is where fail-closed applies.

## Classifications

### `needs_browser` (en-qa Phase 2 eligibility)

`true` when `FRONTEND_FILES > 0`. Otherwise `false` — **but** the caller's explicit `--browser` flag forces `true` regardless, and an undetermined diff (can't compute `FRONTEND_FILES`, e.g. no base ref) is treated as `true` (fail closed — run the browser pass rather than skip it).

## Why fail-closed

The cost asymmetry is the whole point. A false "no risk" skips a plan that a change needed; a false "no-frontend" skips QA that a change needed. Both ship a regression. A false "risk" / "needs-browser" only spends a few extra minutes. When unsure, spend the minutes.
