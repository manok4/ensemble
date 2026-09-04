---
name: en-simplify
description: "Simplify recently changed code for clarity, reuse and efficiency while preserving exact behavior; default scope is the branch diff. Use /en-debug for bugs, not this. Trigger phrases: 'simplify', 'tidy this up', 'refactor pass', 'clean up the diff', 'simplify before PR'."
---


# `/en-simplify`

> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Behavior-preserving simplification of recently changed code. Reviews the change across three dimensions in parallel — **reuse**, **quality**, **efficiency** — applies the safe findings, and verifies behavior held. Prioritizes readable, explicit code over compactness; **fewer lines is not the goal, faster comprehension is.**

> **Behavior-preserving by contract.** Every applied fix must produce the same output for every input, the same error behavior, and the same side effects and ordering. A fix that can't clear that test is skipped. Never simplifies away a safety check.

## Process

1. **Resolve the subagent primitive.** `Agent` with `subagent_type` on Claude Code, `spawn_agent` on Codex. That is the only host fact this skill needs — it invokes no peer, so it carries none of the peer-detection machinery.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit — a peer subprocess does not run simplification passes. This skill only *reads* that variable; it never invokes a peer and never sets it, so it carries none of the protocol for doing so.
3. **Resolve scope** (first match wins):
   1. **User-named scope** (a file, directory, "the function I just wrote", "this morning's changes") — authoritative; do not widen it.
   2. **In a git repo (default):** the diff between the current branch and its base (`git diff origin/<base>...` or the configured upstream). Covers the common "simplify everything on this feature branch before PR." If no upstream/base, fall back to staged + unstaged (`git diff HEAD`).
   3. **Outside a git repo or no diff:** the most recently modified files named by the user or edited earlier in the conversation.

   If none yields a non-empty scope, **ask** what to simplify (use `AskUserQuestion` in Claude Code / `request_user_input` in Codex). Never silently skip.

   **When a caller passed an explicit scope, never ask.** `/en-build` invokes this inside a phase whose autonomy contract permits pauses only in seven enumerated cases, and a question here is not one of them. A caller-supplied scope that resolves empty is a **result to return**, not a question to ask: report "nothing in scope" and let the caller decide. Asking a human who is not watching stalls a build that was told to run unattended.
3a. **Preflight the scope before dispatching anything.** If it holds no substantive human-authored code — only documentation, generated or vendored files, dependencies or lockfiles, or mechanical churn like a formatter sweep — report that there is nothing to simplify and stop. Do not dispatch. On a mixed scope, keep the code and drop the rest.

   **This is a kind gate, never a size gate.** A three-line change the user explicitly named still runs; a thousand-line lockfile diff does not. Size thresholds belong to the caller, and applying one here would silently decline work someone asked for. The cost of getting this wrong is three agents reading a lockfile.

4. **Dispatch three review agents in parallel.** Single message, three `Agent` calls (Claude Code) / `spawn_agent` (Codex), each passed the full diff or resolved file set. Use the existing `agents/code-simplifier.md` agent for each dimension, seeded with the dimension's checklist below. Omit any model override so the user's configured settings apply.

   **The reviewers are read-only in this skill.** Each returns findings; **step 5 applies them, in the parent**. `code-simplifier`'s own description says it may modify files — that is true of it elsewhere and must not be true here, because three of them run **concurrently on one working tree** and three writers editing the same files is a race whose outcome depends on scheduling. Say so in every dispatch prompt rather than relying on the reader inferring it.

   Because they only find and never write, this is evidence-tier work rather than ceiling: the judgement that becomes an edit is made by the parent at step 5.

   - **Dimension 1 — Reuse:** existing utilities/helpers that could replace new code; new functions duplicating existing functionality; inline logic that could use an existing utility; diff code reimplementing a stdlib/runtime primitive (suggest the built-in only when behavior-equivalent — never swap native UI controls, locale/`Intl` formatting, sort-stability, or serialization edge cases).
   - **Dimension 2 — Quality:** redundant/derivable state; parameter sprawl; copy-paste-with-variation; leaky abstractions; stringly-typed code where constants/enums exist; unnecessary wrapper elements (component-tree frameworks only); nested conditionals 3+ deep (flatten with guards/early returns/lookup tables); unnecessary comments (keep only non-obvious WHY); dead code / unused imports / unused exports (prefer the project's dead-code linter or `ast-grep` over text grep; account for re-exports, dynamic imports, framework exports).
   - **Dimension 3 — Efficiency:** redundant work (N+1, repeated reads, duplicate calls); missed concurrency; hot-path bloat; recurring no-op updates (add change-detection guards); unnecessary existence checks (TOCTOU); memory leaks / unbounded structures; overly broad operations.

   **When a dispatch cannot run.** A concurrency or active-agent limit is **backpressure, not failure**: leave that reviewer queued and retry when a slot frees. Treating a limit as a failed reviewer silently drops a whole dimension. A failure that correcting the call will not fix — no subagent primitive on this host, a persistent error — runs **inline in the parent** with the same rubric, and the summary discloses the substitution in one line. Proceed only when all three dimensions have an outcome; applying two and reporting a pass overstates what was checked.

   **Balance — avoid over-simplification.** Every flag has an opposite failure mode. Do not inline a helper that names a concept, merge unrelated logic, or remove an abstraction that exists for testability/extensibility or whose purpose you haven't confirmed obsolete (check `git blame`). If a change would be longer or harder to follow, don't flag it.
5. **Apply fixes.** Aggregate findings; apply each directly. Skip false positives silently (don't argue or ask).

   **Inspect widely, edit narrowly.** Reading beyond the scope to judge a finding is expected — you cannot tell whether a helper is duplicated without looking at the rest of the codebase. **Editing** beyond it is not: confine edits to the resolved scope plus the import and export seams a change makes necessary. When the user named a file or directory, those seams must be inside it too; skip any fix that would edit outside that boundary. A simplifier that quietly edits a caller three directories away is not doing what was asked.

   **An interface that only ever existed in this unshipped scope is not behavior.** A compatibility shim, an intermediate signature, a data shape introduced earlier in the very work being simplified — none of it is protected once you have verified it has no deployed, persisted, public, external, dependent-branch, or in-repo caller outside the scope. Remove it only when every caller update it requires fits inside the mutation boundary above; otherwise keep it. Without this rule the pass preserves scaffolding it watched being built twenty minutes ago. Before each fix, confirm it preserves behavior (same output/errors/side-effects/ordering); if it can't clear that, skip. **Never simplify away a safety check** — input validation at trust boundaries, error handling that prevents data loss, security checks (authz, escaping, sanitization), and accessibility affordances are not removable boilerplate even when a finding frames them as redundant.
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

- `references/code-simplifier-dispatch.md` — dispatch + revert protocol
- `agents/code-simplifier.md` — the reviewer agent

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
