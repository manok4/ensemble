---
name: en-garden
description: "Doc-drift cleanup that runs automatically after every PR merge to main (event-driven, not scheduled). Runs lint, wiki-graph health checks, architecture-doc drift detection, plan-lifecycle drift, and pointer-map drift. Opens small targeted doc-only PRs that auto-merge after en-review (in mode:report-only) clears them. Strictly doc-only — code-level findings file to docs/plans/tech-debt-tracker.md instead. Five loop guards prevent self-trigger cascades. Default-safe security model (GITHUB_TOKEN least-privilege, no fork triggers, branch protection respected). Use when invoked manually for ad-hoc doc cleanup. Trigger phrases: 'garden', 'doc cleanup', 'fix doc drift', 'run garden', 'update architecture doc'."
---

# `/en-garden`

Doc-drift cleanup. Event-driven on `push` to `main` (post-PR-merge). Doc-only by contract; code-level findings go to `docs/plans/tech-debt-tracker.md`. Auto-merges its own PRs after `/en-review` (in `mode:report-only`) clears them.

> **Strict scope: doc-only.** Garden never modifies source code, configuration, tests, or any non-doc artifact. Enforced at runtime via `bin/ensemble-doc-only-check`.

## When invoked

| Trigger | Source |
|---|---|
| `push` to `main` | `.github/workflows/en-garden.yml` (installed by `/en-setup`) |
| Manual (`/en-garden`) | User runs the slash command |

The CI invocation routes through `bin/en-garden-ci` which resolves `claude -p` or `codex exec` (whichever is installed in the runner).

## Process

1. **Detect host.** Source `references/host-detect.md`. CI runner determines which CLI is available.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit. (Garden should not be invoked from inside a peer subprocess.)
3. **Loop guards** (per `references/garden-loop-guards.md`). The CI workflow enforces Guards 1, 2, 3, 5 before the skill runs; Guard 4 (no-material-diff) fires inside the skill at step 9.
4. **Run file-shape lint.** `bin/ensemble-lint --json --scope docs/`. Capture violations.
5. **Run wiki-graph lint.** Invoke `/en-learn --lint` (programmatically via the host's task primitive). Capture violations.
6. **Architecture drift check.** Dispatch `repo-research` to compare `docs/architecture.md` against the codebase:
   - Documented components still present?
   - Layer rules honored? (Code-level violations → tech-debt; doc-level → fix-up PR.)
   - Layer boundaries clean?
   - Per `references/garden-checks.md` and `references/architecture-update-rules.md`.
7. **Plan-lifecycle drift.** For each plan in `docs/plans/active/`, search for U-ID commit messages on `main`. If all units shipped → file as `chore(plans): move FRXX to completed/`.
8. **Pointer-map drift.** Compare `AGENTS.md` "Where things live" pointers against the actual `docs/` tree. Compare `CLAUDE.md` against `claude-md.no-shared-content` lint. File `chore(maps):` PRs for in-scope drift.
9. **Categorize findings strictly into doc batches; surface code-level findings to `tech-debt-tracker.md`.** Per `references/garden-checks.md`. Code-level findings get appended via the format in `references/tech-debt-tracker-format.md`.
10. **Guard 4 — no-material-diff termination.** If no batches were produced, exit silently (no PR, no comment).
11. **Stage + verify each batch.**
    - Apply the fixes for the batch (Edit / Write tools).
    - Run `bin/ensemble-doc-only-check` against the staged diff. **Any non-doc path → abort the batch; log loudly; do not create the PR.**
    - Cap the number of PRs per run at `max_prs_per_run` (default 6).
12. **Open PR per batch.**
    - Branch: `en-garden/<source-merge-sha-short>/<batch-name>` (e.g., `en-garden/a3f1b9c/architecture-update`).
    - PR title: `chore(<scope>): <one-line summary>`.
    - PR body: cites the source-PR SHA and the findings addressed.
    - PR label: `en-garden` (used by Guard 3).
13. **Run `/en-review` per PR.** Mode: `report-only` (mandatory; never configurable for garden). Returns findings JSON; does NOT mutate.
14. **Auto-merge eligibility check.**
    - `/en-review` returns no P0/P1 → eligible.
    - Branch protection allows (per `references/garden-security-model.md`) → enable auto-merge via `gh pr merge --auto --squash`.
    - Otherwise → leave PR open for human resolution.
15. **Summary report.** Post a comment on the source-triggering PR:
    ```markdown
    ## en-garden summary

    Ran 5 checks. Opened 3 doc-only PRs:
    - #102 — chore(arch): document new BillingService component
    - #103 — chore(plans): move FR05 to completed/
    - #104 — chore(learnings): add 4 missing back-refs

    All 3 passed `/en-review` and were auto-merged.

    Surfaced as judgment items (in PR comment, not auto-fixed):
    - 1 contradiction in `docs/learnings/patterns/`
    - 2 data-gap suggestions (sparse coverage on [performance, database])

    Code-level findings filed to tech-debt-tracker.md:
    - TD13: layer violation in src/services/notifications.ts
    - TD14: duplicated formatDate helper in src/utils/

    Run took: 4m 32s. Recursion depth: 1.
    ```
    Saved to `.ensemble/garden-summary.md` for the workflow's "Post summary on source PR" step.

## Strict scope: doc-only

The doc-only contract is enforced at three points:

1. **Categorization (step 9).** Code-level findings never become PRs; they file as TD entries.
2. **Runtime enforcement (step 11).** `bin/ensemble-doc-only-check` verifies every staged path is in the allowlist (`docs/`, `AGENTS.md`, `CLAUDE.md`, `.github/workflows/en-garden.yml`, `.ensemble/garden-summary.md`). Any path outside → abort the batch.
3. **Default-safe security** (per `references/garden-security-model.md`). `GITHUB_TOKEN` least-privilege; no `actions: write`; no fork triggers; branch protection respected; fail-closed on any guard error.

## Loop guards

Five guards prevent self-trigger cascades. Per `references/garden-loop-guards.md`:

1. Skip garden-authored commits (commit message prefix or author).
2. Concurrency group: only one garden run per branch at a time.
3. Garden PR labeling: skip merges of PRs labeled `en-garden`.
4. No-material-diff termination: silent exit if no batches.
5. Recursion depth cap: hard cap at depth 1.

## Auto-merge eligibility

A garden PR auto-merges when **all** hold:

- PR is doc-only (verified by `bin/ensemble-doc-only-check`).
- `/en-review` in `mode:report-only` returns no P0/P1 findings.
- CI checks pass (project tests, lint).
- Branch protection's review requirement is met.

Otherwise: PR stays open for human resolution.

## Cross-review

**Off** at the skill level. Each garden PR has its own quality gate via `/en-review` in `mode:report-only`.

## Reference files

- `references/host-detect.md` — host detection
- `references/garden-checks.md` — full check catalog (file-shape, wiki-graph, architecture, plan lifecycle, pointer maps)
- `references/garden-loop-guards.md` — five-guard mechanism
- `references/garden-security-model.md` — auto-merge safety, permissions, fork policy
- `references/tech-debt-tracker-format.md` — TD entry schema for code-level findings
- `references/architecture-update-rules.md` — what counts as material structural change
- `references/doc-lints.md` — file-shape lint catalog
- `references/learn-lint.md` — wiki-graph lint catalog
- `references/templates/github-workflow-en-garden.yml` — installed workflow
- `bin/en-garden-ci` — CI wrapper (claude -p / codex exec resolver)
- `bin/ensemble-doc-only-check` — runtime allowlist enforcement
- `bin/ensemble-lint` — file-shape lint runner

## Failure protocol

| Failure | Behavior |
|---|---|
| `bin/ensemble-doc-only-check` rejects a batch | Abort that batch; log loudly with offending paths; post to source PR comment |
| `repo-research` returns malformed output | Skip that check; surface in summary; continue with other checks |
| `/en-review` returns malformed JSON | Treat as inconclusive; leave PR open; do not auto-merge |
| Branch-protection check fails (rate-limit, auth) | Fail-closed: leave all PRs open; do not auto-merge |
| `gh pr create` fails | Skip that batch; surface error; continue |
| Workflow times out (default 30 min) | Whatever PRs were already created stay open; the rest are dropped; post summary noting truncation |
| LLM provider auth fails | CI step exits with clear error; no PRs created; manual user action required to fix secrets |
| Two batches conflict on the same file | Open them as separate PRs; let the second rebase against the first when it lands |

## Configuration

`~/.ensemble/config.json` keys:

```json
{
  "garden": {
    "ci_timeout_minutes": 30,
    "max_prs_per_run": 6,
    "auto_merge_enabled": true
  }
}
```

`auto_merge_enabled: false` lets the project run garden but require manual approval on every PR.

## What this skill never does

- **Never modifies source code, configuration, tests.** Doc-only contract.
- **Never spawns garden.** Guard 5 enforces.
- **Never bypasses branch protection.**
- **Never force-pushes.**
- **Never deletes branches** (post-merge cleanup is optional, off by default).
- **Never escalates permissions.**
