---
name: en-setup
description: "Project-level Ensemble bootstrap and diagnostics. Detects greenfield (State 1), existing project without Ensemble (State 2; sub-variants 2a/2b/2c/2d), or already integrated (State 3). State 2 retrofit: archive legacy plans, create docs/ skeleton, generate AGENTS.md/CLAUDE.md, install en-sweep workflow, offer guardrail / Claude Code Review action / bootstrap-patterns. State 3: health checks. Trigger phrases: 'set up Ensemble', 'bootstrap Ensemble', 'install Ensemble here', 'retrofit', 'diagnose Ensemble'."
---

# `/en-setup`

Project-level Ensemble bootstrap and diagnostics. Distinct from the global `./setup` script (machine-level install).

> **Hard rule:** This skill is mechanical setup work. **No code review, no peer cross-review, no implementation.** Off-loads anything ambiguous to `/en-brainstorm`, `/en-foundation`, or `/en-plan`.

## Process

1. **Detect host.** Source `references/host-detect.md` (in plugin) or run `bin/ensemble-detect-host`. Set `HOST`, `PEER_AVAILABLE`, etc.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit with note (this skill should never be peer-invoked).
3. **Detect state** per `references/setup-state-detection.md`:
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
2. **Existing-plans archival (run before creating skeleton).** If `docs/plans/` already exists, run `bin/ensemble-classify-plans docs/plans` to inspect it. Output partitions plans into:
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
4. **Seed `docs/learnings/index.md` and `log.md`** from the empty-state templates in `references/learn-index-format.md` and `references/learn-log-format.md`.
5. **Seed `docs/generated/plan-index.md` and `learning-index.md`** with `generated: true` frontmatter and zero entries (these are mandatory per foundation §10.1; lint requires their existence).
6. **Generate or merge `AGENTS.md`** per sub-variant (see `references/templates/agents-md-template.md` and `references/templates/agents-md-merge-rules.md`). Substitute `{{PROJECT_NAME}}`, `{{ONE_LINE_PURPOSE}}`, `{{TODAY}}`, plus detected `{{BUILD_CMD}}` / `{{TEST_CMD}}` / `{{LINT_CMD}}` / `{{TYPECHECK_CMD}}` / `{{DEV_CMD}}` / `{{LANG}}`.
7. **Generate or merge `CLAUDE.md`** per sub-variant. Substitute `{{PROJECT_NAME}}` / `{{TODAY}}`. Always ensure the AGENTS.md cross-reference line is the first non-frontmatter line.
8. **Add `.gitignore` entries** if missing:
   - `.ensemble/config.local.yaml`
   - Optionally `docs/learnings/archive/` — ask the user.
9. **Install `.github/workflows/en-sweep.yml`** from `references/templates/github-workflow-en-sweep.yml`. Surface required permissions/secrets per A20 in a one-line note: "Sweep needs `ANTHROPIC_API_KEY` (or `OPENAI_API_KEY`) in repo secrets to run."
10. **Create `.ensemble/config.local.example.yaml`** (committed) from `references/templates/config-local-example.yaml`. **Offer** to create `.ensemble/config.local.yaml` (gitignored) with the most-likely-relevant defaults uncommented; ask the user.
11. **Guardrail check.** Run `skills/en-guardrail/bin/install-guardrail status`. If neither scope is installed, prompt:
    > "The en-guardrail PreToolUse hook isn't installed. It prompts before destructive Bash commands (recursive rm, DROP TABLE, force-push, terraform destroy, etc.). Choose:
    >   `p` — install project-scoped now (writes to `<repo>/.claude/settings.json`).
    >   `g` — print the global one-liner for me to run from my terminal (active everywhere; agents can't write `~/.claude/` themselves).
    >   `s` — skip for now."

    On `p` → run `skills/en-guardrail/bin/install-guardrail install-project`.
    On `g` → run `skills/en-guardrail/bin/install-guardrail install-global` (no `--apply`) and surface its output verbatim.
    On `s` → record in the report; don't ask again this session.

    Idempotent — if the status check reports any scope active, skip the prompt and note it in the report.
12. **Claude Code Review action check.** Detect `.github/workflows/claude-code-review.yml`. If absent, prompt:
    > "Anthropic's Claude Code Review GitHub Action isn't installed. It runs Claude on every PR and posts inline review comments — these are exactly what `/en-resolve-pr` is built to handle. Install? (`y` / `n`)
    > Auth options:
    >   - **OAuth** (Pro/Max subscription) — free within rate limits. Requires `CLAUDE_CODE_OAUTH_TOKEN` repo secret (generate with `claude setup-token`).
    >   - **API key** — pay-per-use, no rate cap. Requires `ANTHROPIC_API_KEY` repo secret. Edit the workflow after install to switch."

    On `y` → write `.github/workflows/claude-code-review.yml` from `references/templates/github-workflow-claude-review.yml`. Surface a one-line follow-up: "Add `CLAUDE_CODE_OAUTH_TOKEN` to repo secrets (Settings → Secrets and variables → Actions). See `docs/integrations/anthropic-code-review-action.md` for setup."
    On `n` → record in the report; skip.

    Idempotent — if the workflow already exists, note it and don't overwrite.
13. **Auto-merge repo-setting check.** Run `gh api repos/<owner>/<repo> --jq .allow_auto_merge`.
    - `true` → record 🟢 "Auto-merge enabled at repo level."
    - `false` or empty → surface advisory (not blocking):
      > "Auto-merge is disabled at the repo level. `/en-ship --auto-merge` and `/en-resolve-pr --enable-auto-merge` won't be able to enable auto-merge on PRs until you flip Settings → General → 'Allow auto-merge' on. Skipping for now — this is a manual repo setting."

    Idempotent. Don't try to flip it via API — that requires admin scope and is the kind of repo-policy change a human should make explicitly.
14. **Bootstrap-patterns offer.** Surface to user (informational; they decide later):
    > "After you run `/en-foundation --retrofit`, consider `/en-learn --bootstrap-patterns` to seed `docs/learnings/patterns/` from the codebase's existing conventions. It's optional, opt-in, one-time. Bootstrapped entries are flagged `requires_validation: true` and lower-confidence by default — they give the wiki a starting point without pretending to be capture-fresh. See `references/learn-bootstrap-patterns.md`."

    Don't auto-run it. The user decides.
15. **Recommend next steps:**
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

- **Guardrail status** — run `skills/en-guardrail/bin/install-guardrail status`. 🟢 if either scope is installed; 🟡 if neither (offer the same `p`/`g`/`s` prompt as in State 2 step 10).
- **Claude Code Review action status** — check for `.github/workflows/claude-code-review.yml`. 🟢 if present; 🟡 if absent (offer the same `y`/`n` prompt as in State 2 step 11).
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
  - .github/workflows/en-sweep.yml
  - .github/workflows/claude-code-review.yml (Anthropic Code Review action)
  - .ensemble/config.local.example.yaml
  - .claude/settings.json (en-guardrail PreToolUse hook, project-scoped)

Modified:
  - AGENTS.md (appended Ensemble pointer map section)
  - .gitignore (added .ensemble/config.local.yaml)

Skipped:
  - docs/foundation.md (run /en-foundation --retrofit to create)

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

- `references/setup-state-detection.md` — full state detection algorithm + sub-variants
- `references/templates/agents-md-template.md` — AGENTS.md template + substitutions
- `references/templates/claude-md-template.md` — CLAUDE.md template + substitutions
- `references/templates/agents-md-merge-rules.md` — append-merge logic for variants 2b/2c/2d
- `references/templates/github-workflow-en-sweep.yml` — GH Action workflow
- `references/templates/config-local-example.yaml` — committed config template
- `references/learn-index-format.md` — `learnings/index.md` empty-state seed
- `references/learn-log-format.md` — `learnings/log.md` empty-state seed
- `references/host-detect.md` — host detection (used briefly at start)
- `references/templates/github-workflow-claude-review.yml` — Anthropic Code Review action workflow template
- `references/learn-bootstrap-patterns.md` — Mode F (`/en-learn --bootstrap-patterns`) referenced from step 14
- `scripts/check-health` — diagnostic runner (State 3)
- `skills/en-guardrail/bin/install-guardrail` — installs/uninstalls the destructive-command guardrail hook
- `bin/ensemble-classify-plans` — partitions existing `docs/plans/` into conforming vs non-conforming (used in State 2 step 2)
