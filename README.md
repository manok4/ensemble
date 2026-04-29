# Ensemble

> A host-agnostic product-development plugin for **Claude Code** and **Codex**, with cross-agent peer review and a compounding learning store.

Ensemble is an 11-skill, 11-agent toolkit that takes work from rough idea to shipped, peer-reviewed code. Every skill detects whether it's running under Claude Code or Codex and adapts tool names, peer-review CLI invocations, and platform-specific behaviors accordingly.

**Status: Phases 0–6 complete.** Foundation document, all 11 skills, all 11 agents, all cross-cutting references, plugin manifests, install script, and CI tooling are in place. See [`docs/foundation.md`](./docs/foundation.md) for the full design and [`CHANGELOG.md`](./CHANGELOG.md) for what landed.

---

## Five design pillars

1. **Document-as-source-of-truth.** Every phase produces a durable artifact in `docs/`; the next phase reads it.
2. **Map, not encyclopedia.** `AGENTS.md` and `CLAUDE.md` are pointer indexes (~100 lines each); SKILL.md files are 150–400 lines with templates externalized to `references/`.
3. **Cross-agent peer review.** Claude Code and Codex review each other's work via subprocess CLI calls (`claude -p` ↔ `codex exec`). Single-agent fallback is supported when only one CLI is installed.
4. **Compounding knowledge.** Every solved problem and decision is captured in `docs/learnings/` and queried automatically by future runs.
5. **Lean by design.** SKILL.md targets 150–400 lines; agents are short specialist prompts.

## Skill catalog (planned)

| Skill | Purpose |
|---|---|
| `/en-setup` | Project-level bootstrap and diagnostics |
| `/en-brainstorm` | Q&A + research + 2–3 approaches |
| `/en-foundation` | Combined PRD + technical direction + initial architecture |
| `/en-plan` | Feature/component/refactor plan with stable U-IDs |
| `/en-build` | Execute the plan with per-unit peer review |
| `/en-review` | Multi-persona code review |
| `/en-qa` | System checks + Playwright browser end-to-end testing |
| `/en-learn` | Compounding wiki maintainer (capture / ingest / refresh / pack / lint) |
| `/en-ship` | Pre-flight + commit + push + PR |
| `/en-cross-review` | Ad-hoc peer review of any artifact |
| `/en-garden` | Doc-drift cleanup on every PR merge to `main` |

## Installation

> **Both paths require at least one of `claude` (Claude Code) or `codex` CLI installed.** Both is recommended for full cross-agent peer review; single-agent fallback works with one.

### Path 1 — Direct clone + `./setup` (preferred)

Works for Claude Code, Codex, or both, on any host:

```bash
git clone https://github.com/manok4/ensemble.git ~/.ensemble-source
cd ~/.ensemble-source && ./setup
```

The `./setup` script auto-detects which CLIs are installed and symlinks (or copies on Windows) the skills and agents into the right places. Run with `--verify-only` to check without making changes.

### Path 2 — Claude Code marketplace (alternative)

```text
/plugin marketplace add manok4/ensemble
/plugin install ensemble@ensemble
```

For a Codex sidecar install on the same machine, see [`docs/foundation.md` §19.2 Path 2](./docs/foundation.md#192-phase-a--machine-level-install-one-time-per-machine).

## Project setup (per-repo)

After installing globally, in any project run:

```text
/en-setup
```

It detects whether the project is greenfield, has source code but no Ensemble, or already has Ensemble installed, and acts accordingly. See [`docs/foundation.md` §5.2.11](./docs/foundation.md#5211-en-setup) for state-detection details.

## Repository layout

```
ensemble/
├── .claude-plugin/        # Claude Code plugin manifest
├── .codex-plugin/         # Codex plugin manifest
├── skills/                # 11 skills (en-*)
├── agents/                # 11 agent definitions
├── references/            # Cross-skill references and templates
├── bin/                   # ensemble-lint, ensemble-detect-host, en-garden-ci
├── scripts/               # check-health, sync-to-codex
├── hooks/                 # Optional SessionStart hook
├── docs/                  # Foundation + project docs
├── setup                  # Bash install script
└── package.json
```

## Documentation

- **[Foundation](./docs/foundation.md)** — full design (combined PRD + TDD + architecture intent). 1,900+ lines.

## License

[MIT](./LICENSE)
