# Research dispatch — when and how to call research agents

How `en-brainstorm`, `en-plan`, and `en-foundation` decide whether to spawn `repo-research`, `learnings-research`, and `web-research` agents.

## The three research agents

| Agent | Purpose | Latency | When to dispatch |
|---|---|---|---|
| `repo-research` | Scan the codebase for patterns, conventions, file paths, existing implementations | Medium (file reads + grep) | Always for Standard/Deep `en-plan`; always for State-2 `en-foundation` retrofits |
| `learnings-research` | Query `docs/learnings/` for relevant past bugs/patterns/decisions via `index.md` | Fast | Always for Standard/Deep `en-plan` and `en-foundation` |
| `web-research` | External docs (Context7) and best-practice search (WebSearch); URL fetch for ingest | High (network) | Only when local context is thin and external prior art would change the recommendation |

## Dispatch matrix

| Skill | Depth | repo-research | learnings-research | web-research |
|---|---|---|---|---|
| `en-brainstorm` | Lightweight | never | never | optional |
| `en-brainstorm` | Standard | never | never | on-request |
| `en-brainstorm` | Deep | never | never | on-request |
| `en-plan` | Lightweight | optional | **always** | optional |
| `en-plan` | Standard | **always** | **always** | conditional |
| `en-plan` | Deep | **always** | **always** | conditional |
| `en-foundation` | (any) | **always** for retrofits, optional for greenfield | **always** | optional |

**`en-brainstorm` dispatches no scouts.** It reads `docs/learnings/index.md` and the foundation section-index inline (its step-4 bounded scan) rather than spawning `repo-research` or `learnings-research`. A scout would return a gist for less context, but it costs a dispatch round-trip in a skill whose entire cost profile is round-trips. Only `web-research` is ever dispatched here, and only on request.

## Parallelism

When two agents are dispatched in the same phase, fire them **in parallel**. Each returns independently; the orchestrating skill awaits both before proceeding.

In Claude Code:

```
Agent({ subagent_type: "repo-research", ... })   ← single message,
Agent({ subagent_type: "learnings-research", ... }) ← two tool calls
```

In Codex:

```
spawn_agent("repo-research", ...)
spawn_agent("learnings-research", ...)
```

## What each agent receives

### `repo-research`

Inputs:
- One-paragraph summary of what the user is trying to do.
- The files/directories most likely relevant.
- Specific questions: "Where do similar features live?", "What's the file naming convention?", "What test framework is used?"

Output:
- Patterns found (cite file:line).
- Conventions (with examples).
- Existing implementations the new work could reuse or model after.
- File-system map for the relevant area (top-level structure).

### `learnings-research`

Inputs:
- One-paragraph summary of the work.
- Tags / components likely relevant.

Output:
- Top 5–10 matching learnings (cite path + title + one-line summary).
- Direct quotes of `applies_when:` for each match (so the orchestrating skill can judge fit).

The agent reads `docs/learnings/index.md` first (Karpathy's pattern), grep-filters by tag/component/date, then drills into top candidates.

### `web-research`

Inputs:
- Specific question (not "research X" — too broad).
- Whether to use Context7 (for library docs) or WebSearch (for general best practices).
- Any specific libraries or sources to check.

Output:
- Citations with quotes.
- Summary of findings.
- Conflicts or open debates if any.

**Cost-conscious.** Web research has the highest latency and the highest token cost. Skip when:
- The team has prior experience with the area (learnings-research will surface).
- The codebase has prior art (repo-research will surface).
- The recommendation is unlikely to change based on external prior art.

## When to dispatch `web-research` even if the matrix says optional

- User explicitly asks ("look up how X handles this").
- The recommendation depends on a non-trivial external library's behavior.
- The user is on the fence between two approaches and external benchmarks would tip it.

## Conditional dispatch in `en-plan`

Standard/Deep plans dispatch `web-research` when **all** of these hold:
1. The plan touches a 3rd-party library not used elsewhere in the codebase.
2. The library has known footguns (auth, payments, migrations, infra-level concerns).
3. The user hasn't said "skip web research".

Otherwise, skip.

## Token budget

Rough budget per research dispatch:

| Agent | Token budget |
|---|---|
| `repo-research` | 5K–15K (file reads dominate) |
| `learnings-research` | 2K–8K (index.md + 3–5 page reads) |
| `web-research` | 8K–25K (fetches + synthesis) |

For Lightweight skills, **prefer none** unless local context is genuinely insufficient. The depth-scaled defaults above make this automatic.

## Failure protocol

| Failure | Behavior |
|---|---|
| Agent times out | Log; continue without; note "research truncated" in the skill's output |
| Agent returns malformed output | Log; ignore; continue |
| Network failure for `web-research` | Log; suggest user run again later if needed |
| Empty results | Note in skill output; not a failure |

## Evidence dossier (large result sets)

To keep the orchestrator's context small, research agents use the **evidence-dossier** pattern instead of returning every quote inline:

1. **Scout writes bulk evidence to scratch.** The agent writes verbatim quotes with source pointers (`file:line` or URL) to a scratch file at `/tmp/ensemble/<skill>/<run-id>/<agent>.md`, line-capped (~150 lines; oldest-trimmed if exceeded). `<run-id>` is supplied by the dispatching skill (or derived from the task) so parallel agents don't collide.
2. **Agent returns only a gist + path.** The structured return carries a 3–5 line gist (the headline findings) plus `dossier_path`. It does **not** inline the full quote set.
3. **Downstream reads on demand.** The orchestrator (en-plan / en-review / en-foundation) and any downstream agent read `dossier_path` from disk only when they need the detail — they carry the gist in working context, not the full dossier.

**Degraded fallback:** if the scratch write fails (no `/tmp`, permission error), return the findings inline as before and note `dossier_path: null` in the gist. Never drop evidence because the dossier write failed.

This keeps the orchestrator's window bounded regardless of how much the scout read — the cost of deep research lands on disk, not in the conversation.

## Capturing research as a learning

When `en-brainstorm`, `en-plan`, or `en-foundation` learns something *new* via `web-research` that's worth retaining, the capture-from-synthesis reflex (D21) fires:

> "I picked up [insight] from [source]. Capture as a learning?"

User accepts → `/en-learn capture --from-conversation` files it as a `decisions/` or `patterns/` learning, with the source URL recorded for future reference.
