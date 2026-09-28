# Diff-signal detection

Shared classification of a change's size and risk surface, consumed by `/en-review` (`--lite` gate, effort ladder) and `/en-qa` (browser-phase detector). One definition so the two skills can't drift apart.

> **Fail-closed is the contract.** Every classification below defaults to the *safe, do-more* answer when any input is unknown. "Small" and "no-frontend" are privileges a diff earns by being unambiguous; ambiguity revokes them.

## Inputs

Compute from the diff under review (`git diff <base>...HEAD`, or the staged/working set when no base):

- `EXEC_LINES` — count of changed **executable code** lines (added + removed), excluding blank lines and comment-only lines.
- `UNCOUNTED_FILES` — count of changed files that are **not** countable source code: `.md`, `.txt`, JSON/YAML/TOML config, `.sh`, CI workflow files, lockfiles, generated files, binary assets. (These have no meaningful "executable line" count, so their risk can't be sized — they force the safe path.)
- `FRONTEND_FILES` — changed files matching the frontend/UI patterns below.
- `RISK_SIGNALS` — risk-surface patterns present in the diff (paths or content) below.

## Frontend / UI patterns (drives en-qa browser phase)

A changed file is a **frontend file** if its path matches any of:

- Extensions: `.tsx`, `.jsx`, `.vue`, `.svelte`, `.astro`
- `.css`, `.scss`, `.sass`, `.less`, styled-components / CSS-in-JS files
- Directory segments: `components/`, `ui/`, `pages/`, `views/`, `app/` (Next.js app router), `src/routes/` (SvelteKit), `templates/`, `public/`, `static/`, `assets/`
- HTML files: `.html`, `.htm`
- Client entrypoints: `main.tsx`, `index.tsx`, `App.tsx`, and framework equivalents

When `FRONTEND_FILES == 0` the change cannot affect rendered UI, so a browser pass has nothing to exercise.

## Risk-surface patterns (drives en-review lite gate)

A diff has a **risk signal** when paths or content touch any of:

- **Auth / authz:** `auth`, `login`, `session`, `token`, `password`, `oauth`, `permission`, `rbac`, `acl`, middleware guarding routes.
- **Payments / money:** `payment`, `billing`, `charge`, `invoice`, `stripe`, `refund`, commission/disbursement logic.
- **Migrations / schema:** `migrations/`, `alembic/`, `schema`, `ALTER`, `DROP`, `CREATE TABLE`, model/entity definitions.
- **External effects:** outbound HTTP, email/SMS/webhook/Slack sends, third-party API clients, queue producers.
- **Secrets / config:** `.env` handling, secret/key material, security headers (CORS, CSP), cookie config.
- **Data mutation at scale:** bulk `UPDATE`/`DELETE`, backfills, ETL writes.

## Classifications

### `is_low_risk` (en-review `--lite` eligibility)

`true` only when **both** hold:

- `RISK_SIGNALS` is empty
- (caller adds: no conditional review personas were independently triggered)

Otherwise `false` — **fail closed**. Size is deliberately not an input: `--lite` is the user saying "this is a quick fix", and a fix with its regression test and a changelog line is still quick. What the user cannot waive is the risk surface, so any risk signal forces `false`. A `--lite` request does not override a `false` result; the gate wins.

**Canonical override-reason identifiers.** When a `--lite` request is overridden, the caller reports WHY using these stable enum values (one per failed condition; `/en-review`'s `lite_gate:` outcome line consumes them verbatim):

| Reason ID | Failed condition |
|---|---|
| `risk-signal` | `RISK_SIGNALS` non-empty |
| `conditional-persona:<names>` | (caller-added, en-review) a conditional review persona fired independently; `<names>` is the alphabetically-sorted `+`-joined persona list, e.g. `conditional-persona:performance+security` |

When multiple conditions fail, report all of them, deduplicated, in the fixed table order above, comma+space separated — one deterministic encoding so equivalent runs produce identical output.

### `is_small_and_safe` (en-review effort ladder, rung 2)

`true` only when **all** hold: `EXEC_LINES` is known AND `1 <= EXEC_LINES <= 39`; `UNCOUNTED_FILES == 0`; `RISK_SIGNALS` is empty. Otherwise `false` — **fail closed**: an unknown line count, ANY uncounted file (a 5-line code change plus one `.md` → not small), or any risk signal. `/en-review`'s effort ladder resolves `low` on it without a `--lite` flag; it is the diff earning the cheap tier on its own.

### `needs_browser` (en-qa Phase 2 eligibility)

`true` when `FRONTEND_FILES > 0`. Otherwise `false` — **but** the caller's explicit `--browser` flag forces `true` regardless, and an undetermined diff (can't compute `FRONTEND_FILES`, e.g. no base ref) is treated as `true` (fail closed — run the browser pass rather than skip it).

## Why fail-closed

The cost asymmetry is the whole point. A false "low-risk" gives a lite read to a change that needed the full one; a false "no-frontend" skips QA that a change needed. Both ship a regression. A false "not-small" / "needs-browser" only spends a few extra minutes. When unsure, spend the minutes.
