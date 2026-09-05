---
name: en-setup
description: "Ensemble bootstrap and diagnostics for a project: detects its state, creates the docs skeleton, generates AGENTS.md and CLAUDE.md, offers optional integrations and health checks. Trigger phrases: 'set up Ensemble', 'bootstrap Ensemble', 'install Ensemble here', 'retrofit', 'diagnose Ensemble'."
disable-model-invocation: true
---


# `/en-setup`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


Project-level Ensemble bootstrap and diagnostics. Distinct from the global `./setup` script (machine-level install).

> **Hard rule:** This skill is mechanical setup work. **No code review, no peer cross-review, no implementation.** Off-loads anything ambiguous to `/en-brainstorm`, `/en-foundation`, or `/en-plan`.

> **Severity vocabulary.** The lint this skill installs (`bin/ensemble-lint`) emits findings graded P0-P3; the levels are defined in `references/peer-contract.md` and mean the same thing to every skill that reads them. This skill's own report uses 🟢 / 🟡 / 🔴.

## Process

1. **Confirm this is a git repository** and resolve the repo root. Nothing here needs host detection: this skill writes the same `AGENTS.md` and `CLAUDE.md` on either host, offers the same guardrail, and invokes no peer — it set `HOST` and `PEER_AVAILABLE` for years and read neither.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit with a note — this skill should never be peer-invoked. It only reads that variable; it never sets it and never invokes a peer, so it carries none of the protocol for doing so.
3. **Detect state** per `references/setup-state-detection.md`:
   - State 1 — Greenfield (empty repo or initial-commit, no `docs/foundation.md`).
   - State 2 — Existing project, no Ensemble (source code present, foundation or learnings missing). Identify sub-variant 2a/2b/2c/2d by which of `AGENTS.md`/`CLAUDE.md` exist.
   - State 3 — Existing project with Ensemble (`docs/foundation.md` and `docs/learnings/` both present).

     **Legacy learning store.** If `docs/learnings/bugs/`, `patterns/`, `decisions/`, or `sources/` exists, this project predates the artifact-type layout. Surface it before doing anything else:

     > "This project has N entries under the retired directories. The new layout reads `docs/learnings/` flat, `docs/decisions/`, and `docs/CONTEXT.md` — so those entries are **invisible** to capture, lint, and research **without being deleted**. Nothing announces that on its own. Run `/en-learn --migrate` to move them."

     **`en-setup` does not run the migration itself.** It reports and hands off. The procedure is interactive by design — entries whose artifact type is ambiguous need a human, and a scaffolding run is not the place for per-entry classification. Read `references/layout-migration.md` for what the migration does; scaffolding continues around the existing store, which is left untouched.
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
1a. **Probe once, then ask once.** Seven serial prompts made this flow an interview. Issue every probe in one message: `$SKILL_DIR/scripts/ensemble-classify-plans docs/plans` when `docs/plans/` exists, `sweep.enabled` and `lint_ci.enabled` in `.ensemble/config.local.yaml`, the resolved guardrail installer's `status`, `command -v gnhf`, `gh api repos/<owner>/<repo> --jq .allow_auto_merge`, and whether `.github/workflows/claude-code-review.yml`, `.github/workflows/ensemble-lint.yml`, `REVIEW.md` and `.ensemble/config.local.yaml` exist. Then put **one numbered round** to the user, each item with a recommended answer, listing only what the probes left open:

   | Item | Listed when | Recommend |
   |---|---|---|
   | Archive non-conforming plans to `docs/plans/legacy/` (step 2) | `non_conforming` is non-empty | `y` |
   | Ignore `docs/learnings/archive/` (step 9) | always | `n` |
   | Sweep cadence `daily` / `weekly` / `monthly` (step 11) | `sweep.enabled` not `false` | `weekly` |
   | Create `.ensemble/config.local.yaml` (step 12) | absent | `y` |
   | Guardrail scope `p` / `g` / `s` (step 13) | neither scope installed | `p` |
   | Install gnhf (step 13a) | not on PATH | `n` |
   | Claude Code Review action (step 14) | workflow absent | `y` |
   | `REVIEW.md`, with its project type (step 16) | absent | `y` |
   | `ensemble-lint.yml` PR check (step 18) | absent, `lint_ci.enabled` not `false` | `y` |

   A recorded decline is not listed again. The steps below read this round's answers and none of them asks a second time; from here the install runs through step 18 without stopping, printing one line per step as it completes.
2. **Existing-plans archival (run before creating skeleton).** If `docs/plans/` already exists, `$SKILL_DIR/scripts/ensemble-classify-plans docs/plans` (run at step 1a) partitions plans into:
   - `conforming` — already pass Ensemble plan validation; leave in place.
   - `non_conforming` — `.md` files in `docs/plans/` that aren't Ensemble plans (legacy / hand-rolled / from another tool).
   - `subdirs` — unrecognized subdirectories.
   - `tech_debt` — `docs/plans/tech-debt-tracker.md` if present (treat as conforming).

   **If `non_conforming` is non-empty**, the round listed the files and asked whether to archive them to `docs/plans/legacy/`, preserved but no longer picked up by `/en-build`, `/en-learn` or `/en-sweep`, with `/en-plan --from-legacy <path>` as the later migration route.

   On `y` → `mkdir -p docs/plans/legacy`; `git mv` each non-conforming file into `docs/plans/legacy/`. Write `docs/plans/legacy/README.md` documenting:
   - The convention: legacy plans are preserved here untouched; Ensemble skills ignore this directory.
   - The migration path: `/en-plan --from-legacy docs/plans/legacy/<file>.md` brings a legacy plan into the active flow with proper R-ID/U-ID assignment and peer review.
   - The list of archived files with original paths.

   On `n` → leave in place; record in the report that lint will warn (`frontmatter.required-field-missing` etc.) until each file is migrated or archived.

   `subdirs` (unrecognized subdirectories under `plans/`) are surfaced but not auto-archived — they may be in-flight work the user wants to handle manually.
3. **Create directory skeleton:**
   ```
   docs/
     CONTEXT.md            <- the glossary; seeded at step 6
     decisions/            <- ADRs, NNNN-<slug>.md
     plans/{active,completed}/
     learnings/            <- solutions sit flat here
     generated/
     designs/
   ```
   - Use the platform's file-write primitive (Write tool / `apply_patch`).
   - Don't fail if directories already exist.
4. **Seed `docs/learnings/index.md` and `log.md`** from the empty-state templates in `references/learn-index-format.md` and `references/learn-log-format.md`.
5. **Seed `docs/generated/plan-index.md` and `learning-index.md`** with `generated: true` frontmatter and zero entries (these are mandatory per foundation §10.1; lint requires their existence).
6. **Seed `docs/CONTEXT.md` — read `references/glossary-rules.md`.**

   **If the file already exists, never overwrite it.** Copy
   `references/templates/context-template.md` only when `docs/CONTEXT.md` is
   absent. On an existing file the operation is **merge-only**: every existing
   entry is preserved verbatim, and additions are limited to terms from the
   declared domain model that are confirmed missing. `/en-setup` is idempotent, and
   a second run that replaces a curated glossary with freshly model-authored terms
   would break that in the most expensive way available — silently, over content
   nobody can regenerate.

   Then define the project's **core domain nouns**.

   This is the *seeding* path, and it exists because accretion alone cannot reach these terms. A capture defines a word when the work rubs against it, which reliably surfaces peripheral mechanics; the nouns a system is built around rarely break, so they rarely appear in a learning. Without seeding, the glossary fills with edge-case vocabulary and never names what the project is about.

   **Bounded by the source and the bar, never by a count.** The source is the declared domain model — schema, core types, primary models, top-level domain docs. The bar is that a new engineer would need the term defined. A small domain yields a few terms; do not pad to reach a number, and do not reach outside the declared model to find more.

   A full `/en-setup` run is the **repo-wide bootstrap**: it is the only path that can produce a coherent "what is this project" glossary, so it seeds the whole declared model rather than one area.

7. **Generate or merge `AGENTS.md`** per sub-variant (see `references/templates/agents-md-template.md` and `references/templates/agents-md-merge-rules.md`). Substitute `{{PROJECT_NAME}}`, `{{ONE_LINE_PURPOSE}}`, `{{TODAY}}`, plus detected `{{BUILD_CMD}}` / `{{TEST_CMD}}` / `{{LINT_CMD}}` / `{{TYPECHECK_CMD}}` / `{{DEV_CMD}}` / `{{LANG}}`.
8. **Generate or merge `CLAUDE.md`** per sub-variant. Substitute `{{PROJECT_NAME}}` / `{{TODAY}}`. Always ensure the AGENTS.md cross-reference line is the first non-frontmatter line.
9. **Add `.gitignore` entries** if missing. **Verify each entry is actually present after the write — do not assume the write succeeded.**
   - `.ensemble/config.local.yaml` — **required.** Confirm with `grep -qF '.ensemble/config.local.yaml' .gitignore` after writing. If `.gitignore` doesn't exist, create it with this line.
   - Optionally `docs/learnings/archive/` — per the round's answer.

   This step is verified again in the final-verification phase (step 18). Both checks must pass.
10. **Install project-local `bin/ensemble-lint`.** Copy `references/templates/ensemble-lint`, which every skill that lints invokes as the project-relative `bin/ensemble-lint`, to `<repo-root>/bin/ensemble-lint`, `chmod +x` it, and `git add bin/ensemble-lint`. **Idempotent**: if the destination exists AND matches the source, skip the copy but still verify `chmod +x`. **Verification:** `[ -x bin/ensemble-lint ]`; re-checked in step 18. **Re-sync on update:** it is a copy, so re-run this step after a plugin update. Until D101 three sweep scripts were installed here too, for a GitHub workflow that ran them by relative path; the sweep now runs from the skill directory on a dedicated machine and nothing project-local is needed for it.

11. **Sweep schedule (dedicated machine).** The sweep no longer runs in this repo's CI: launchd on a dedicated Mac runs `/en-sweep`'s runner through Codex on a cadence, and the runner merges the doc-only PRs once their checks pass (D101). This step records the choice and prints what to run **on that machine**; it writes no schedule here, because the schedule is not this repo's.

    **Check `.ensemble/config.local.yaml` first.** If it carries `sweep.enabled: false`, skip this step entirely and report the sweep as *declined by config*. Do not re-prompt: the operator already answered, and asking again on every run is what makes a report unreadable.
    1. **Cadence** is the round's answer: `daily` / `weekly` / `monthly` (default `weekly`). Record `sweep.schedule: <name>` in `.ensemble/config.local.yaml` (informational; the cadence lives in the plist on the sweep machine).
    2. **Print the machine-side commands**, with this repo's path filled in:
       ```
       # on the sweep machine, once per repo (the installer is carried by /en-sweep, beside this skill):
       bash <ensemble>/…/en-sweep/scripts/install-sweep-schedule add-repo <path-to-this-checkout>
       # once per machine (re-run to change cadence or the default model):
       bash <ensemble>/…/en-sweep/scripts/install-sweep-schedule install --cadence weekly --hour 9 --model <alias-or-id> --effort high
       ```
       and note that the machine needs `codex`, `gh` (logged in with an identity allowed to merge green PRs) and `jq` on PATH, a clean clone of this repo, and `sweep.model` / `sweep.effort` in that clone's `.ensemble/config.local.yaml` if this repo should override the machine default.
    3. **Note the activity gate:** "The runner skips a repo silently when no non-sweep commits landed since the last sweep; `--force` bypasses it."

12. **Create `.ensemble/config.local.example.yaml`** (committed) from `references/templates/config-local-example.yaml`. Create `.ensemble/config.local.yaml` (gitignored) with the most-likely-relevant defaults uncommented when the round said `y`.
13. **Guardrail check.** The guardrail installer belongs to `/en-guardrail`, which installs as its own skill and may not be present. **Resolve it before use:** look for `install-guardrail` in a sibling `en-guardrail` skill directory alongside this one. If it is not there, say so and point the user at `/en-guardrail` rather than guessing a path — then skip to the next step. Its `status` ran at step 1a. If neither scope is installed, the round offered the hook, which prompts before destructive Bash commands (recursive rm, DROP TABLE, force-push, terraform destroy) **and destructive DB-writing MCP tools** (`mcp__*__run_sql` running `DROP`/`TRUNCATE`/mass `UPDATE`): `p` project-scoped (writes `<repo>/.claude/settings.json`), `g` the global one-liner to run yourself (agents can't write `~/.claude/`), `s` skip.

    On `p` → run the resolved installer with `install-project` (installs **both** the Bash matcher and the MCP DB-tool matcher — EN09).
    On `g` → run the resolved installer with `install-global` (no `--apply`) and surface its output verbatim.
    On `s` → record in the report; don't ask again this session.

    Idempotent — if the status check reports any scope active, the round omitted the item; note it in the report. **Bypass (EN09):** the temporary disable is human-only — export `ENSEMBLE_GUARDRAIL_BYPASS=on` in your shell before launching; the old inline `ENSEMBLE_GUARDRAIL=off <cmd>` prefix no longer works (it was model-writable). Agents must never set/export it.
13a. **gnhf CLI check (optional — only for `/en-loop`).** `/en-loop` uses the `gnhf` CLI (an agent-agnostic autonomous-loop engine) for bounded, overnight, objective-driven loops. `command -v gnhf` ran at step 1a; if absent, the round offered the install (optional, never blocking): gnhf is agent-agnostic and only needed for `/en-loop`, every other Ensemble skill works without it.

    On `y` → run `npm i -g gnhf`; surface the result (and any npm error verbatim). On `n` → record in the report; skip. **Never a hard gate** — gnhf is optional, so declining (or a failed npm install) does not fail setup.

    Idempotent — if `gnhf` is already on PATH (`command -v gnhf`), note its presence; the round omitted the item.
14. **Claude Code Review action check.** If `.github/workflows/claude-code-review.yml` is absent, the round offered Anthropic's Claude Code Review GitHub Action: it runs Claude on every PR and posts inline review comments, which is what `/en-resolve-pr` is built to handle. Auth is either **OAuth** (Pro/Max, `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`) or an **API key** (`ANTHROPIC_API_KEY`, pay-per-use); the workflow is edited after install to switch.

    On `y` → write `.github/workflows/claude-code-review.yml` from `references/templates/github-workflow-claude-review.yml`. Surface a one-line follow-up: "Add `CLAUDE_CODE_OAUTH_TOKEN` to repo secrets (Settings → Secrets and variables → Actions). See `https://github.com/manok4/ensemble/blob/main/docs/integrations/anthropic-code-review-action.md` for setup."
    On `n` → record in the report; skip.

    Idempotent — if the workflow already exists, note it and don't overwrite.
15. **Auto-merge repo-setting check.** Run `gh api repos/<owner>/<repo> --jq .allow_auto_merge`.
    - `true` → record 🟢 "Auto-merge enabled at repo level."
    - `false` or empty → surface advisory (not blocking):
      > "Auto-merge is disabled at the repo level; `/en-ship --auto-merge` and `/en-resolve-pr --enable-auto-merge` need Settings → General → 'Allow auto-merge' switched on."

    Idempotent. Don't try to flip it via API — that requires admin scope and is the kind of repo-policy change a human should make explicitly.
16. **`REVIEW.md` offer.** If `REVIEW.md` is absent at the repo root, the round offered to seed it from the Ensemble-flavored template. It tunes PR review on this repo: severity calibration, nit caps, skip rules, repo-specific checks, convergence on multi-round reviews. Anthropic's managed Code Review service reads it automatically; the self-hosted action's `prompt:` step has to include the file content (see template § 'Wiring `REVIEW.md` into the self-hosted action').

    On `y` → `{{PROJECT_TYPE}}` came with the answer (one of: `backend service` / `frontend app` / `library` / `cli tool` / `docs site` / `mobile app` / `infrastructure` / `mixed`); write `REVIEW.md` from `references/templates/review-md-template.md` with `{{PROJECT_NAME}}` (from `docs/foundation.md` `project:`), `{{PROJECT_TYPE}}`, and `{{PLAN_ID_PREFIX}}` substituted.
    On `n` → record in the report; skip.

    Idempotent — if `REVIEW.md` already exists, note its presence and skip.
17. **Verification-receipt notice (informational).** Surface once, and write nothing:

    > "`/en-build` records which checks passed against an exact working tree, and `/en-ship` skips what
    > that receipt covers. Your pre-push hook can read the same receipt instead of re-running a suite
    > `/en-ship` finished seconds earlier. `/en-ship` carries a `verification-receipt` reference with a
    > snippet to paste into `.git/hooks/pre-push`."

    **This step never creates or edits a hook.** A hook is where a project encodes its own policy;
    rewriting one on a user's behalf is help nobody asked for, and `/en-ship` never bypasses hooks
    either. Print the pointer and move on.

18. **Final verification phase (mandatory, idempotent).** After all install steps complete, **walk every required artifact and confirm it's present**. This is the safety net — long mechanical sequences drop steps under context pressure, and a verification phase at the end catches that.

    **Required artifacts** (must exist; missing → fail):

    | Artifact | Check |
    |---|---|
    | `docs/plans/{active,completed}/` | both directories exist |
    | `docs/learnings/` | exists |
    | `docs/decisions/` | exists |
    | `docs/CONTEXT.md` | exists and carries the flagged-ambiguities tail |
    | `docs/learnings/{index.md,log.md}` | both files exist |
    | `docs/generated/{plan-index.md,learning-index.md}` | both files exist with `generated: true` frontmatter |
    | `docs/designs/` | exists |
    | `AGENTS.md` | exists; contains the Ensemble pointer-map section marker |
    | `CLAUDE.md` | exists; first non-frontmatter line cross-references AGENTS.md |
    | `.gitignore` | contains `.ensemble/config.local.yaml` (`grep -qF '.ensemble/config.local.yaml' .gitignore`) |
    | `./bin/ensemble-lint` | exists, executable (`-x`) |
    | `.ensemble/config.local.example.yaml` | exists |

    **Optional artifacts** (depend on user opt-in earlier; surface in report but don't fail if absent):

    - `.github/workflows/ensemble-lint.yml` (step 1a opt-in). A PR check running `bin/ensemble-lint --scope docs/` on changes to `docs/`, `AGENTS.md` or `CLAUDE.md`. Template at `references/templates/github-workflow-ensemble-lint.yml`. Narrower than the sweep, it reports on a pull request rather than running on a schedule or opening one, so it is its own item. A decline records `lint_ci.enabled: false`.
    - `sweep.schedule` in `.ensemble/config.local.yaml` (step 11 opt-in; the schedule itself lives on the sweep machine). **A decline is recorded, never silent.** Write `sweep.enabled: false` and report the sweep as *declined*, not *missing*. Re-offering an install the operator refused trains them to skim the report.

    - `.github/workflows/claude-code-review.yml` (step 14 opt-in)
    - `REVIEW.md` (step 16 opt-in)
    - `.claude/settings.json` with guardrail PreToolUse hook (step 13 opt-in)
    - `.ensemble/config.local.yaml` (step 12 opt-in)

    **Environment dependencies** (advisory; surface 🟡 in report, do NOT block install):

    | Dependency | Check | Repair if missing |
    |---|---|---|
    | `timeout` or `gtimeout` on PATH (GNU coreutils) | `command -v timeout \|\| command -v gtimeout` | macOS: `brew install coreutils`. Linux distros typically already have it. |
    | `gnhf` on PATH (optional; only for `/en-loop`) | `command -v gnhf` | `npm i -g gnhf` (agent-agnostic loop engine; every other skill works without it) |

    Surface the timeout-binary check as an advisory in the report — do NOT block install on missing it. Users may have legitimate reasons to defer (offline, restricted brew, container without coreutils). The 🟡 line in the report tells them what to install:

    ```
    🟡 No `timeout` binary found on PATH.
       Repair: brew install coreutils  (macOS)
       Used by: the peer helper's timeout wrapper (/en-review, /en-plan,
       /en-foundation). Without it the peer runs unbounded and the
       helper says so on stderr at every call.
    ```

    **For each missing required artifact**: re-run the corresponding install step **once**. If it's still missing, **fail loudly**:

    ```
    ⚠️  /en-setup verification failed.
    Missing required artifacts after retrofit:
      - bin/ensemble-lint (not present)
      - .gitignore (does not contain '.ensemble/config.local.yaml')

    These were supposed to be installed by steps 9–10 but the writes
    didn't take. Re-run /en-setup, or surface this to the user and ask
    them to commit what's there before proceeding.
    ```

    **Idempotency check:** running `/en-setup` again on the same repo must produce zero new changes once verification has passed. Encode this expectation in the report ("Final verification: 14 / 14 required artifacts present").

19. **Recommend next steps:**
    ```
    Two paths:
      - Run /en-foundation --retrofit to back-fill docs/foundation.md and docs/architecture.md from existing code.
        (Recommended for projects that will see continuing development with Ensemble.)
      - Or jump to /en-plan for the next feature; foundation can be filled in later.

    Once /en-foundation has settled and you've seen the codebase's
    conventions surface in real reviews, consider:
      - /en-learn capture — file the first real learning when one earns it
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

Invoke `bash "$SKILL_DIR/scripts/check-health"` — this skill carries it, anchored per `references/script-invocation.md`. It prints 🟢/🟡/🔴 per check. Pipe through and surface the result to the user.

In addition to file-shape and lint checks, the diagnostic includes:

- **Required-artifact verification** - same table as State 2 step 18 (final verification). Each missing required artifact is 🔴; offer the same install step as a repair (e.g. missing `./bin/ensemble-lint` → "Re-run the bin-install from State 2 step 10? (y/n)"). This catches projects that were retrofitted before the bin-install step existed and never got the project-local lint.
- **Sweep schedule** — read `sweep.enabled` / `sweep.schedule` from `.ensemble/config.local.yaml`: 🟢 recorded, 🟡 absent (print the step 11 machine-side commands). A leftover `.github/workflows/en-sweep.yml` is 🟡 *retired; delete it*. Whether the dedicated machine's launchd job is loaded is that machine's `install-sweep-schedule status`, not something this repo can see.
- **Guardrail status** — run the resolved `install-guardrail` with `status` (see the guardrail check for how it resolves; 🟡 and skip when `/en-guardrail` is not installed). 🟢 if either scope is installed; 🟡 if neither (offer the same `p`/`g`/`s` prompt as in State 2 step 13).
- **Claude Code Review action status** — check for `.github/workflows/claude-code-review.yml`. 🟢 if present; 🟡 if absent (offer the same `y`/`n` prompt as in State 2 step 14).
- **Auto-merge repo-setting** — `gh api repos/<owner>/<repo> --jq .allow_auto_merge`. 🟢 if `true`; 🟡 advisory if `false` (manual repo setting; surface the path: Settings → General → "Allow auto-merge").
- **`timeout` / `gtimeout` on PATH** — `command -v timeout || command -v gtimeout`. 🟢 if either resolves; 🟡 advisory if neither (surface the macOS install path: `brew install coreutils`). Used by the peer helper's timeout wrapper. Advisory-only: the helper says on stderr when it runs unbounded.
- **`gnhf` CLI (optional; only for `/en-loop`)** — `command -v gnhf`. 🟢 if present; 🟡 advisory if absent (surface `npm i -g gnhf`). Agent-agnostic loop engine that `/en-loop` wraps; only needed for `/en-loop`, so its absence is never 🔴 — every other skill works without it.

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
  - docs/CONTEXT.md
  - docs/decisions/
  - docs/learnings/{index.md,log.md}
  - docs/generated/{plan-index.md,learning-index.md}
  - CLAUDE.md (from template)
  - REVIEW.md (review-only instructions; from template)
  - .github/workflows/claude-code-review.yml (Anthropic Code Review action)
  - ./bin/ensemble-lint (chmod +x)
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
| GH Action workflow already exists with different content | Don't overwrite. Surface a warning: "Existing `.github/workflows/<file>.yml` differs from template; leaving as-is. Compare manually if you want to update." A leftover `en-sweep.yml` from before D101 is reported as retired: delete it, the sweep runs from the dedicated machine now. |
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
- `references/templates/config-local-example.yaml` — committed config template
- `references/learn-index-format.md` — `learnings/index.md` empty-state seed
- `references/learn-log-format.md` — `learnings/log.md` empty-state seed
- `references/templates/github-workflow-claude-review.yml` — Anthropic Code Review action workflow template
- `references/templates/review-md-template.md` — `REVIEW.md` Ensemble-flavored default; State 2 step 16
- `scripts/check-health` — diagnostic runner (State 3)
- `install-guardrail`, carried by `/en-guardrail` — installs/uninstalls the destructive-command guardrail hook
- `$SKILL_DIR/scripts/ensemble-classify-plans` — partitions existing `docs/plans/` into conforming vs non-conforming (used in State 2 step 2)
