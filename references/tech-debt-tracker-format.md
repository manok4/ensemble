# `docs/plans/tech-debt-tracker.md` format

The canonical place for "noticed but deferred" items. Append-only, with stable TD-IDs. Read by `/en-plan` when planning new work.

## File structure

```markdown
---
type: tech-debt-tracker
generated: false
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# Tech debt tracker

> Noticed-but-deferred items. Append-only; do not renumber TD-IDs.
> `/en-plan` reads this when planning new work and may cite items
> via `Resolves: TD<n>` in unit metadata.

## Open

### TD1. <Title>

- **Source:** <skill-or-actor> review of <unit/plan/branch/file>
- **Severity:** P1
- **Confidence:** 7/10
- **Location:** `src/auth/refresh.ts:42`
- **Why it matters:** <1-2 sentence rationale>
- **Suggested fix:** <concrete description>
- **Logged:** YYYY-MM-DD

### TD2. ...

## Resolved

### TD<n>. <Title>

- (same fields)
- **Resolved:** YYYY-MM-DD by `<commit-sha>` in `docs/plans/completed/FRXX-<name>.md`
```

## Field rules

| Field | Required | Notes |
|---|---|---|
| `Source` | yes | Who logged this (e.g., "en-review on FR07-U3", "en-garden architecture drift", "user manual entry") |
| `Severity` | yes | P0–P3 from `references/severity.md` |
| `Confidence` | yes | 1–10 |
| `Location` | yes | `<file>:<line>` for code; `<section>` for docs; `global` for cross-cutting |
| `Why it matters` | yes | 1–2 sentences |
| `Suggested fix` | yes | Concrete description |
| `Logged` | yes | `YYYY-MM-DD` (date the entry was added) |
| `Resolved` | for resolved entries | `YYYY-MM-DD by <commit-sha> in <plan-path>` |

## TD-ID stability

TD-IDs are **append-only** (per `references/stable-ids.md`):

- Never renumber. Never delete.
- When resolved, move the entry from `## Open` to `## Resolved`. Keep the same TD-ID.
- When a duplicate is filed (same finding from two sources), merge the source citations into a single entry; keep the lowest TD-ID.

`bin/ensemble-lint`'s `id-stability.td-renumbered` rule (P1) flags any change.

## Who appends

| Actor | When |
|---|---|
| `/en-plan` | When deferring planning work that came up but is out of scope |
| `/en-build` | When a peer-review finding is "agree but defer" (per `references/severity.md`) |
| `/en-review` | When a finding is `gated_auto`/`manual` but the user defers |
| `/en-garden` | When a code-level finding surfaces (architecture drift, layer violation) — garden never modifies code, so all code-level findings come here |
| User | Manual entries are fine; just follow the format |

## Who resolves

| Actor | How |
|---|---|
| `/en-build` | Cites `Resolves: TD<n>` in unit metadata; commit body cites the TD-ID |
| `/en-learn capture` | When the plan that resolves the TD ships, marks it resolved (move to `## Resolved`, add `Resolved: <date> by <sha>` field) |
| `/en-garden` | Hygiene pass: re-checks resolved TDs match the cited commits; flags mismatches (`tech-debt.resolved-not-found`) |

## Heuristics for what qualifies

Goes in tracker:

- ✓ Concrete code-level finding with a clear location and fix.
- ✓ Architecture-rule violation that wasn't caught at review time.
- ✓ Test coverage gap for a non-critical path.
- ✓ Naming inconsistency that spans multiple files.
- ✓ Library / dep upgrade that the team agreed to defer.

Doesn't go in tracker:

- ✗ "Code could be cleaner" without a specific location or fix — too vague.
- ✗ Style preferences without a project standard backing them.
- ✗ Speculative refactors ("we might want to extract X someday").
- ✗ Doc-only items — those are handled by `/en-garden` directly, not tracked here.

When in doubt, surface to user: "Defer to tech-debt-tracker, ignore, or fix now?"

## Worked example

```markdown
## Open

### TD11. Refresh token error path doesn't surface user-friendly message

- **Source:** en-review on FR07-U3 (peer finding, not applied)
- **Severity:** P2
- **Confidence:** 7/10
- **Location:** `src/auth/refresh.ts:78` (catch block)
- **Why it matters:** When the refresh token is malformed (rare but possible), the user sees a generic "auth error" instead of a targeted "please sign in again" — leads to support tickets.
- **Suggested fix:** Branch on the specific error type (`MalformedTokenError` vs others); render a targeted message in the auth UI.
- **Logged:** 2026-04-26

### TD12. Inconsistent test naming in src/auth/

- **Source:** en-garden lint pass
- **Severity:** P3
- **Confidence:** 6/10
- **Location:** `src/auth/*.test.ts` (4 files)
- **Why it matters:** Half use `describe()` blocks, half use top-level `test()` calls. New tests pick up the local pattern; convention drifts.
- **Suggested fix:** Pick one (project convention is `describe()`); migrate the four outliers in a refactor PR.
- **Logged:** 2026-04-28

## Resolved

### TD7. N+1 query in dashboard render path

- **Source:** en-review on FR05-U2 (peer finding, deferred)
- **Severity:** P1
- **Confidence:** 9/10
- **Location:** `src/dashboard/render.ts:124`
- **Why it matters:** Loop calls `findUserById` per row; produces N+1.
- **Suggested fix:** Batch via `findManyUsersByIds`.
- **Logged:** 2026-04-15
- **Resolved:** 2026-04-22 by `e8a23b1` in `docs/plans/completed/FR06-dashboard-perf.md`
```

## Lint rules

`bin/ensemble-lint` checks:

- `id-stability.td-renumbered` — TD-IDs append-only.
- `cross-link.broken-td` — `Resolves: TD<n>` cites a TD-ID that doesn't exist in the tracker.
- `tech-debt.resolved-not-found` (advisory) — a `Resolved:` line cites a commit-sha that doesn't exist on `main` (catches typos and reverted commits).
