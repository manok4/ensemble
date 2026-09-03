# Sweep checks — what `/en-sweep` audits

The catalog of doc-drift checks `/en-sweep` runs on every PR-merge pass. Findings within scope (doc-only) become fix-up PRs; findings out of scope (code-level) get filed to `docs/plans/tech-debt-tracker.md`.

> **Strict scope: doc-only.** Sweep never modifies source code, configuration, tests, or any non-doc artifact. Anything code-level becomes a tech-debt entry.

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
| `CLAUDE.md` body has content that duplicates `AGENTS.md` (per `claude-md.no-shared-content` lint) | `chore(maps): remove duplicate content in CLAUDE.md` (in scope) — only if the duplication is mechanical to remove |
| Project commands changed (e.g., new `package.json` script for `lint`) | `chore(maps): update project commands in AGENTS.md` (in scope) |

### F. Tech-debt-tracker hygiene

| Check | Action |
|---|---|
| TD entries with no `Logged:` date | `chore(plans): backfill log dates in tech-debt-tracker.md` (in scope) |
| TD entries cited as `Resolves: TD<n>` in completed plans | Mark resolved in tech-debt-tracker.md (in scope) |
| Duplicate TD entries (same finding from multiple sources) | Merge; preserve all source citations (in scope) |

## Code-level findings (out of scope; → tech-debt-tracker)

When `/en-sweep`'s checks surface a code-level pattern, **never** open a fix-up PR. Instead, append an entry to `docs/plans/tech-debt-tracker.md` per `references/tech-debt-tracker-format.md`:

| Code-level finding | TD entry |
|---|---|
| Layer-rule violation in source | "Module X imports from forbidden layer Y" |
| Duplicated helper across multiple files | "`formatDate` duplicated in src/utils/ and src/lib/" |
| Hand-rolled util that has a shared equivalent | "`debounce` in src/components/ should use shared shared/throttle.ts" |
| Test coverage gap surfaced by code analysis | "Payment retry path has no test coverage" |

`/en-plan` reads `tech-debt-tracker.md` when planning new work and can cite TD-IDs in unit metadata.

## PR batching

Sweep's findings are grouped into batches; one PR per batch. Naming convention:

| Batch | Branch | PR title |
|---|---|---|
| Lint fixes | `en-sweep/<sha>/lint-fixes` | `chore(sweep): fix N lint findings` |
| Wiki cross-refs | `en-sweep/<sha>/learnings-back-refs` | `chore(learnings): add N missing back-refs` |
| Architecture | `en-sweep/<sha>/architecture-update` | `chore(arch): document <X>` |
| Plans | `en-sweep/<sha>/plan-lifecycle` | `chore(plans): move N plans to completed/` |
| Maps | `en-sweep/<sha>/map-update` | `chore(maps): update AGENTS.md pointers` |
| Tech-debt hygiene | `en-sweep/<sha>/td-hygiene` | `chore(plans): tech-debt-tracker hygiene` |

`max_prs_per_run` (default 6) caps the number of PRs sweep opens in a single run.

## Branch naming

`en-sweep/<source-merge-sha-short>/<batch-name>` (e.g., `en-sweep/a3f1b9c/architecture-update`).

The `<source-merge-sha-short>` is the SHA of the merge that triggered the run. Lets the user trace which PR sweep was responding to.

## Per-PR review

Each sweep PR runs `/en-review` in `mode:report-only`:

- Returns findings JSON without mutating.
- Sweep parses; if no P0/P1, auto-merges.
- Any P0/P1 → PR stays open for human resolution.

## Continuous monitoring (opt-in, per `sweep.continuous_monitoring.*`)

When enabled in `.ensemble/config.local.yaml`, sweep runs its `continuous-monitor` helper after the file-shape and wiki-graph checks. The monitor scans for:

- **Dead code** — uses project tools when available (`ts-prune` for TS/JS, `vulture` for Python, `golang.org/x/tools/cmd/deadcode` for Go).
- **Dependency vulnerabilities** — wraps `npm audit` / `pip-audit` / `cargo audit`.

Output is JSON-lines normalized to a common shape (per the head of that helper).

### Triage by size

Sweep's `triage-findings` helper partitions monitor output into three buckets:

| Bucket | Criteria | Artifact created |
|---|---|---|
| **TD entry** (trivial / mechanical) | Single dead function; dep-vuln with auto-fix; loc_estimate < `auto_plan_threshold_loc`; <`auto_plan_threshold_locations` files affected | Append to `docs/plans/tech-debt-tracker.md` with marker `Filed by /en-sweep (continuous-monitor)` |
| **Draft plan** (pattern / decision-required) | ≥`auto_plan_threshold_locations` dead-code findings clustered in same dir; severe CVE without auto-fix | Write to `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` with `status: draft`, `generator: en-sweep` |
| **Skipped** | Uncategorizable / under threshold | Logged in summary; not surfaced |

**Caps:** `sweep.max_drafts_per_run` (default 3). Overflow rolls to TD with a "would have been a plan" note. Without this cap, a single sweep run could flood `docs/plans/active/` with stale-symbol plans.

**Idempotency:** before writing a draft plan, sweep checks `docs/plans/active/` for an existing plan with `generator: en-sweep` and matching `area:`. If present, skip — the user is presumably reviewing the existing draft. Prevents duplicate plans on every merge.

### Auto-generated draft plan format

```yaml
---
type: plan
plan_type: improvement | bug
plan_id: <PREFIX><NN>
title: Remove dead helpers in src/utils/
status: draft
location: active
created: <YYYY-MM-DD>
covers_requirements: []
requirements_pending: true
peer_review_verdict:
depth: lightweight
generator: en-sweep                    # ← marks auto-generated
generator_run: a3f1b9c                  # ← merge SHA that triggered
generator_checks: [dead-code]
area: src/utils/
---
```

The `generator` field is informational; lint is lenient on `covers_requirements: []` for plans where `generator` is set, since they originate from automation rather than from a user-driven foundation R-ID.

### User exit paths from a draft plan

| Decision | Action |
|---|---|
| Accept as-is | Flip `status: draft → open`. `/en-build` picks it up next. |
| Flesh out into a real plan | `/en-plan --resume docs/plans/active/<plan>.md` — preserves the plan_id, runs research and peer review, generates U-IDs |
| Decline | Move file to `docs/plans/archive/` with `status: abandoned` plus a note |

## Reference files

- `references/doc-lints.md` — file-shape lint rules
- `references/learn-lint.md` — wiki-graph health checks
- `references/architecture-update-rules.md` — material vs non-material changes
- `references/sweep-loop-guards.md` — preventing self-trigger cascades
- `references/sweep-security-model.md` — auto-merge safety
- `references/tech-debt-tracker-format.md` — TD entry schema
- `bin/ensemble-doc-only-check` — runtime allowlist enforcement
- `continuous-monitor` (carried by `/en-sweep`) — dead-code + dep-audit scanner
- `triage-findings` (carried by `/en-sweep`) — partitions findings into TD vs draft plan
