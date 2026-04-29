---
name: en-setup
description: "Project-level Ensemble bootstrap and diagnostics. Detects whether a repo is greenfield (State 1), an existing project without Ensemble (State 2 with sub-variants 2a/2b/2c/2d), or already integrated (State 3). Creates the docs/ skeleton, generates or append-merges AGENTS.md and CLAUDE.md, installs the en-garden GitHub Action, sets up .ensemble/ config files, and runs health checks. Use whenever the user wants to install Ensemble in a project, bootstrap a new repo, retrofit an existing repo, or diagnose Ensemble integration. Trigger phrases: 'set up Ensemble', 'bootstrap Ensemble in this project', 'install Ensemble here', 'check my Ensemble setup', 'diagnose Ensemble', 'retrofit this project'."
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
  2. Run /en-foundation to lock product+technical scope, generate AGENTS.md / CLAUDE.md / docs/architecture.md, and emit FR01-project-setup.

Run /en-setup again later for diagnostics on Ensemble integration.
```

Exit.

## State 2 — Retrofit bootstrap

Run all of these in order. Each step is idempotent — running `/en-setup` twice produces the same end state.

1. **Confirm sub-variant.** Probe for `AGENTS.md` / `CLAUDE.md` existence; classify as 2a/2b/2c/2d.
2. **Create directory skeleton:**
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
3. **Seed `docs/learnings/index.md` and `log.md`** from the empty-state templates in `references/learn-index-format.md` and `references/learn-log-format.md`.
4. **Seed `docs/generated/plan-index.md` and `learning-index.md`** with `generated: true` frontmatter and zero entries (these are mandatory per foundation §10.1; lint requires their existence).
5. **Generate or merge `AGENTS.md`** per sub-variant (see `references/templates/agents-md-template.md` and `references/templates/agents-md-merge-rules.md`). Substitute `{{PROJECT_NAME}}`, `{{ONE_LINE_PURPOSE}}`, `{{TODAY}}`, plus detected `{{BUILD_CMD}}` / `{{TEST_CMD}}` / `{{LINT_CMD}}` / `{{TYPECHECK_CMD}}` / `{{DEV_CMD}}` / `{{LANG}}`.
6. **Generate or merge `CLAUDE.md`** per sub-variant. Substitute `{{PROJECT_NAME}}` / `{{TODAY}}`. Always ensure the AGENTS.md cross-reference line is the first non-frontmatter line.
7. **Add `.gitignore` entries** if missing:
   - `.ensemble/config.local.yaml`
   - Optionally `docs/learnings/archive/` — ask the user.
8. **Install `.github/workflows/en-garden.yml`** from `references/templates/github-workflow-en-garden.yml`. Surface required permissions/secrets per A20 in a one-line note: "Garden needs `ANTHROPIC_API_KEY` (or `OPENAI_API_KEY`) in repo secrets to run."
9. **Create `.ensemble/config.local.example.yaml`** (committed) from `references/templates/config-local-example.yaml`. **Offer** to create `.ensemble/config.local.yaml` (gitignored) with the most-likely-relevant defaults uncommented; ask the user.
10. **Recommend next steps:**
    ```
    Two paths:
      - Run /en-foundation --retrofit to back-fill docs/foundation.md and docs/architecture.md from existing code.
        (Recommended for projects that will see continuing development with Ensemble.)
      - Or jump to /en-plan for the next feature; foundation can be filled in later.
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
  - .github/workflows/en-garden.yml
  - .ensemble/config.local.example.yaml

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
| GH Action workflow already exists with different content | Don't overwrite. Surface a warning: "Existing `.github/workflows/en-garden.yml` differs from template; leaving as-is. Compare manually if you want to update." |
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
- `references/templates/github-workflow-en-garden.yml` — GH Action workflow
- `references/templates/config-local-example.yaml` — committed config template
- `references/learn-index-format.md` — `learnings/index.md` empty-state seed
- `references/learn-log-format.md` — `learnings/log.md` empty-state seed
- `references/host-detect.md` — host detection (used briefly at start)
- `scripts/check-health` — diagnostic runner (State 3)
