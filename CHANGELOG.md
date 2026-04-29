# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Foundation document (`docs/foundation.md`) — combined PRD + technical design + architecture intent.
- Plugin manifests for Claude Code and Codex.
- Phase 1 cross-cutting references (host-detect, outside-voice, finding-schema, severity-and-routing, learning frontmatter, doc-lints, etc.).
- `bin/ensemble-lint` (file-shape doc lint runner) and `bin/ensemble-detect-host` (host detection helper).
- `setup` script for machine-level install across Claude Code and Codex.
- Skills: `en-setup`, `en-brainstorm`, `en-foundation`, `en-plan`.
- Always-on reviewer agents: `correctness-reviewer`, `testing-reviewer`, `maintainability-reviewer`, `standards-reviewer`.
