# Garden checks — what `/en-garden` audits

The catalog of doc-drift checks `/en-garden` runs on every PR-merge pass. Findings within scope (doc-only) become fix-up PRs; findings out of scope (code-level) get filed to `docs/plans/tech-debt-tracker.md`.

> **Strict scope: doc-only.** Garden never modifies source code, configuration, tests, or any non-doc artifact. Anything code-level becomes a tech-debt entry.

## Categories of check

### A. File-shape lints (`bin/ensemble-lint`)

Runs the full lint catalog from `references/doc-lints.md`:

- Frontmatter validity, ID stability, cross-link integrity, status correctness, no-absolute-paths, freshness, generated-file integrity, index coverage, CLAUDE.md discipline, length budgets.

**In scope for fix-up PR:** `safe_auto` findings (broken cross-link repair when target is obvious; missing required frontmatter fields; CLAUDE.md cross-reference repair; status-location sync; index regeneration).

**Out of scope:** None — lint findings are all doc-shape.

### B. Wiki-graph health (`/en-learn --lint`)

Per `references/learn-lint.md`:

- Orphans, missing back-refs, broken links, contradictions, missing pages, stale references, index drift, log drift, data gaps.

**In scope:** Mechanical fixes (`--fix` auto-applies): missing back-refs, broken-link repair, index regen, log append.

**Out of scope:** Judgment items (orphans, contradictions, missing-page candidates, data-gap suggestions) — surfaced as a comment on the source PR for human attention.

### C. Architecture drift (`docs/architecture.md` vs codebase)

Dispatch `repo-research` to scan the current codebase and compare against `docs/architecture.md`:

| Check | Detection | Action |
|---|---|---|
| Documented component still present | Look for files matching the component's "Key files" | Missing → `chore(arch): remove <X> from architecture.md` (in scope) |
| Undocumented component | Top-level dir under `src/`/`lib/` not listed in architecture.md's Components table | New → `chore(arch): document new <X> component` (in scope) |
| Layer rule violation | If layer rules are documented (e.g., "service can't import route helpers"), grep for forbidden imports | Violation in source → file as TD entry (out of scope; tech-debt-tracker) |
| Dependency direction shift | Documented dep direction vs `package.json` dependencies + import graph | Shift → `chore(arch): update dependency-direction note` (in scope) |
| Freshness | `updated:` field >30 days (configurable) | Stale → `chore(arch): refresh from current code` (in scope; only if material change found) |

### D. Plan lifecycle drift (`docs/plans/active/` vs git log)

For each plan in `docs/plans/active/`:

- Check if all units' commits exist on `main` (search by U-ID in commit messages).
- All units shipped → `chore(plans): move FRXX to completed/` (in scope).
- Some units shipped, some not → leave the plan in `active/`; surface in summary.

This catches the case where the user shipped without invoking `/en-learn` to flip the plan.

### E. Pointer-map drift (`AGENTS.md` / `CLAUDE.md` vs current `docs/`)

| Check | Action |
|---|---|
| `AGENTS.md` "Where things live" cites a path that no longer exists | `chore(maps): remove stale pointer in AGENTS.md` (in scope) |
| New top-level docs/ directory (e.g., first `docs/references/` after a `learn --pack`) not in `AGENTS.md` | `chore(maps): add pointer for docs/<X>/` (in scope) |
| `CLAUDE.md` body has content that duplicates `AGENTS.md` (per `claude-md.no-shared-content` lint) | `chore(maps): remove duplicate content in CLAUDE.md` (in scope) — only if the duplication is mechanical to remove |
| Project commands changed (e.g., new `package.json` script for `lint`) | `chore(maps): update project commands in AGENTS.md` (in scope) |

### F. Tech-debt-tracker hygiene

| Check | Action |
|---|---|
| TD entries with no `Logged:` date | `chore(plans): backfill log dates in tech-debt-tracker.md` (in scope) |
| TD entries cited as `Resolves: TD<n>` in completed plans | Mark resolved in tech-debt-tracker.md (in scope) |
| Duplicate TD entries (same finding from multiple sources) | Merge; preserve all source citations (in scope) |

## Code-level findings (out of scope; → tech-debt-tracker)

When `/en-garden`'s checks surface a code-level pattern, **never** open a fix-up PR. Instead, append an entry to `docs/plans/tech-debt-tracker.md` per `references/tech-debt-tracker-format.md`:

| Code-level finding | TD entry |
|---|---|
| Layer-rule violation in source | "Module X imports from forbidden layer Y" |
| Duplicated helper across multiple files | "`formatDate` duplicated in src/utils/ and src/lib/" |
| Hand-rolled util that has a shared equivalent | "`debounce` in src/components/ should use shared shared/throttle.ts" |
| Test coverage gap surfaced by code analysis | "Payment retry path has no test coverage" |

`/en-plan` reads `tech-debt-tracker.md` when planning new work and can cite TD-IDs in unit metadata.

## PR batching

Garden's findings are grouped into batches; one PR per batch. Naming convention:

| Batch | Branch | PR title |
|---|---|---|
| Lint fixes | `en-garden/<sha>/lint-fixes` | `chore(docs): fix N lint findings` |
| Wiki cross-refs | `en-garden/<sha>/learnings-back-refs` | `chore(learnings): add N missing back-refs` |
| Architecture | `en-garden/<sha>/architecture-update` | `chore(arch): document <X>` |
| Plans | `en-garden/<sha>/plan-lifecycle` | `chore(plans): move N plans to completed/` |
| Maps | `en-garden/<sha>/map-update` | `chore(maps): update AGENTS.md pointers` |
| Tech-debt hygiene | `en-garden/<sha>/td-hygiene` | `chore(plans): tech-debt-tracker hygiene` |

`max_prs_per_run` (default 6) caps the number of PRs garden opens in a single run.

## Branch naming

`en-garden/<source-merge-sha-short>/<batch-name>` (e.g., `en-garden/a3f1b9c/architecture-update`).

The `<source-merge-sha-short>` is the SHA of the merge that triggered the run. Lets the user trace which PR garden was responding to.

## Per-PR review

Each garden PR runs `/en-review` in `mode:report-only`:

- Returns findings JSON without mutating.
- Garden parses; if no P0/P1, auto-merges.
- Any P0/P1 → PR stays open for human resolution.

## Reference files

- `references/doc-lints.md` — file-shape lint rules
- `references/learn-lint.md` — wiki-graph health checks
- `references/architecture-update-rules.md` — material vs non-material changes
- `references/garden-loop-guards.md` — preventing self-trigger cascades
- `references/garden-security-model.md` — auto-merge safety
- `references/tech-debt-tracker-format.md` — TD entry schema
- `bin/ensemble-doc-only-check` — runtime allowlist enforcement
