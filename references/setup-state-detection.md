# `/en-setup` state detection

How `/en-setup` decides which of three flows to run, and the four sub-variants of State 2.

## Three states

| State | Repo signals | Behavior |
|---|---|---|
| **State 1** — New project | Repo is empty or initial-commit only, AND `docs/foundation.md` doesn't exist | Recommend `/en-brainstorm` then `/en-foundation`. Don't pre-create artifacts. |
| **State 2** — Existing project, no Ensemble | Repo has source code AND (`docs/foundation.md` is absent OR `docs/learnings/` is absent) | Retrofit: create skeleton, generate or merge `AGENTS.md`/`CLAUDE.md`, install GH Action workflow, set up `.ensemble/` config |
| **State 3** — Existing project with Ensemble | `docs/foundation.md` exists AND `docs/learnings/` exists | Diagnostic mode: health checks + repair |

## Detection algorithm

```
function detect_state():
    has_foundation = exists("docs/foundation.md")
    has_learnings = exists("docs/learnings/")  # directory
    has_source = source_code_present()         # see below
    
    if not has_source and not has_foundation:
        return "state-1"
    
    if has_foundation and has_learnings:
        return "state-3"
    
    # Source code OR partial Ensemble OR neither
    if has_source and (not has_foundation or not has_learnings):
        return "state-2"
    
    # Edge case: foundation present but learnings missing — treat as state 2 (partial retrofit)
    # Edge case: empty repo with foundation — treat as state 1 (foundation was started but no project yet)
    if not has_source:
        return "state-1"
    
    return "state-2"  # safe default
```

## "Source code present" heuristic

```
function source_code_present():
    # Any of:
    return any_of(
        exists("package.json"),
        exists("go.mod"),
        exists("Cargo.toml"),
        exists("pyproject.toml"),
        exists("requirements.txt"),
        exists("Gemfile"),
        exists("composer.json"),
        exists("pom.xml"),
        exists("build.gradle"),
        non_empty("src/"),
        non_empty("lib/"),
        non_empty("app/"),
        # More than just README.md and .git/
        files_in_repo_excluding_docs_and_git() > 1
    )
```

## State 2 sub-variants

When State 2 is detected, identify the sub-variant by which map files exist:

| Variant | `AGENTS.md` | `CLAUDE.md` | AGENTS.md action | CLAUDE.md action |
|---|---|---|---|---|
| **2a** | absent | absent | Generate from template | Generate from template |
| **2b** | absent | present | Generate from template; cross-reference existing CLAUDE.md | Append-merge: keep existing content; append Ensemble Claude-specific section if not present |
| **2c** | present | absent | Append-merge: keep existing content; append Ensemble pointer index if not present | Generate from template (one-line cross-ref to AGENTS.md + Claude-specific guidance) |
| **2d** | present | present | Append-merge each: keep existing content; append Ensemble pointer index / Claude-specific section if not present. Never overwrite | Same |

Append-merge logic detailed in `references/templates/agents-md-merge-rules.md`.

## State 1 — Greenfield handoff

`/en-setup` for State 1 doesn't pre-create artifacts. It outputs a one-paragraph guide:

> "This looks like a brand-new project. Recommended next steps:
>
> 1. Run `/en-brainstorm` to explore what you're building. Outputs a design doc.
> 2. Run `/en-foundation` to lock down product requirements and technical direction. This will also create `AGENTS.md`, `CLAUDE.md`, `docs/architecture.md`, the `docs/` skeleton, and an `FR01-project-setup` plan.
>
> Run `/en-setup` again later if you want diagnostics on the project's Ensemble integration."

## State 2 — Retrofit bootstrap

Steps in order (per §5.2.11):

1. **Detect sub-variant** (2a/2b/2c/2d).
2. **Create directory skeleton:** `docs/{plans/{active,completed},learnings/{bugs,patterns,decisions,sources},references,generated,designs}/`. Seed `docs/learnings/index.md` and `log.md`. Seed `docs/generated/plan-index.md` and `learning-index.md` (empty stubs with `generated: true`).
3. **Generate or merge `AGENTS.md`** per sub-variant.
4. **Generate or merge `CLAUDE.md`** per sub-variant.
5. **Add `.gitignore` entries:** `.ensemble/config.local.yaml`. Optionally `docs/learnings/archive/` (ask user).
6. **Install `.github/workflows/en-garden.yml`** from `references/templates/github-workflow-en-garden.yml`. Surface required permissions/secrets per A20.
7. **Create `.ensemble/config.local.example.yaml`** (committed). Offer to create `.ensemble/config.local.yaml` (gitignored) with most-likely-relevant defaults uncommented.
8. **Recommend next steps:**
   - "Run `/en-foundation --retrofit` to back-fill `docs/foundation.md` and `docs/architecture.md` from existing code."
   - "Or jump to `/en-plan` for the next feature; foundation can be filled in later."

## State 3 — Diagnostic mode

Health checks:

| Check | Status |
|---|---|
| `AGENTS.md` exists at root | 🟢 / 🔴 |
| `CLAUDE.md` exists at root | 🟢 / 🔴 |
| `CLAUDE.md` has cross-reference to AGENTS.md | 🟢 / 🟡 |
| `docs/foundation.md` exists with valid frontmatter | 🟢 / 🟡 |
| `docs/architecture.md` exists with valid frontmatter | 🟢 / 🟡 |
| `docs/architecture.md` updated within freshness window | 🟢 / 🟡 |
| `docs/plans/{active,completed}/` directories present | 🟢 / 🟡 |
| `docs/learnings/{bugs,patterns,decisions,sources}/` directories present | 🟢 / 🟡 |
| `docs/learnings/{index.md,log.md}` present | 🟢 / 🟡 |
| `docs/generated/{plan-index.md,learning-index.md}` present with `generated: true` | 🟢 / 🟡 |
| `.github/workflows/en-garden.yml` installed | 🟢 / 🟡 |
| `.ensemble/config.local.example.yaml` present | 🟢 / 🟡 |
| `bin/ensemble-lint --scope docs/` runs clean | 🟢 / 🔴 / 🟡 |
| Required CLIs on PATH (`gh`, `git`, `jq`) | 🟢 / 🔴 |
| At least one of `claude` / `codex` on PATH | 🟢 / 🔴 |
| MCP servers configured (Playwright, Context7) | 🟢 / 🟡 |
| Plugin version current (compare with manifest) | 🟢 / 🟡 |

For each 🔴 / 🟡 check, surface a one-line repair offer:

> "🟡 `docs/learnings/log.md` missing. Repair: create empty seed. (yes/no)"

After all checks, output a summary count: "🟢 12 / 🟡 2 / 🔴 0".

## Reporting

Every `/en-setup` invocation outputs a structured report:

```text
State detected: state-2 (sub-variant 2c)

Created:
  docs/plans/active/
  docs/plans/completed/
  docs/learnings/{bugs,patterns,decisions,sources}/
  docs/learnings/{index.md,log.md}
  docs/generated/{plan-index.md,learning-index.md}
  CLAUDE.md (from template)
  .github/workflows/en-garden.yml
  .ensemble/config.local.example.yaml

Modified:
  AGENTS.md (appended Ensemble pointer map section)
  .gitignore (added .ensemble/config.local.yaml)

Next step:
  Run /en-foundation --retrofit to back-fill foundation and architecture from existing code.
  Or run /en-plan for the next feature.
```

The user always knows what was created, what was modified, and what to do next.
