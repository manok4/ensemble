---
name: en-setup
description: "Project-level Ensemble bootstrap and diagnostics. Detects greenfield (State 1), existing project without Ensemble (State 2; sub-variants 2a/2b/2c/2d), or already integrated (State 3). State 2 retrofit: archive legacy plans, create docs/ skeleton, generate AGENTS.md/CLAUDE.md, install en-sweep workflow, offer guardrail / Claude Code Review action / bootstrap-patterns. State 3: health checks. Trigger phrases: 'set up Ensemble', 'bootstrap Ensemble', 'install Ensemble here', 'retrofit', 'diagnose Ensemble'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-setup`

Project-level Ensemble bootstrap and diagnostics. Distinct from the global `./setup` script (machine-level install).

> **Hard rule:** This skill is mechanical setup work. **No code review, no peer cross-review, no implementation.** Off-loads anything ambiguous to `/en-brainstorm`, `/en-foundation`, or `/en-plan`.

## Process

1. **Detect host.** Source `$ENSEMBLE_ROOT/references/host-detect.md` (in plugin) or run `$ENSEMBLE_ROOT/bin/ensemble-detect-host`. Set `HOST`, `PEER_AVAILABLE`, etc.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit with note (this skill should never be peer-invoked).
3. **Detect state** per `$ENSEMBLE_ROOT/references/setup-state-detection.md`:
   - State 1 — Greenfield (empty repo or initial-commit, no `docs/foundation.md`).
   - State 2 — Existing project, no Ensemble (source code present, foundation or learnings missing). Identify sub-variant 2a/2b/2c/2d by which of `AGENTS.md`/`CLAUDE.md` exist.
   - State 3 — Existing project with Ensemble (`docs/foundation.md` and `docs/learnings/` both present).
4. **Run the state-specific flow** (below).
5. **Output** a structured report listing what was created, what was modified (if anything), and the recommended next step.

## State 1 — Greenfield handoff

**Don't pre-create artifacts.** Hand off to the right skill.

Output:

```
This looks like a brand-new project. Recommended next steps:

  1. Run /en-brainstorm to explore what you're building. Outputs a design doc.
  2. Run /en-foundation to lock product+technical scope, generate AGENTS.md / CLAUDE.md / docs/architecture.md, and emit the bootstrap <PREFIX>01-feature_project-setup plan (prefix chosen during foundation; falls back to FR).

Run /en-setup again later for diagnostics on Ensemble integration.
```

Exit.

## State 2 — Retrofit bootstrap

Run all of these in order. Each step is idempotent — running `/en-setup` twice produces the same end state.

1. **Confirm sub-variant.** Probe for `AGENTS.md` / `CLAUDE.md` existence; classify as 2a/2b/2c/2d.
2. **Existing-plans archival (run before creating skeleton).** If `docs/plans/` already exists, run `$ENSEMBLE_ROOT/bin/ensemble-classify-plans docs/plans` to inspect it. Output partitions plans into:
   - `conforming` — already pass Ensemble plan validation; leave in place.
   - `non_conforming` — `.md` files in `docs/plans/` that aren't Ensemble plans (legacy / hand-rolled / from another tool).
   - `subdirs` — unrecognized subdirectories.
   - `tech_debt` — `docs/plans/tech-debt-tracker.md` if present (treat as conforming).

   **If `non_conforming` is non-empty**, prompt:
   > "Found `<count>` plan file(s) in `docs/plans/` that don't match Ensemble's format:
   >   - `<path1>`
   >   - `<path2>`
   >   - …
   >
   > Archive them to `docs/plans/legacy/` so they're preserved but won't be picked up by `/en-build`, `/en-learn`, `/en-sweep`? You can migrate any of them into Ensemble's flow later via `/en-plan --from-legacy <path>`. (y/n; default y)"

   On `y` → `mkdir -p docs/plans/legacy`; `git mv` each non-conforming file into `docs/plans/legacy/`. Write `docs/plans/legacy/README.md` documenting:
   - The convention: legacy plans are preserved here untouched; Ensemble skills ignore this directory.
   - The migration path: `/en-plan --from-legacy docs/plans/legacy/<file>.md` brings a legacy plan into the active flow with proper R-ID/U-ID assignment and peer review.
   - The list of archived files with original paths.

   On `n` → leave in place; record in the report that lint will warn (`frontmatter.required-field-missing` etc.) until each file is migrated or archived.

   `subdirs` (unrecognized subdirectories under `plans/`) are surfaced but not auto-archived — they may be in-flight work the user wants to handle manually.
3. **Create directory skeleton:**
   ```
   docs/
     plans/{active,completed}/
     learnings/{bugs,patterns,decisions,sources}/
     references/
     generated/
     designs/
   ```
   - Use the platform's file-write primitive (Write tool / `apply_patch`).
   - Don't fail if directories already exist.
4. **Seed `docs/learnings/index.md` and `log.md`** from the empty-state templates in `$ENSEMBLE_ROOT/references/learn-index-format.md` and `$ENSEMBLE_ROOT/references/learn-log-format.md`.
5. **Seed `docs/generated/plan-index.md` and `learning-index.md`** with `generated: true` frontmatter and zero entries (these are mandatory per foundation §10.1; lint requires their existence).
6. **Generate or merge `AGENTS.md`** per sub-variant (see `$ENSEMBLE_ROOT/references/templates/agents-md-template.md` and `$ENSEMBLE_ROOT/references/templates/agents-md-merge-rules.md`). Substitute `{{PROJECT_NAME}}`, `{{ONE_LINE_PURPOSE}}`, `{{TODAY}}`, plus detected `{{BUILD_CMD}}` / `{{TEST_CMD}}` / `{{LINT_CMD}}` / `{{TYPECHECK_CMD}}` / `{{DEV_CMD}}` / `{{LANG}}`.
7. **Generate or merge `CLAUDE.md`** per sub-variant. Substitute `{{PROJECT_NAME}}` / `{{TODAY}}`. Always ensure the AGENTS.md cross-reference line is the first non-frontmatter line.
8. **Add `.gitignore` entries** if missing. **Verify each entry is actually present after the write — do not assume the write succeeded.**
   - `.ensemble/config.local.yaml` — **required.** Confirm with `grep -qF '.ensemble/config.local.yaml' .gitignore` after writing. If `.gitignore` doesn't exist, create it with this line.
   - Optionally `docs/learnings/archive/` — ask the user.

   This step is verified again in the final-verification phase (step 17). Both checks must pass.
9. **Install project-local `bin/` scripts.** **(Required for the en-sweep workflow in step 10 to actually run.)** Copy these four scripts from the plugin's `bin/` into `<repo-root>/bin/`, `chmod +x` each, and stage for commit:

   - `$ENSEMBLE_ROOT/bin/en-sweep-ci` — wrapper invoked by `.github/workflows/en-sweep.yml` (line 114 of the template).
   - `$ENSEMBLE_ROOT/bin/ensemble-sweep-activity-check` — invoked directly by the workflow (lines 52, 54 of the template) for the "no non-sweep commits since last run" gate.
   - `$ENSEMBLE_ROOT/bin/ensemble-doc-only-check` — used by the en-sweep skill to gate doc-only PR auto-merge.
   - `$ENSEMBLE_ROOT/bin/ensemble-lint` — used by en-sweep, en-plan, en-review for file-shape lints.

   **Resolving the plugin source path.** The plugin's `bin/` lives wherever the host CLI loads plugins from. Resolve via (in order):
     - `${ENSEMBLE_PLUGIN_DIR:-}` env var if set.
     - The skill's own load path: `dirname(realpath(<this SKILL.md>))/../../bin/`.
     - `~/.claude/plugins/<plugin-id>/bin/` for Claude Code's default layout (fallback).

   For each of the four scripts: copy from `<plugin>/bin/<name>` to `<repo>/bin/<name>`, run `chmod +x <repo>/bin/<name>`, and `git add bin/<name>`. **Idempotent**: if the destination file exists AND the content matches the source, skip the copy but still verify `chmod +x`.

   **Verification:** after copying, confirm with `[ -x bin/<name> ]` for each. Re-checked in the final-verification phase (step 17).

   These bin scripts are project-local on purpose — they're invoked from `.github/workflows/en-sweep.yml` via relative paths, which only works if they're committed to the repo.

10. **Install `.github/workflows/en-sweep.yml`** from `$ENSEMBLE_ROOT/references/templates/github-workflow-en-sweep.yml`. Depends on step 9 — the workflow won't function without those bin scripts.
    1. **Ask cadence.** Prompt: "How often should `/en-sweep` run? `daily` / `weekly` / `monthly` (default `weekly`), or paste a cron expression for custom (e.g. `0 9 * * 1,4` for Mon+Thu)."
    2. **Map to cron.** Named values map to:
       - `daily` → `0 9 * * *`
       - `weekly` → `0 9 * * 1` (Monday 9am UTC)
       - `monthly` → `0 9 1 * *` (1st of the month, 9am UTC)
       - Anything else is treated as a literal cron expression and substituted as-is.
    3. **Substitute** `{{SWEEP_CRON}}` in the template with the resolved cron expression and write the workflow file. Record `sweep.schedule: <name>` in `.ensemble/config.local.yaml` so the choice is documented (informational; the cron is already in the workflow file).
    4. **Verify** the workflow file exists after the write: `[ -f .github/workflows/en-sweep.yml ]`. Re-checked in step 17.
    5. **Surface required secrets** per A20: "Sweep needs **one** auth secret in repo Settings → Secrets and variables → Actions: `CLAUDE_CODE_OAUTH_TOKEN` (Pro/Max subscription; preferred — generate with `claude setup-token`) OR `ANTHROPIC_API_KEY` (pay-per-use) OR `OPENAI_API_KEY` (if running `codex` CLI). Workflow passes all three; the CLI in the runner picks up the matching one."
    6. **Note the activity gate:** "Sweep runs on the configured schedule but skips silently when no non-sweep commits have landed since the last sweep run. Manual `workflow_dispatch` always bypasses the gate. Activity check via `$ENSEMBLE_ROOT/bin/ensemble-sweep-activity-check`."
11. **Create `.ensemble/config.local.example.yaml`** (committed) from `$ENSEMBLE_ROOT/references/templates/config-local-example.yaml`. **Offer** to create `.ensemble/config.local.yaml` (gitignored) with the most-likely-relevant defaults uncommented; ask the user.
12. **Guardrail check.** Run `skills/en-guardrail/bin/install-guardrail status`. If neither scope is installed, prompt:
    > "The en-guardrail PreToolUse hook isn't installed. It prompts before destructive Bash commands (recursive rm, DROP TABLE, force-push, terraform destroy, etc.). Choose:
    >   `p` — install project-scoped now (writes to `<repo>/.claude/settings.json`).
    >   `g` — print the global one-liner for me to run from my terminal (active everywhere; agents can't write `~/.claude/` themselves).
    >   `s` — skip for now."

    On `p` → run `skills/en-guardrail/bin/install-guardrail install-project`.
    On `g` → run `skills/en-guardrail/bin/install-guardrail install-global` (no `--apply`) and surface its output verbatim.
    On `s` → record in the report; don't ask again this session.

    Idempotent — if the status check reports any scope active, skip the prompt and note it in the report.
13. **Claude Code Review action check.** Detect `.github/workflows/claude-code-review.yml`. If absent, prompt:
    > "Anthropic's Claude Code Review GitHub Action isn't installed. It runs Claude on every PR and posts inline review comments — these are exactly what `/en-resolve-pr` is built to handle. Install? (`y` / `n`)
    > Auth options:
    >   - **OAuth** (Pro/Max subscription) — free within rate limits. Requires `CLAUDE_CODE_OAUTH_TOKEN` repo secret (generate with `claude setup-token`).
    >   - **API key** — pay-per-use, no rate cap. Requires `ANTHROPIC_API_KEY` repo secret. Edit the workflow after install to switch."

    On `y` → write `.github/workflows/claude-code-review.yml` from `$ENSEMBLE_ROOT/references/templates/github-workflow-claude-review.yml`. Surface a one-line follow-up: "Add `CLAUDE_CODE_OAUTH_TOKEN` to repo secrets (Settings → Secrets and variables → Actions). See `docs/integrations/anthropic-code-review-action.md` for setup."
    On `n` → record in the report; skip.

    Idempotent — if the workflow already exists, note it and don't overwrite.
14. **Auto-merge repo-setting check.** Run `gh api repos/<owner>/<repo> --jq .allow_auto_merge`.
    - `true` → record 🟢 "Auto-merge enabled at repo level."
    - `false` or empty → surface advisory (not blocking):
      > "Auto-merge is disabled at the repo level. `/en-ship --auto-merge` and `/en-resolve-pr --enable-auto-merge` won't be able to enable auto-merge on PRs until you flip Settings → General → 'Allow auto-merge' on. Skipping for now — this is a manual repo setting."

    Idempotent. Don't try to flip it via API — that requires admin scope and is the kind of repo-policy change a human should make explicitly.
15. **`REVIEW.md` offer.** Detect `REVIEW.md` at the repo root. If absent, prompt:
    > "`REVIEW.md` is a project-root file that tunes how PR review behaves on this repo — severity calibration, nit caps, skip rules, repo-specific checks, convergence behavior on multi-round reviews. Read automatically by Anthropic's managed Code Review service (Team/Enterprise plans); for the self-hosted action, the workflow's `prompt:` step has to include the file content (see template § 'Wiring `REVIEW.md` into the self-hosted action'). Seed `REVIEW.md` from the Ensemble-flavored default template? (`y` / `n`)"

    On `y` → ask the user `{{PROJECT_TYPE}}` (one of: `backend service` / `frontend app` / `library` / `cli tool` / `docs site` / `mobile app` / `infrastructure` / `mixed`); write `REVIEW.md` from `$ENSEMBLE_ROOT/references/templates/review-md-template.md` with `{{PROJECT_NAME}}` (from `docs/foundation.md` `project:`), `{{PROJECT_TYPE}}`, and `{{PLAN_ID_PREFIX}}` substituted.
    On `n` → record in the report; skip.

    Idempotent — if `REVIEW.md` already exists, note its presence and skip.
16. **Bootstrap-patterns offer.** Surface to user (informational; they decide later):
    > "After you run `/en-foundation --retrofit`, consider `/en-learn --bootstrap-patterns` to seed `docs/learnings/patterns/` from the codebase's existing conventions. It's optional, opt-in, one-time. Bootstrapped entries are flagged `requires_validation: true` and lower-confidence by default — they give the wiki a starting point without pretending to be capture-fresh. See `$ENSEMBLE_ROOT/references/learn-bootstrap-patterns.md`."

    Don't auto-run it. The user decides.

17. **Final verification phase (mandatory, idempotent).** After all install steps complete, **walk every required artifact and confirm it's present**. This is the safety net — long mechanical sequences drop steps under context pressure, and a verification phase at the end catches that.

    **Required artifacts** (must exist; missing → fail):

    | Artifact | Check |
    |---|---|
    | `docs/plans/{active,completed}/` | both directories exist |
    | `docs/learnings/{bugs,patterns,decisions,sources}/` | all four directories exist |
    | `docs/learnings/{index.md,log.md}` | both files exist |
    | `docs/generated/{plan-index.md,learning-index.md}` | both files exist with `generated: true` frontmatter |
    | `docs/{references,designs}/` | both directories exist |
    | `AGENTS.md` | exists; contains the Ensemble pointer-map section marker |
    | `CLAUDE.md` | exists; first non-frontmatter line cross-references AGENTS.md |
    | `.gitignore` | contains `.ensemble/config.local.yaml` (`grep -qF '.ensemble/config.local.yaml' .gitignore`) |
    | `.github/workflows/en-sweep.yml` | exists |
    | `$ENSEMBLE_ROOT/bin/en-sweep-ci` | exists, executable (`-x`) |
    | `$ENSEMBLE_ROOT/bin/ensemble-sweep-activity-check` | exists, executable |
    | `$ENSEMBLE_ROOT/bin/ensemble-doc-only-check` | exists, executable |
    | `$ENSEMBLE_ROOT/bin/ensemble-lint` | exists, executable |
    | `.ensemble/config.local.example.yaml` | exists |

    **Optional artifacts** (depend on user opt-in earlier; surface in report but don't fail if absent):

    - `.github/workflows/claude-code-review.yml` (step 13 opt-in)
    - `REVIEW.md` (step 15 opt-in)
    - `.claude/settings.json` with guardrail PreToolUse hook (step 12 opt-in)
    - `.ensemble/config.local.yaml` (step 11 opt-in)

    **For each missing required artifact**: re-run the corresponding install step **once**. If it's still missing, **fail loudly**:

    ```
    ⚠️  /en-setup verification failed.
    Missing required artifacts after retrofit:
      - bin/ensemble-lint (not present)
      - .gitignore (does not contain '.ensemble/config.local.yaml')

    These were supposed to be installed by steps 8–9 but the writes
    didn't take. Re-run /en-setup, or surface this to the user and ask
    them to commit what's there before proceeding.
    ```

    **Idempotency check:** running `/en-setup` again on the same repo must produce zero new changes once verification has passed. Encode this expectation in the report ("Final verification: 14 / 14 required artifacts present").

18. **Recommend next steps:**
    ```
    Two paths:
      - Run /en-foundation --retrofit to back-fill docs/foundation.md and docs/architecture.md from existing code.
        (Recommended for projects that will see continuing development with Ensemble.)
      - Or jump to /en-plan for the next feature; foundation can be filled in later.

    Once /en-foundation has settled and you've seen the codebase's
    conventions surface in real reviews, consider:
      - /en-learn --bootstrap-patterns — seed docs/learnings/patterns/
        from the codebase (opt-in; one-time; lower-confidence entries).
    ```

### Detection of project commands

For substituting `{{BUILD_CMD}}`, etc., check (in order):

| Source | Field |
|---|---|
| `package.json` `scripts.build` / `test` / `lint` / `typecheck` / `dev` | If present → use |
| `Makefile` targets | Inspect for `build`, `test`, `lint` |
| `Cargo.toml`, `pyproject.toml`, `go.mod` | Use language-default commands |
| Otherwise | `<unset>` (don't guess) |

For `{{LANG}}`: detect from `package.json` (TypeScript if `"typescript"` in deps; JavaScript otherwise), `Cargo.toml` (Rust), `go.mod` (Go), `pyproject.toml` (Python), etc.

## State 3 — Diagnostic mode

Invoke `scripts/check-health` (in the plugin's `scripts/` directory). It prints 🟢/🟡/🔴 per check. Pipe through and surface the result to the user.

In addition to file-shape and lint checks, the diagnostic includes:

- **Required-artifact verification** — same table as State 2 step 17 (final verification). Each missing required artifact is 🔴; offer the same install step as a repair (e.g. missing `$ENSEMBLE_ROOT/bin/ensemble-lint` → "Re-run the bin-install from State 2 step 9? (y/n)"). This catches projects that were retrofitted before the bin-install step existed and never got the project-local scripts.
- **Guardrail status** — run `skills/en-guardrail/bin/install-guardrail status`. 🟢 if either scope is installed; 🟡 if neither (offer the same `p`/`g`/`s` prompt as in State 2 step 12).
- **Claude Code Review action status** — check for `.github/workflows/claude-code-review.yml`. 🟢 if present; 🟡 if absent (offer the same `y`/`n` prompt as in State 2 step 13).
- **Auto-merge repo-setting** — `gh api repos/<owner>/<repo> --jq .allow_auto_merge`. 🟢 if `true`; 🟡 advisory if `false` (manual repo setting; surface the path: Settings → General → "Allow auto-merge").

For each 🟡 / 🔴 check, the user can opt-in to repair:

```
🟡 docs/learnings/log.md missing.
   Repair: create empty seed file with placeholder content.
   Apply? (y/n)
```

User accepts → apply the fix; re-run `check-health` to confirm.

After all checks (and any repairs), output a one-line summary: "🟢 12 / 🟡 0 / 🔴 0 — all checks pass."

## Output format

Always output a structured report:

```
State detected: state-2 (sub-variant 2c)

Created:
  - docs/plans/active/
  - docs/plans/completed/
  - docs/learnings/{bugs,patterns,decisions,sources}/
  - docs/learnings/{index.md,log.md}
  - docs/generated/{plan-index.md,learning-index.md}
  - CLAUDE.md (from template)
  - REVIEW.md (review-only instructions; from template)
  - .github/workflows/en-sweep.yml
  - .github/workflows/claude-code-review.yml (Anthropic Code Review action)
  - bin/en-sweep-ci (chmod +x)
  - bin/ensemble-sweep-activity-check (chmod +x)
  - bin/ensemble-doc-only-check (chmod +x)
  - bin/ensemble-lint (chmod +x)
  - .ensemble/config.local.example.yaml
  - .claude/settings.json (en-guardrail PreToolUse hook, project-scoped)

Modified:
  - AGENTS.md (appended Ensemble pointer map section)
  - .gitignore (added .ensemble/config.local.yaml)

Skipped:
  - docs/foundation.md (run /en-foundation --retrofit to create)

Final verification: 14 / 14 required artifacts present.

Next step:
  Run /en-foundation --retrofit to back-fill foundation and architecture from existing code.
  Or run /en-plan for the next feature.
```

## Edge cases

| Case | Handling |
|---|---|
| Repo is not a git repo | Surface and stop. Tell user to run `git init` first or pass `--no-git` (rare). |
| `package.json` malformed | Skip command detection; substitute `<unset>` and surface a warning. |
| User declines `.ensemble/config.local.yaml` creation | Skip; only the example file exists. |
| GH Action workflow already exists with different content | Don't overwrite. Surface a warning: "Existing `.github/workflows/<file>.yml` differs from template; leaving as-is. Compare manually if you want to update." Applies to both `en-sweep.yml` and `claude-code-review.yml`. |
| Existing `AGENTS.md` / `CLAUDE.md` has Ensemble integration already | Detect via heading/link match; no-op. |

## What this skill never does

- **No code review.** Defers to `/en-review`.
- **No code generation.** Defers to `/en-build`.
- **No peer cross-review.** Setup is mechanical.
- **No git commit.** User stages and commits the changes themselves (or via `/en-ship`).
- **No content invention.** Substitutions come from detected values or templates; if unknown → `<unset>` placeholder.

## Reference files

- `$ENSEMBLE_ROOT/references/setup-state-detection.md` — full state detection algorithm + sub-variants
- `$ENSEMBLE_ROOT/references/templates/agents-md-template.md` — AGENTS.md template + substitutions
- `$ENSEMBLE_ROOT/references/templates/claude-md-template.md` — CLAUDE.md template + substitutions
- `$ENSEMBLE_ROOT/references/templates/agents-md-merge-rules.md` — append-merge logic for variants 2b/2c/2d
- `$ENSEMBLE_ROOT/references/templates/github-workflow-en-sweep.yml` — GH Action workflow
- `$ENSEMBLE_ROOT/references/templates/config-local-example.yaml` — committed config template
- `$ENSEMBLE_ROOT/references/learn-index-format.md` — `learnings/index.md` empty-state seed
- `$ENSEMBLE_ROOT/references/learn-log-format.md` — `learnings/log.md` empty-state seed
- `$ENSEMBLE_ROOT/references/host-detect.md` — host detection (used briefly at start)
- `$ENSEMBLE_ROOT/references/templates/github-workflow-claude-review.yml` — Anthropic Code Review action workflow template
- `$ENSEMBLE_ROOT/references/templates/review-md-template.md` — `REVIEW.md` Ensemble-flavored default; referenced from step 14
- `$ENSEMBLE_ROOT/references/learn-bootstrap-patterns.md` — Mode F (`/en-learn --bootstrap-patterns`) referenced from step 16
- `scripts/check-health` — diagnostic runner (State 3)
- `skills/en-guardrail/bin/install-guardrail` — installs/uninstalls the destructive-command guardrail hook
- `$ENSEMBLE_ROOT/bin/ensemble-classify-plans` — partitions existing `docs/plans/` into conforming vs non-conforming (used in State 2 step 2)
