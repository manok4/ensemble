# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Foundation document (`docs/foundation.md`) — combined PRD + technical design + architecture intent (1,922 lines).
- Plugin manifests for Claude Code (`.claude-plugin/plugin.json`, `marketplace.json`) and Codex (`.codex-plugin/plugin.json`).
- `setup` script for machine-level install across Claude Code and Codex; `scripts/{check-health,sync-to-codex}`.
- Cross-cutting references: host-detect, outside-voice, single-agent-fallback, recursion-guard, finding-schema, severity, severity-and-routing, stable-ids, cli-wrappers, doc-lints, code-simplifier-dispatch, conventional-commits, secret-patterns, research-dispatch, socratic-questions, foundation-questions, setup-state-detection, core-beliefs-starter, pack-reference-template.
- Build/review/QA references: build-orchestration, build-handoff, persona-dispatch, qa-flows, playwright-helpers.
- Garden references: garden-checks, garden-loop-guards, garden-security-model, tech-debt-tracker-format.
- Learn references: learning-frontmatter-schema, learn-cross-ref-maintenance, learn-index-format, learn-log-format, learn-ingest, learn-lint, architecture-update-rules.
- Templates: AGENTS.md, CLAUDE.md, foundation, plan, design-doc, architecture, learning, en-garden GitHub workflow, config.local.example.yaml, agents-md-merge-rules.
- `bin/ensemble-lint` (file-shape doc lint runner with backtick-aware path detection), `bin/ensemble-detect-host` (host detection helper), `bin/ensemble-doc-only-check` (en-garden runtime allowlist), `bin/en-garden-ci` (CI claude-p / codex-exec resolver).
- All 11 skills: `en-setup`, `en-brainstorm`, `en-foundation`, `en-plan`, `en-build`, `en-review`, `en-qa`, `en-learn`, `en-ship`, `en-cross-review`, `en-garden`.
- All 11 agents: 4 always-on reviewers (`correctness-reviewer`, `testing-reviewer`, `maintainability-reviewer`, `standards-reviewer`), 3 conditional reviewers (`security-reviewer`, `performance-reviewer`, `migrations-reviewer`), 3 research agents (`repo-research`, `learnings-research`, `web-research`), 1 refiner (`code-simplifier`, sourced from Anthropic claude-plugins-official).
