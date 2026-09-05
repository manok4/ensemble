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
| Scheduled cadence | launchd on a dedicated Mac runs `$SKILL_DIR/scripts/ensemble-sweep-runner`, installed by `$SKILL_DIR/scripts/install-sweep-schedule` (`daily` / `weekly` / `monthly`, local time; default weekly, Monday 09:00). The runner loops the checkouts listed in `~/.ensemble/sweep-repos` and drives each through **Codex** (D101). |
| `ensemble-sweep-runner --force` | A person kicks the runner by hand (or `install-sweep-schedule run-now`); `--force` bypasses the activity gate. |
| Manual (`/en-sweep`) | User runs the slash command in a session for ad-hoc cleanup. |

**Activity gate.** Before the sweep job runs, `$SKILL_DIR/scripts/ensemble-sweep-activity-check` walks `git log` for the most recent sweep-authored commit on `main` (matches the scopes `chore(sweep):`, `chore(arch):`, `chore(plans):`, `chore(learnings):`, `chore(maps):`) and counts non-sweep commits since then. If zero, the runner skips that repo silently: no LLM calls, no PRs. `--force` bypasses the gate.

**Every scope in that list has to be one sweep authors and a human would not.** A shared scope makes the gate read a human commit as sweep's own in two places at once, picking it as `LAST_SWEEP_SHA` and subtracting it from the count, and both errors skip the cycle; that is why the lint batch ships as `chore(sweep):` and `docs` is not a sweep scope (D65).

**The runner, per repo.** Refuses a dirty tree, fetches and fast-forwards the default branch, runs the activity gate, then `codex exec --json -s workspace-write` with network on, the model and effort from the repo's `sweep.model` / `sweep.effort` (else `ENSEMBLE_SWEEP_MODEL` / `ENSEMBLE_SWEEP_EFFORT` from the plist, else Codex's default), and a prompt that invokes this skill unattended. **The proof the skill ran is `.ensemble/sweep-result.json`** (step 14): no valid file after the run means the skill did not execute, the runner logs that, merges nothing and exits non-zero. A turn-count guard could not tell "ran and did nothing" from "described what it would do" (FR01 U11); the result file can. After the run the runner merges every PR the file marks eligible, once that PR's checks are green, with `gh pr merge --squash --delete-branch`. One lock per machine, so a manual kick cannot overlap the schedule.

## Process

1. **No host detection.** On the schedule the runner launched Codex; interactively, the host's own tools apply. The skill reads no host or peer variable and carries no detection files.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit. (Sweep should not be invoked from inside a peer subprocess.)
3. **Loop guards** (per `references/sweep-loop-guards.md`). The runner enforces Guard 1 (one run per machine, a lock) and Guard 3 (recursion depth cap) before the skill runs. Guard 2 (no-material-diff) fires inside the skill, at step 10.
4. **Dispatch the architecture scan first, then lint while it runs.** Step 6's `repo-research` is the slow step and depends on nothing below; start it, then run steps 4, 5, 7 and 8, which are independent scans, and collect its result at step 6. **Run file-shape lint.** `bin/ensemble-lint --json --scope docs/`. Capture violations.
5. **Run wiki-graph lint.** Invoke `/en-learn --lint` (programmatically via the host's task primitive). Capture violations.
6. **Architecture drift check.** Collect the `repo-research` result dispatched at step 4; it compared `docs/architecture.md` against the codebase:
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
10. **Guard 2 — no-material-diff termination.** If no batches were produced, write `.ensemble/sweep-result.json` with an empty `prs` list (step 14) and exit; no PR, no comment.
11. **Stage + verify each batch.**
    - Apply the fixes for the batch: `Edit` on existing files, `Write` only for new ones. A doc-drift fix that rewrites `docs/architecture.md` whole produces a diff `/en-review` cannot read as a fix.
    - Run `$SKILL_DIR/scripts/ensemble-doc-only-check` against the staged diff. **Any non-doc path → abort the batch; log loudly; do not create the PR.**
    - Cap the number of PRs per run at `max_prs_per_run` (default 6).
12. **Open PR per batch.**
    - Branch: `en-sweep/<source-merge-sha-short>/<batch-name>` (e.g., `en-sweep/a3f1b9c/architecture-update`).
    - PR title: `chore(<scope>): <one-line summary>`.
    - PR body: cites the source-PR SHA and the findings addressed.
    - PR label: `en-sweep`. Kept for humans filtering the PR list; no guard reads it since the label guard retired.
13. **Run `/en-review` per PR.** Mode: `report-only` (mandatory; never configurable for sweep). Returns findings JSON; does NOT mutate.
14. **Merge eligibility, recorded, never acted on here.** For each PR: `/en-review` returned no P0/P1 → `merge_eligible: true`; findings, malformed JSON, or `sweep.auto_merge_enabled: false` → `false` with the reason. Write the whole run to `.ensemble/sweep-result.json` (not staged; it is not in the doc-only allowlist):

    ```json
    {"run_id": "<ISO timestamp>-<head sha7>", "branch": "main",
     "prs": [{"number": 102, "batch": "architecture-update", "review": "clean", "merge_eligible": true, "reason": ""},
             {"number": 103, "batch": "plans", "review": "findings", "merge_eligible": false, "reason": "P1 open"}]}
    ```

    **This skill never merges.** Merging is the runner's step, after the PR's checks finish green; a session run that wants the same outcome invokes `ensemble-sweep-runner --merge-only --repo <path>`. The file is also the runner's proof the skill executed, so it is written on every path, including the no-batches exit at step 10. `review: inconclusive` (malformed review JSON) is never eligible.
15. **Summary report.** Write it to `.ensemble/sweep-summary.md`; the runner appends it to `~/.ensemble/logs/sweep.log`:
    ```markdown
    ## en-sweep summary

    Ran 5 checks. Opened 3 doc-only PRs:
    - #102 — chore(arch): document new BillingService component
    - #103 — chore(plans): move FR05 to completed/
    - #104 — chore(learnings): add 4 missing back-refs

    All 3 passed `/en-review` and are merge-eligible; the runner merges them once checks pass.

    Surfaced as judgment items (in PR comment, not auto-fixed):
    - 1 contradiction in `docs/learnings/`
    - 2 data-gap suggestions (sparse coverage on [performance, database])

    Code-level findings filed to tech-debt-tracker.md:
    - TD13: layer violation in src/services/notifications.ts
    - TD14: duplicated formatDate helper in src/utils/

    Run took: 4m 32s. Recursion depth: 1.
    ```
    A manual `/en-sweep` prints the same text in the session.

## Strict scope: doc-only

The doc-only contract is enforced at three points:

1. **Categorization (step 9).** Code-level findings never become PRs; they file as TD entries.
2. **Runtime enforcement (step 11).** `$SKILL_DIR/scripts/ensemble-doc-only-check` verifies every staged path is in the allowlist (`docs/`, `AGENTS.md`, `CLAUDE.md`, `.ensemble/sweep-summary.md`). Any path outside → abort the batch.
3. **Default-safe security** (per `references/sweep-security-model.md`). The runner acts as the machine's own `gh` identity, whose repo permissions are the entire scope; Codex runs in the workspace-write sandbox; branch protection is respected (a refused merge is left open, never forced); fail-closed on any guard error.

## Loop guards

Sweep is scheduled, so it cannot fire on its own commits and the cadence is the rate-limiter. Three guards, all load-bearing. Per `references/sweep-loop-guards.md`:

1. **One run per machine.** The runner takes `~/.ensemble/sweep.lock` and skips when another run holds it, so a manual kick cannot overlap the schedule. In the runner.
2. **No-material-diff termination.** Silent exit when sweep produces no batches. Inside the skill, at step 10.
3. **Recursion depth cap.** Hard stop at `ENSEMBLE_SWEEP_DEPTH=1`, against an agent reading this file and dispatching `/en-sweep` from inside a sweep. Set by the runner.

Two further guards belonged to the retired `push` trigger and caught only sweep re-triggering on its own merge; their numbers are not reused, and `references/sweep-loop-guards.md` records them so the question is not reopened without the trigger change that would justify them (D27, D65).

## Merge eligibility

The runner merges a sweep PR when **all** hold:

- PR is doc-only (verified by `$SKILL_DIR/scripts/ensemble-doc-only-check`).
- `/en-review` in `mode:report-only` returned no P0/P1 findings, recorded as `merge_eligible: true` in `.ensemble/sweep-result.json`.
- Every check on the PR finished green (the runner waits up to `ENSEMBLE_SWEEP_CHECKS_TIMEOUT`, default 30 minutes; a PR with no checks merges at once).
- `gh pr merge --squash --delete-branch` succeeds under the machine's identity.

Otherwise the PR stays open with the reason in the log. A `BLOCKED` merge state after green checks means branch protection wants a review this identity cannot give; the fix is a repo setting, not a runner flag.

## Cross-review

**Off** at the skill level. Each sweep PR has its own quality gate via `/en-review` in `mode:report-only`.

## Reference files

- `references/sweep-checks.md` — full check catalog (file-shape, wiki-graph, architecture, plan lifecycle, pointer maps, continuous monitoring)
- `$SKILL_DIR/scripts/continuous-monitor` — dead-code + dep-audit scanner; outputs JSON-lines findings
- `$SKILL_DIR/scripts/triage-findings` — partitions findings into TD entries vs draft plans
- `references/sweep-loop-guards.md` — the three loop guards, and the two the scheduled trigger retired
- `references/sweep-security-model.md` — the machine's identity, the sandbox, merge safety
- `references/tech-debt-tracker-format.md` — TD entry schema for code-level findings
- `references/architecture-update-rules.md` — what counts as material structural change
- `references/doc-lints.md` — file-shape lint catalog
- `references/learn-lint.md` — wiki-graph lint catalog
- `$SKILL_DIR/scripts/ensemble-sweep-runner` — the scheduled entry point: per-repo gate, `codex exec`, result-file guard, merge
- `$SKILL_DIR/scripts/install-sweep-schedule` — `add-repo`, `install` (launchd), `status`, `run-now`, `uninstall`; run by a person on the sweep machine
- `$SKILL_DIR/scripts/ensemble-doc-only-check` — runtime allowlist enforcement
- `bin/ensemble-lint` — file-shape lint runner
- `$SKILL_DIR/scripts/ensemble-sweep-activity-check` — pre-run activity gate; decides whether to skip the cycle

## Failure protocol

| Failure | Behavior |
|---|---|
| `$SKILL_DIR/scripts/ensemble-doc-only-check` rejects a batch | Abort that batch; log loudly with offending paths in the summary |
| `repo-research` returns malformed output | Skip that check; surface in summary; continue with other checks |
| `/en-review` returns malformed JSON | Record `review: inconclusive`, `merge_eligible: false`; the PR stays open |
| A PR's check fails, or its merge is refused | The runner leaves it open with the reason logged; nothing is retried or forced |
| `gh pr create` fails | Skip that batch; surface error; continue |
| The Codex run exceeds `ENSEMBLE_SWEEP_TIMEOUT` (default 45 min) | The runner kills it; PRs already opened stay open; no result file means nothing merges and the repo is logged as failed |
| Codex or `gh` auth fails on the machine | The runner's doctor stops before any repo; fix the login on that machine and re-run |
| Two batches conflict on the same file | Open them as separate PRs; let the second rebase against the first when it lands |

## Configuration

Sweep reads `.ensemble/config.local.yaml`, the project-local gitignored file
`/en-setup` seeds; on the sweep machine that is the file in that machine's
checkout. Nothing in `~/.ensemble/config.json` reaches sweep.

```yaml
sweep:
  enabled: true             # false makes the runner skip this repo; /en-setup writes it on a decline
  schedule: weekly          # informational; the cadence lives in the launchd plist
  model: fable              # Codex -m for the scheduled run; unset falls back to ENSEMBLE_SWEEP_MODEL, then Codex's default
  effort: high              # model_reasoning_effort: minimal | low | medium | high | xhigh
  max_prs_per_run: 6        # step 11 stops opening PRs at this count
  auto_merge_enabled: true  # false records every PR as not merge-eligible; the runner merges none
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

**Model precedence on the schedule:** `sweep.model` in the repo's YAML on the sweep machine, then `ENSEMBLE_SWEEP_MODEL` from the launchd plist (`install-sweep-schedule --model`), then Codex's configured default; effort the same way. A manual `/en-sweep` runs on the session's model.

**Cadence and timeouts are the runner's, not config keys.** The schedule lives in `~/Library/LaunchAgents/com.ensemble.sweep.plist` (`install-sweep-schedule install --cadence …`); `ENSEMBLE_SWEEP_TIMEOUT` caps each repo's Codex run and `ENSEMBLE_SWEEP_CHECKS_TIMEOUT` the wait for a PR's checks, both set in the plist's environment.

## What this skill never does

- **Never modifies source code, configuration, tests.** Doc-only contract.
- **Never spawns sweep.** Guard 3 (recursion depth cap) enforces.
- **Never bypasses branch protection.** A refused merge is left open; nothing is forced or approved by the runner.
- **Never force-pushes.**
- **Never deletes branches** (post-merge cleanup is optional, off by default).
- **Never escalates permissions.**
