# The final verification walk

Read at the final verification phase, and again by State 3's diagnostic, which
runs the same required-artifact table.

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

- `.github/workflows/ensemble-lint.yml` (step 1a opt-in). A PR check linting the changed docs, from `references/templates/github-workflow-ensemble-lint.yml`. A decline records `lint_ci.enabled: false`.
- `## Test impact` in `AGENTS.md` (step 1a opt-in). Absent is a valid answer for a beside-the-source layout, and only that one.
- `sweep.schedule` in `.ensemble/config.local.yaml` (step 8 opt-in; the schedule lives on the sweep machine). **A decline is recorded, never silent.** Write `sweep.enabled: false` and report the sweep as *declined*, not *missing*: re-offering an install the operator refused trains them to skim the report.
- `.github/workflows/claude-code-review.yml` (step 11 opt-in)
- `REVIEW.md` (step 13 opt-in)
- `.claude/settings.json` with guardrail PreToolUse hook (step 10 opt-in)
- `.ensemble/config.local.yaml` (step 9 opt-in)

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
