# Build handoff (build-handoff flavor)

The default `en-build` flavor when **HOST = Codex**. Codex implements natively; Claude is dispatched as a **PEER-REVIEWER** (subject to D30: peer reports, host applies — never edits files). Codex parses the findings, applies what it agrees with, defers others to `tech-debt-tracker.md`, then commits.

> **Critical distinction.** This file describes PEER-REVIEWER dispatch. Worker dispatch (build-by-orchestration) lives in `build-orchestration.md`. Peer-reviewers must never modify files, run commands, or make commits — only return findings.

## Flow per unit

```
┌────────────────────────────────────────────────────────────────────┐
│  HOST = Codex                                                      │
│                                                                    │
│  for unit in plan.units:                                           │
│    1. Codex implements natively (edits files, runs tests).         │
│    2. Verification gate 1 (unit tests + lint).                     │
│    3. Code-simplifier pass (per references/code-simplifier-       │
│       dispatch.md).                                                │
│    4. Verification gate 2 (re-run after simplifier; revert on    │
│       failure).                                                    │
│    5. Dispatch Claude as PEER-REVIEWER:                            │
│         claude -p --output-format json --max-turns 1 "<prompt>"  │
│         with ENSEMBLE_PEER_REVIEW=true                             │
│    6. Claude returns findings JSON (does NOT edit files — D30).    │
│    7. Codex parses JSON; apply / defer / disagree per             │
│       references/severity.md.                                      │
│    8. Re-verify if any code changed.                               │
│    9. Commit (conventional message + U-ID + peer findings noted).  │
└────────────────────────────────────────────────────────────────────┘
```

## Peer-reviewer dispatch prompt

Use the Outside Voice prompt from `references/outside-voice.md` with these substitutions:

| Variable | Value |
|---|---|
| `{ARTIFACT_TYPE}` | `code unit (per-unit diff during en-build)` |
| `{ONE_LINE_PROJECT_CONTEXT}` | One sentence from `AGENTS.md` first paragraph |
| `{ONE_LINE_GOAL}` | The unit's "Goal" from the plan |
| `{ARTIFACT_BODY}` | The post-simplifier diff plus the unit's plan section |
| `{PEER_MODE}` | `cross-agent` (or `single-agent-fallback` if Codex is also the only CLI) |

The prompt explicitly forbids file edits, commands, and commits (D30). The peer returns JSON-only findings.

## Single-agent fallback (when only Codex installed)

If Claude CLI isn't installed, fall back to **fresh subprocess of Codex itself** (`codex exec` with a separate context window):

- `PEER_MODE=single-agent-fallback`
- `PEER_CMD=codex exec`
- Outside Voice prompt augmented per `references/single-agent-fallback.md` (be more aggressive, bias toward finding problems)
- The contract from D30 still holds — the fresh Codex subprocess returns findings only.

## What Codex applies (step 7)

For each finding, Codex chooses one of three responses (per `references/severity.md`):

1. **Agree and apply.** Edit files; re-verify; commit.
2. **Agree but defer.** Append entry to `docs/plans/tech-debt-tracker.md` with a TD-ID. Cite the unit.
3. **Disagree with rationale.** Note in unit progress report; don't apply.

The user is surfaced only on contention (host disagrees with P0; high-confidence security/architecture deferral; peer verdict = reject; conflicting findings).

## Re-verify after applying

Same as build-by-orchestration — if Codex applies any code changes in response to peer findings, re-run unit tests + lint before commit. On failure: `git restore`; surface to user.

## Commit message format

```
<type>(<scope>): <short subject> — U<N>

<body>

Implementer: codex (native)
Code-simplifier: <changed N files | skipped>
Peer review (claude, mode: cross-agent):
  - Applied: <count> findings
  - Deferred to tech-debt-tracker.md: <count> findings
  - Disagreed: <count> findings
```

## Failure of peer subprocess

| Failure | Behavior |
|---|---|
| `claude -p` subprocess times out | Mark peer review as skipped for this unit; commit without peer verdict; surface in summary |
| Malformed JSON response | Retry once with "respond with valid JSON only" suffix; on second failure, mark as skipped |
| Peer subprocess CLI error | Surface; offer to retry with `--no-peer-per-unit` to continue without |
| Peer attempted to modify files (D30 violation) | Detect by checking git status before/after subprocess; revert any changes; log violation; do not trust this round of findings |

## Detecting D30 violations

Before invoking the peer subprocess:

```bash
git stash --include-untracked --quiet
PEER_BASE_SHA=$(git rev-parse HEAD)
```

After:

```bash
if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: peer subprocess modified the working tree (D30 violation). Reverting." >&2
  git restore --staged .
  git restore .
  git clean -fd  # remove any untracked files the peer created
  # Do not trust this round of findings — they came from a process that broke its contract
fi
git stash pop --quiet
```

This is defensive — Outside Voice prompt is explicit about not editing, so violations should be rare. The check ensures they're caught and contained.

## When to use this flavor

- HOST = Codex (default).
- HOST = Claude but user passed `--handoff` to explicitly use peer-reviewer dispatch.

## Environment

- `ENSEMBLE_PEER_REVIEW=true` is set in the subprocess — recursion guard.
- `--max-turns 1` for the peer call (single response).
- `peer_timeout_seconds` from `~/.ensemble/config.json` (default 600).
