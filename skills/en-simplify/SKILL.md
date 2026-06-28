---
name: en-simplify
description: "Simplify recently changed code for clarity, reuse, quality, and efficiency while preserving exact behavior. Three parallel review dimensions (reuse / quality / efficiency), behavior-preserving, scoped verification. Default scope: the current branch diff vs base. Usable ad-hoc and called by /en-build's post-build phase. Use /en-debug for bugs, not this. Trigger phrases: 'simplify', 'tidy this up', 'refactor pass', 'clean up the diff', 'simplify before PR'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-simplify`

Behavior-preserving simplification of recently changed code. Reviews the change across three dimensions in parallel — **reuse**, **quality**, **efficiency** — applies the safe findings, and verifies behavior held. Prioritizes readable, explicit code over compactness; **fewer lines is not the goal, faster comprehension is.**

> **Behavior-preserving by contract.** Every applied fix must produce the same output for every input, the same error behavior, and the same side effects and ordering. A fix that can't clear that test is skipped. Never simplifies away a safety check.

## Process

1. **Detect host (light).** Source `$ENSEMBLE_ROOT/references/host-detect.md` for path conventions and subagent-dispatch primitives.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit (peer subprocesses don't run simplification passes).
3. **Resolve scope** (first match wins):
   1. **User-named scope** (a file, directory, "the function I just wrote", "this morning's changes") — authoritative; do not widen it.
   2. **In a git repo (default):** the diff between the current branch and its base (`git diff origin/<base>...` or the configured upstream). Covers the common "simplify everything on this feature branch before PR." If no upstream/base, fall back to staged + unstaged (`git diff HEAD`).
   3. **Outside a git repo or no diff:** the most recently modified files named by the user or edited earlier in the conversation.

   If none yields a non-empty scope, **ask** what to simplify (use `AskUserQuestion` in Claude Code / `request_user_input` in Codex). Never silently skip.
4. **Dispatch three review agents in parallel.** Single message, three `Agent` calls (Claude Code) / `spawn_agent` (Codex), each passed the full diff or resolved file set. Use the existing `$ENSEMBLE_ROOT/agents/code-simplifier.md` agent for each dimension, seeded with the dimension's checklist below. Omit any model override so the user's configured settings apply.

   - **Dimension 1 — Reuse:** existing utilities/helpers that could replace new code; new functions duplicating existing functionality; inline logic that could use an existing utility; diff code reimplementing a stdlib/runtime primitive (suggest the built-in only when behavior-equivalent — never swap native UI controls, locale/`Intl` formatting, sort-stability, or serialization edge cases).
   - **Dimension 2 — Quality:** redundant/derivable state; parameter sprawl; copy-paste-with-variation; leaky abstractions; stringly-typed code where constants/enums exist; unnecessary wrapper elements (component-tree frameworks only); nested conditionals 3+ deep (flatten with guards/early returns/lookup tables); unnecessary comments (keep only non-obvious WHY); dead code / unused imports / unused exports (prefer the project's dead-code linter or `ast-grep` over text grep; account for re-exports, dynamic imports, framework exports).
   - **Dimension 3 — Efficiency:** redundant work (N+1, repeated reads, duplicate calls); missed concurrency; hot-path bloat; recurring no-op updates (add change-detection guards); unnecessary existence checks (TOCTOU); memory leaks / unbounded structures; overly broad operations.

   **Balance — avoid over-simplification.** Every flag has an opposite failure mode. Do not inline a helper that names a concept, merge unrelated logic, or remove an abstraction that exists for testability/extensibility or whose purpose you haven't confirmed obsolete (check `git blame`). If a change would be longer or harder to follow, don't flag it.
5. **Apply fixes.** Aggregate findings; apply each directly. Skip false positives silently (don't argue or ask). Before each fix, confirm it preserves behavior (same output/errors/side-effects/ordering); if it can't clear that, skip. **Never simplify away a safety check** — input validation at trust boundaries, error handling that prevents data loss, security checks (authz, escaping, sanitization), and accessibility affordances are not removable boilerplate even when a finding frames them as redundant.
6. **Verify behavior preserved.**
   - Run typecheck + lint over the project (fast; catches broken imports, dropped narrowings, dead code other modules reference).
   - Run tests scoped to the changed paths; broaden when the change has obvious wide reach (heavily-imported utility rewritten, shared code consolidated). If the runner has no scoping, run the full suite.
   - **Do not** relax assertions, weaken types, or skip tests to make checks pass — fix the break or revert the specific change that caused it.
   - If no test/lint/typecheck is configured, state that explicitly; don't silently skip verification.
7. **Summarize by dimension.** Report what was applied per dimension (reuse / quality / efficiency), how many findings were skipped as false-positive, and the behavior-preservation result (checks run + outcome). Example: *"Applied 6 — reuse 2, quality 3, efficiency 1; skipped 2 false positives; typecheck + lint clean, 11 scoped tests pass."* Do not headline a net-lines-removed figure — the measure is what improved and that behavior held, not how much code shrank. If there were no findings, confirm the code didn't need changes.

## Flags

| Flag | Effect |
|---|---|
| `--scope <path>` | Override scope resolution; simplify only this path. |
| `--no-verify` | Skip step 6 verification (rare; surface a warning that behavior preservation is unverified). |

## Commit policy

**Does not commit.** Leaves applied changes in the working tree. When invoked by `/en-build`'s post-build phase, the build's commit flow picks them up; when invoked ad-hoc, the user (or `/en-ship`) commits. Committing here would sweep unrelated uncommitted changes into a misleading `refactor` commit.

## Reference files

- `$ENSEMBLE_ROOT/references/code-simplifier-dispatch.md` — dispatch + revert protocol
- `$ENSEMBLE_ROOT/agents/code-simplifier.md` — the reviewer agent
- `$ENSEMBLE_ROOT/references/host-detect.md`

## Failure protocol

| Failure | Behavior |
|---|---|
| Scope resolves empty | Ask the user what to simplify; never guess. |
| A fix breaks tests/lint/typecheck | Revert that specific change; continue with the rest; surface the regression. |
| A finding would remove a safety check | Skip it; note in the summary that it was preserved deliberately. |
| No test/lint/typecheck configured | State it in the summary; do not claim behavior was verified. |

## What this skill never does

- **Never changes behavior.** Same output/errors/side-effects/ordering, always.
- **Never removes safety checks** (validation, error handling, authz, escaping, accessibility).
- **Never commits.** Leaves changes in the working tree.
- **Never headlines lines-removed** as the win. Clarity, safety, and efficiency fixes often preserve or add lines.
