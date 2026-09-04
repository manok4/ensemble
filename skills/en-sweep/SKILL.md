---
name: en-sweep
description: "Scheduled doc-drift cleanup: file-shape lint, wiki-graph health, architecture and plan-lifecycle drift, then an auto-merging doc-only PR once review clears it. Skips when nothing new landed. Trigger phrases: 'sweep', 'doc cleanup', 'fix doc drift', 'run sweep'."
disable-model-invocation: true
---


# `/en-sweep`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Doc-drift cleanup. **Scheduled** (default weekly) with an activity gate that skips runs when no non-sweep commits have landed since the last sweep. Doc-only by contract; code-level findings go to `docs/plans/tech-debt-tracker.md`. Auto-merges its own PRs after `/en-review` (in `mode:report-only`) clears them.

> **Strict scope: doc-only.** Sweep never modifies source code, configuration, tests, or any non-doc artifact. Enforced at runtime via `$SKILL_DIR/scripts/ensemble-doc-only-check`.

> **Peer contract.** Severity, confidence, autofix class, the `peer_decision`
> object and its reason enum are defined once in `references/peer-contract.md`
> and are byte-identical across every skill that exchanges findings. What this
> skill *does* with a finding is its own policy, not part of that contract.

## When invoked

| Trigger | Source |
|---|---|
| Scheduled cadence | `.github/workflows/en-sweep.yml` cron (set during `/en-setup`; default `0 9 * * 1` — weekly Mon 9am UTC). Configurable: `daily` / `weekly` / `monthly` named values, or any literal cron expression. |
| `workflow_dispatch` | Manual fire from the Actions UI; bypasses the activity gate. |
| Manual (`/en-sweep`) | User runs the slash command locally for ad-hoc cleanup. |

**Activity gate.** Before the sweep job runs, `$SKILL_DIR/scripts/ensemble-sweep-activity-check` walks `git log` for the most recent sweep-authored commit on `main` (matches the scopes `chore(sweep):`, `chore(arch):`, `chore(plans):`, `chore(learnings):`, `chore(maps):`) and counts non-sweep commits since then. If zero, the sweep job is skipped silently: no LLM calls, no PRs, no comments. Manual `workflow_dispatch` always bypasses the gate.

**Every scope in that list has to be one sweep authors and a human would not.** A shared scope makes the gate read a human commit as sweep's own in two places at once, picking it as `LAST_SWEEP_SHA` and subtracting it from the count. Both errors skip the cycle. `chore(docs):` was in the list until 2026-09-03 and did exactly that, so the lint batch now ships as `chore(sweep):`.

The CI invocation routes through `$SKILL_DIR/scripts/en-sweep-ci` which resolves `claude -p` or `codex exec` (whichever is installed in the runner), registers the freshly-cloned plugin (`--plugin-dir "$ENSEMBLE_PLUGIN_DIR"`) so the `en-sweep` skill resolves, and **guards the result**: if the CLI returns a no-op envelope (`num_turns: 0`, `is_error: true`, or `result` containing "Unknown command"), the wrapper exits non-zero so the job fails loudly instead of going green-but-inert. (Field bug FR01 U11: prior runs passed weekly while doing nothing because the skill was never registered.)

## Process

1. **No host detection.** In CI, `$SKILL_DIR/scripts/en-sweep-ci` has already picked the CLI; interactively, the host's own tools apply. The skill reads no host or peer variable and carries no detection files.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit. (Sweep should not be invoked from inside a peer subprocess.)
3. **Loop guards** (per `references/sweep-loop-guards.md`). The workflow enforces Guard 1 (concurrency group) and Guard 3 (recursion depth cap) before the skill runs. Guard 2 (no-material-diff) fires inside the skill, at step 10.
4. **Run file-shape lint.** `bin/ensemble-lint --json --scope docs/`. Capture violations.
5. **Run wiki-graph lint.** Invoke `/en-learn --lint` (programmatically via the host's task primitive). Capture violations.
6. **Architecture drift check.** Dispatch `repo-research` to compare `docs/architecture.md` against the codebase:
   - Documented components still present?
   - Layer rules honored? (Code-level violations → tech-debt; doc-level → fix-up PR.)
   - Layer boundaries clean?
   - Per `references/sweep-checks.md` and `references/architecture-update-rules.md`.
7. **Plan-lifecycle drift.** For each plan in `docs/plans/active/`, search for U-ID commit messages on `main`. If all units shipped → file as `chore(plans): move <plan_id> to completed/` (e.g. `move EN03 to completed/`).
8. **Pointer-map drift.** Compare `AGENTS.md` "Where things live" pointers against the actual `docs/` tree. Compare `CLAUDE.md` against `claude-md.no-shared-content` lint. File `chore(maps):` PRs for in-scope drift.
8a. **Continuous monitoring (opt-in).** If `.ensemble/config.local.yaml` has `sweep.continuous_monitoring.dead_code: true` or `dep_audit: true`, run `$SKILL_DIR/scripts/continuous-monitor` and pipe through `$SKILL_DIR/scripts/triage-findings`. The triage output partitions findings into:
    - `td_entries` — trivial / mechanical (single dead function, dep with auto-fix). Append to `docs/plans/tech-debt-tracker.md`. Marker: `Filed by /en-sweep (continuous-monitor)`.
    - `draft_plans` — pattern / structural / decision-required (≥2 dead-code findings clustered in same area; severe CVE without auto-fix). Each draft plan goes into `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` with `status: draft`, `generator: en-sweep`, `generator_run: <merge-sha-short>`, `generator_checks: [dead-code|dep-audit]`. Cap at `sweep.max_drafts_per_run` (default 3); overflow rolls into TD with a "would have been a plan" note.

    Idempotent: before creating a draft, check `docs/plans/active/` for an existing plan with `generator: en-sweep` and matching `area:` — skip if present.

    The user reviews each draft plan, flips `status: draft → open` to accept (or moves to `archive/` to decline). To flesh out a draft into a full plan with peer review and R-ID coverage, run `/en-plan --resume docs/plans/active/<plan>.md`.
9. **Categorize findings strictly into doc batches; surface code-level findings to `tech-debt-tracker.md`.** Per `references/sweep-checks.md`. Code-level findings get appended via the format in `references/tech-debt-tracker-format.md`.
10. **Guard 2 — no-material-diff termination.** If no batches were produced, exit silently (no PR, no comment).
11. **Stage + verify each batch.**
    - Apply the fixes for the batch (Edit / Write tools).
    - Run `$SKILL_DIR/scripts/ensemble-doc-only-check` against the staged diff. **Any non-doc path → abort the batch; log loudly; do not create the PR.**
    - Cap the number of PRs per run at `max_prs_per_run` (default 6).
12. **Open PR per batch.**
    - Branch: `en-sweep/<source-merge-sha-short>/<batch-name>` (e.g., `en-sweep/a3f1b9c/architecture-update`).
    - PR title: `chore(<scope>): <one-line summary>`.
    - PR body: cites the source-PR SHA and the findings addressed.
    - PR label: `en-sweep`. Kept for humans filtering the PR list; no guard reads it since the label guard retired.
13. **Run `/en-review` per PR.** Mode: `report-only` (mandatory; never configurable for sweep). Returns findings JSON; does NOT mutate.
14. **Auto-merge eligibility check.**
    - `/en-review` returns no P0/P1 → eligible.
    - Branch protection allows (per `references/sweep-security-model.md`) → enable auto-merge via `gh pr merge --auto --squash`.
    - Otherwise → leave PR open for human resolution.
15. **Summary report.** Post a comment on the source-triggering PR:
    ```markdown
    ## en-sweep summary

    Ran 5 checks. Opened 3 doc-only PRs:
    - #102 — chore(arch): document new BillingService component
    - #103 — chore(plans): move FR05 to completed/
    - #104 — chore(learnings): add 4 missing back-refs

    All 3 passed `/en-review` and were auto-merged.

    Surfaced as judgment items (in PR comment, not auto-fixed):
    - 1 contradiction in `docs/learnings/`
    - 2 data-gap suggestions (sparse coverage on [performance, database])

    Code-level findings filed to tech-debt-tracker.md:
    - TD13: layer violation in src/services/notifications.ts
    - TD14: duplicated formatDate helper in src/utils/

    Run took: 4m 32s. Recursion depth: 1.
    ```
    Saved to `.ensemble/sweep-summary.md` for the workflow's "Post summary on source PR" step.

## Strict scope: doc-only

The doc-only contract is enforced at three points:

1. **Categorization (step 9).** Code-level findings never become PRs; they file as TD entries.
2. **Runtime enforcement (step 11).** `$SKILL_DIR/scripts/ensemble-doc-only-check` verifies every staged path is in the allowlist (`docs/`, `AGENTS.md`, `CLAUDE.md`, `.github/workflows/en-sweep.yml`, `.ensemble/sweep-summary.md`). Any path outside → abort the batch.
3. **Default-safe security** (per `references/sweep-security-model.md`). `GITHUB_TOKEN` least-privilege; no `actions: write`; no fork triggers; branch protection respected; fail-closed on any guard error.

## Loop guards

Sweep is scheduled, so it cannot fire on its own commits and the cadence is the rate-limiter. Three guards, all load-bearing. Per `references/sweep-loop-guards.md`:

1. **Concurrency group.** One sweep per branch at a time, so a manual `workflow_dispatch` cannot overlap the cron run. In the workflow.
2. **No-material-diff termination.** Silent exit when sweep produces no batches. Inside the skill, at step 10.
3. **Recursion depth cap.** Hard stop at `ENSEMBLE_SWEEP_DEPTH=1`, against an agent reading this file and dispatching `/en-sweep` from inside a sweep. In the workflow.

Two further guards existed under the old `push` trigger, one reading the pushed commit's message and one reading the merged PR's label. Both only ever caught sweep re-triggering on its own merge, which no longer happens. They are retired rather than demoted, and their numbers are not reused; `references/sweep-loop-guards.md` records what they did so the question does not get reopened without the trigger change that would justify them.

## Auto-merge eligibility

A sweep PR auto-merges when **all** hold:

- PR is doc-only (verified by `$SKILL_DIR/scripts/ensemble-doc-only-check`).
- `/en-review` in `mode:report-only` returns no P0/P1 findings.
- CI checks pass (project tests, lint).
- Branch protection's review requirement is met.

Otherwise: PR stays open for human resolution.

## Cross-review

**Off** at the skill level. Each sweep PR has its own quality gate via `/en-review` in `mode:report-only`.

## Reference files

- `references/sweep-checks.md` — full check catalog (file-shape, wiki-graph, architecture, plan lifecycle, pointer maps, continuous monitoring)
- `$SKILL_DIR/scripts/continuous-monitor` — dead-code + dep-audit scanner; outputs JSON-lines findings
- `$SKILL_DIR/scripts/triage-findings` — partitions findings into TD entries vs draft plans
- `references/sweep-loop-guards.md` — the three loop guards, and the two the scheduled trigger retired
- `references/sweep-security-model.md` — auto-merge safety, permissions, fork policy
- `references/tech-debt-tracker-format.md` — TD entry schema for code-level findings
- `references/architecture-update-rules.md` — what counts as material structural change
- `references/doc-lints.md` — file-shape lint catalog
- `references/learn-lint.md` — wiki-graph lint catalog
- `references/templates/github-workflow-en-sweep.yml` — installed workflow
- `$SKILL_DIR/scripts/en-sweep-ci` — CI wrapper (claude -p / codex exec resolver)
- `$SKILL_DIR/scripts/ensemble-doc-only-check` — runtime allowlist enforcement
- `bin/ensemble-lint` — file-shape lint runner
- `$SKILL_DIR/scripts/ensemble-sweep-activity-check` — pre-run activity gate; decides whether to skip the cycle

## Failure protocol

| Failure | Behavior |
|---|---|
| `$SKILL_DIR/scripts/ensemble-doc-only-check` rejects a batch | Abort that batch; log loudly with offending paths; post to source PR comment |
| `repo-research` returns malformed output | Skip that check; surface in summary; continue with other checks |
| `/en-review` returns malformed JSON | Treat as inconclusive; leave PR open; do not auto-merge |
| Branch-protection check fails (rate-limit, auth) | Fail-closed: leave all PRs open; do not auto-merge |
| `gh pr create` fails | Skip that batch; surface error; continue |
| Workflow times out (default 30 min) | Whatever PRs were already created stay open; the rest are dropped; post summary noting truncation |
| LLM provider auth fails | CI step exits with clear error; no PRs created; manual user action required to fix secrets |
| Two batches conflict on the same file | Open them as separate PRs; let the second rebase against the first when it lands |

## Configuration

Sweep reads `.ensemble/config.local.yaml`, the project-local gitignored file
`/en-setup` seeds. It is **not** `~/.ensemble/config.json`, which this section
named until 2026-09-03; that file is real but holds `peer_mode_override` for
host detection, and nothing in it has ever reached sweep.

```yaml
sweep:
  schedule: weekly          # informational; the cron lives in the workflow file
  max_prs_per_run: 6        # step 11 stops opening PRs at this count
  auto_merge_enabled: true  # false leaves every PR for manual approval
  continuous_monitoring:
    dead_code: true         # step 8a runs the monitor when either is true
    dep_audit: true
  auto_plan_threshold_loc: 50        # read by scripts/triage-findings
  auto_plan_threshold_locations: 2   # read by scripts/triage-findings
  max_drafts_per_run: 3              # read by scripts/triage-findings
```

Two kinds of key are in that list and the difference matters when one stops
working. `triage-findings` parses the last three itself, so a typo there is
silent and the default stands. The rest are read by this skill's own steps,
which means they are only as reliable as the step that cites them.

**The CI timeout is not a config key.** It is `timeout-minutes:` in
`.github/workflows/en-sweep.yml`, and editing the workflow is the only way to
change it. This section advertised a `ci_timeout_minutes` key until
2026-09-03; nothing substituted it into the workflow, so setting it did
nothing.

## What this skill never does

- **Never modifies source code, configuration, tests.** Doc-only contract.
- **Never spawns sweep.** Guard 3 (recursion depth cap) enforces.
- **Never bypasses branch protection.**
- **Never force-pushes.**
- **Never deletes branches** (post-merge cleanup is optional, off by default).
- **Never escalates permissions.**
