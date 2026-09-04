# Research dispatch — when and how to call research agents

How `en-brainstorm`, `en-plan`, and `en-foundation` decide whether to spawn `repo-research`, `learnings-research`, and `web-research` agents.

## The three research agents

| Agent | Purpose | Latency | When to dispatch |
|---|---|---|---|
| `repo-research` | Scan the codebase for patterns, conventions, file paths, existing implementations | Medium (file reads + grep) | Always for Standard/Deep `en-plan`; always for State-2 `en-foundation` retrofits |
| `learnings-research` | Query `docs/learnings/` for relevant past terms, decisions, and solutions via `index.md` | Fast | Always for `en-review`; for `en-plan` only when an inline read of `index.md` turns up more candidates (~5+) than it can drill into itself |
| `web-research` | External docs (Context7) and best-practice search (WebSearch); URL fetch for ingest | High (network) | Only when local context is thin and external prior art would change the recommendation |

## Dispatch matrix

| Skill | Depth | repo-research | learnings-research | web-research |
|---|---|---|---|---|
| `en-brainstorm` | Lightweight | never | never | skip unless asked |
| `en-brainstorm` | Standard | never | never | round-1 item; default skip |
| `en-brainstorm` | Deep | never | never | round-1 item; default skip |
| `en-plan` | Lightweight | optional | index inline | optional |
| `en-plan` | Standard | **always** | index inline; agent when ~5+ candidates | conditional |
| `en-plan` | Deep | **always** | index inline; agent when ~5+ candidates | conditional |
| `en-foundation` | (any) | **always** for retrofits, optional for greenfield | never | optional |
| `en-learn` | (any) | never | on a genuinely broad overlap search only | never |
| `en-debug` | (any) | fallback only, when span-to-source cannot anchor | never | never |
| `en-setup` | (any) | never | never | never |
| `en-sweep` | (any) | **always**, for architecture drift | never | never |
| `en-review` | (any) | never | **always** | never |

**`en-sweep` dispatches only `repo-research`**, for its architecture-drift check. Its wiki-graph check runs `/en-learn --lint`, and a lint wants the whole graph rather than the handful of entries a scout returns, so it never dispatches `learnings-research`.

**`en-review` dispatches only `learnings-research`,** in the same parallel batch as the dimension reviewers, to surface prior decisions a finding may already be settled by. It never dispatches `repo-research`: a review is anchored in the diff in front of it, and the persona reviewers read whatever surrounding code they need directly.

**`en-learn` dispatches only `learnings-research`, and only on a broad search.** It never scouts the codebase: its whole subject is what reading the code cannot recover, so a repo scan answers a question it is not asking.

**`en-setup` dispatches nothing.** It writes files from templates and probes for their presence; it never scans a codebase and never reads learnings. Its row exists to answer the question, not to route anything.

**`en-debug` dispatches only `repo-research`, and only as a fallback** when its span-to-source mapping cannot anchor a hypothesis. It reads no learnings: a telemetry hypothesis is anchored in the log line in front of it, not in prior write-ups. It carries this file for the dossier protocol its one scout follows.

**`en-foundation` dispatches only `repo-research`.** It reads `docs/learnings/index.md` inline during its orient step, for the same reason `en-brainstorm` does: a scout costs a dispatch round-trip to summarise a file the skill can just read.

**`en-brainstorm` dispatches no scouts.** It reads `docs/learnings/index.md` and the foundation section-index inline (its bounded existing-context scan) rather than spawning `repo-research` or `learnings-research`. A scout would return a gist for less context, but it costs a dispatch round-trip in a skill whose entire cost profile is round-trips. Its only dispatches are `web-research`, on request, and `repo-fact-lookup`, a retrieval agent that answers the specific questions the frontier rounds raise and verifies the design doc's absence-claims. That is not a scout: it is given the question, never the topic.

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

User accepts → `/en-learn capture --from-conversation` files it. Where it lands is `/en-learn`'s routing call — a term, a decision, or a solution — and the source URL is recorded with it.
