# Build orchestration (build-by-orchestration flavor)

The default `en-build` flavor when **HOST = Claude Code**. Claude is the host; Codex is dispatched as a **WORKER** (not a peer reviewer) to implement each unit. Claude reviews the returned diff itself; the cross-agent property (implementer ≠ reviewer) is naturally satisfied.

> **Critical distinction.** This file describes WORKER dispatch (D29 + D30 worker-vs-peer-reviewer note). The peer-reviewer dispatch lives in `build-handoff.md`. Worker dispatch is **not** subject to D30's "peer reports, host applies" rule — workers may edit files, run tests within their scope, and return diffs.

## Flow per unit

```
┌────────────────────────────────────────────────────────────────────┐
│  HOST = Claude Code                                                │
│                                                                    │
│  for unit in plan.units:                                           │
│    1. Dispatch Codex as WORKER:                                    │
│         "Implement <unit>. Files: ... Approach: ... Verify       │
│          tests pass. Return the diff and a summary."               │
│    2. Codex returns: diff + summary + tests_passed: true|false     │
│    3. Verification gate 1 (Claude re-runs unit tests + lint).      │
│    4. Code-simplifier pass (per references/code-simplifier-       │
│       dispatch.md).                                                │
│    5. Verification gate 2 (re-run after simplifier; revert on    │
│       failure).                                                    │
│    6. Claude reviews the simplified diff itself, forms findings.   │
│       (No subprocess — cross-agent property already satisfied.)    │
│    7. Apply / defer / disagree per references/severity.md.         │
│    8. Re-verify if any code changed.                               │
│    9. Commit (conventional message + U-ID + peer findings noted).  │
└────────────────────────────────────────────────────────────────────┘
```

## Dispatch prompt template (WORKER)

The Codex worker dispatch must clearly identify itself as a WORKER, not a peer reviewer. Use explicit role markers:

```text
ROLE: WORKER (you implement; you may edit files; you may run tests within your scope).

TASK: Implement {U_ID} from {PLAN_PATH}.

UNIT SPECIFICATION (verbatim from plan):
{UNIT_BLOCK}

PROJECT CONTEXT:
{AGENTS_MD_EXCERPT}

CONSTRAINTS:
- Implement only the files listed in the unit's "Files" field. Don't sprawl.
- Honor the unit's "Execution note" (test-first | characterization-first | pragmatic).
- Run unit-level tests + project lint before returning.
- Return: a unified diff, a short summary, and a tests_passed boolean.

You are NOT the peer reviewer. You are the worker. Edit files, run commands as needed.

Output format (JSON):
{
  "summary": "<2-3 sentences>",
  "tests_passed": true | false,
  "lint_passed": true | false,
  "diff": "<unified diff>",
  "files_modified": ["<repo-relative path>", ...],
  "notes": "<optional notes for the host>"
}
```

## Why this flavor satisfies implementer ≠ reviewer

- **Implementer:** Codex (as worker).
- **Reviewer:** Claude (the host) reads Codex's diff and forms findings.

No separate `claude -p` / `codex exec` peer-review subprocess is needed in this flavor — the cross-agent property is already satisfied by the dispatch shape.

## What Claude reviews (steps 6–7)

Claude reviews the **simplified diff** (after code-simplifier pass) using the same review heuristics as the persona reviewers — correctness, testing, maintainability, standards. Inline review, not via `Agent` tool dispatch (since this is the host doing the review itself, not delegating).

The review produces findings in the same shape as `references/finding-schema.md`. Apply / defer / disagree routing is in `references/severity.md`.

## Re-verify after host applies findings

If Claude applies any code edits in step 7, re-run unit tests + lint before commit. On failure: `git restore` the changes; surface to user. The host never commits broken code in pursuit of a finding.

## Failure of Codex worker

| Failure | Behavior |
|---|---|
| Codex returns `tests_passed: false` | Pause; surface failure; ask user whether to retry, manually fix, or skip the unit |
| Codex returns malformed JSON | Retry once with "respond with valid JSON only"; on second failure, escalate to user |
| Codex subprocess times out | Mark unit as failed; continue with subsequent units only if dependencies allow; surface at the end |
| Codex dispatch fails (CLI error) | Fall back to **build-handoff** flavor: Claude implements natively; this is degraded — surface as a one-line note |

## Commit message format

```
<type>(<scope>): <short subject> — U<N>

<body>

Implementer: codex (worker)
Code-simplifier: <changed N files | skipped>
Host review findings:
  - Applied: <count> findings
  - Deferred to tech-debt-tracker.md: <count> findings
  - Disagreed: <count> findings
```

## When to NOT use this flavor

- Codex CLI not on PATH → fall back to `build-handoff` (which itself falls back to single-agent if claude CLI also missing).
- User passed `--no-orchestrate` → Claude implements natively, treats this as build-handoff.
- Unit's "Execution note" is `characterization-first` AND the unit is highly intertwined with existing code → orchestrating to a worker often loses context; consider native implementation with `--no-peer-per-unit` if the user wants to skip cross-review.

## Environment

- `ENSEMBLE_PEER_REVIEW=true` is **not** set for worker dispatch — that env var is the recursion guard for *peer review*, not workers. Workers can perform their full operations.
- Pass `--max-turns` aggressively (e.g., 30) so Codex has room to iterate on tests within the unit.
