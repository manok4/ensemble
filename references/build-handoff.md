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
│    5. Dispatch Claude as PEER-REVIEWER (pipe stdin, --bare,        │
│       wrapped in timeout):                                         │
│         bin/ensemble-build-peer-prompt ... | \                    │
│           timeout "${peer_timeout_seconds:-600}" \                 │
│             claude --bare -p --output-format json --max-turns 1   │
│         (env: ENSEMBLE_PEER_REVIEW=true; stderr captured to log)   │
│    6. Claude returns findings JSON (does NOT edit files — D30).    │
│    7. Codex parses JSON; apply / defer / disagree per             │
│       references/severity.md. Build a `resolutions[]` list as it   │
│       walks each finding (one entry per finding, with status).     │
│    8. Re-verify if any code changed.                               │
│    9. **Per-unit finalize loop.** Counter `re_review_count`       │
│       starts at 0; increments after each re-review pass. If        │
│       `verdict: revise` AND ≥1 finding applied AND                 │
│       `re_review_count < --max-per-unit-iterations` (default 1)   │
│       → re-invoke peer with `--iteration-context-file` carrying   │
│       the resolutions[] list, increment counter. Loop back to     │
│       step 6. On `approve` or cap exhaustion, continue. With      │
│       default cap=1, exactly one re-review fires when the         │
│       initial pass returned revise+applied findings.               │
│   10. Commit (conventional message + U-ID + `phase: P<N>` trailer │
│       + one `peer-resolution:` trailer per finding).               │
└────────────────────────────────────────────────────────────────────┘
```

## Peer-reviewer dispatch prompt

Use `bin/ensemble-build-peer-prompt` to assemble the Outside Voice prompt — do NOT build it by reasoning. The helper emits the slim template to **stdout** (single-agent fallback note + plan-specific dimensions are substituted automatically based on the flags you pass). The canonical invocation pipes that stdout directly into `claude` over stdin — never via `argv`.

### Canonical invocation (build-handoff)

```bash
# 1. Build a tempfile containing the post-simplifier diff + the unit's plan section
cat > /tmp/en-build-unit-artifact.txt <<EOF
=== Unit: $U_ID — $UNIT_GOAL ===

== Unit specification (from plan) ==
$UNIT_BLOCK

== Post-simplifier diff ==
$POST_SIMPLIFIER_DIFF
EOF

# 2. Pipe helper-stdout → claude-stdin. No argv-inlining of the prompt.
#    --bare strips MCP loading, hooks, LSP, plugin sync, CLAUDE.md auto-discovery,
#    keychain reads — everything that can stall a peer subprocess on startup.
#    timeout enforces peer_timeout_seconds (default 600) so a hang fails fast
#    instead of stalling the build forever.
#    stderr is captured for diagnostic visibility on failure.
ENSEMBLE_PEER_REVIEW=true bin/ensemble-build-peer-prompt \
  --artifact-type code \
  --project-context "$ONE_LINE_PROJECT_CONTEXT" \
  --goal "Review unit $U_ID: $UNIT_GOAL" \
  --artifact-file /tmp/en-build-unit-artifact.txt \
  --peer-mode "$PEER_MODE" \
  | timeout "${peer_timeout_seconds:-600}" \
      claude --bare -p --output-format json --max-turns 1 \
      > /tmp/en-build-peer-response.json \
      2>/tmp/en-build-peer-stderr.log
```

For re-review iterations (see **Per-unit finalize loop** below), pass `--iteration-context-file <path>` with a serialized resolutions[] context — the helper inserts it between the artifact body and the JSON-shape instructions.

### Why this exact shape (not `prompt=$(...) ; claude -p "$prompt"`)

- **Pipe over argv.** Capturing the helper's stdout into a shell variable and re-passing as argv hits `ARG_MAX` and stalls some CLI argument-parsing paths — observed silent hangs in the field. Stdin avoids the entire class. The Claude CLI's `-p` description explicitly calls out: *"useful for pipes."*
- **`--bare` flag.** *Per `claude --help`:* "Minimal mode: skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery." That list IS the menu of common silent-hang causes for one-shot peer subprocesses. Sets `CLAUDE_CODE_SIMPLE=1`. Skills still resolve via `/skill-name` if the prompt references them.
- **`timeout` wrapper.** Without it, a hung peer blocks the build indefinitely. `peer_timeout_seconds` from `~/.ensemble/config.json` is the configured ceiling; the wrapper enforces it.
- **stderr capture.** When a peer fails, the user needs `/tmp/en-build-peer-stderr.log` to diagnose (was it MCP init? auth? timeout?). The default of swallowing stderr makes hangs invisible.

The Outside Voice prompt explicitly forbids file edits, commands, and commits (D30). The peer returns JSON-only findings (read from `/tmp/en-build-peer-response.json`).

## Per-unit finalize loop (`--max-per-unit-iterations`, default 1)

Same shape as `/en-plan`'s plan-level finalize loop, scoped to a single unit. When the per-unit peer returns `verdict: revise` and the host applies one or more findings, the implementation has changed since the peer reviewed it — those fixes haven't been verified. The loop runs the peer once more on the post-fix state.

**Counter semantics.** `re_review_count` starts at **0** and increments by 1 after each re-review pass. The initial peer pass at step 5 does NOT count toward it. With default cap=1, this guarantees **exactly one re-review pass** whenever the initial pass returned `revise` with applied findings — the post-fix diff is always peer-verified at default settings. (If the cap were checked against total iterations starting at 1, default cap=1 would never fire — that's the bug this counter avoids.)

Behavior:

| Verdict | Condition | Action |
|---|---|---|
| `approve` | any | Exit loop. Proceed to commit (step 10). The applied findings (if any) have been peer-verified. |
| `revise` | ≥1 finding applied AND `re_review_count < cap` | Build `peer_review_resolutions[]` (schema below), serialize into a `## Previous review context` tempfile, re-invoke peer with `--iteration-context-file`. Increment `re_review_count` after the re-review returns. |
| `revise` | cap reached AND ≥1 finding applied on the cap-hitting pass | Exit loop. **Surface a P1 warning** in the unit summary: those last applications were verified by lint+tests at step 8 but NOT by another peer pass. User can raise `--max-per-unit-iterations` if this recurs. Commit with current resolutions. |
| `revise` | cap reached AND all findings on the cap-hitting pass deferred/disagreed | Exit loop without warning. Commit with current resolutions. |
| `revise` | no findings applied (all deferred or disagreed) | Exit loop — re-running peer wouldn't see different code. Commit with current resolutions. |
| `reject` | any | Pause and surface to user. Don't loop. |

**Cap rationale.** Per-unit findings tend to be mechanical fixes that converge fast. Default `--max-per-unit-iterations: 1` means one re-review max (so total of 2 peer passes per unit max: initial + 1 re-review). Override with `--max-per-unit-iterations <N>` on `/en-build`. Set to `0` to disable per-unit looping entirely (revert to single-pass, pre-PR behavior).

**Iteration prompt context.** The "Previous review context" section is assembled from the unit's `peer_review_resolutions[]` list — same format as `/en-plan`'s plan-level loop:

```text
## Previous review context (iteration {N})

This is iteration {N+1} of the per-unit review for U{ID}. Verify previously-
applied findings actually resolve the concern; surface only NEW issues or
unresolved-from-previous. Do not re-litigate findings listed below unless
you have new evidence.

### Applied (peer should verify the fix landed):
- [{finding_id}] {title} — {applied_summary}

### Deferred (do NOT re-flag):
- [{finding_id}] {title} — Rationale: {rationale}

### Disagreed-with (do NOT re-flag unless new evidence):
- [{finding_id}] {title} — Rationale: {rationale}
```

## Resolution log (`peer_review_resolutions[]` per unit)

As Codex walks each finding in step 7, it appends a structured entry to a per-unit `resolutions[]` array. Each entry mirrors the plan-level schema in `references/templates/plan-template.md`, scoped to the unit:

```yaml
- finding_id: <peer-supplied or host-minted as `u<N>-<iteration>-<index>`, e.g. `u3-1-2`>
  u_id: U<N>
  iteration: <integer; iteration of the per-unit loop>
  severity: P0 | P1 | P2 | P3
  title: <short title from peer>
  status: applied | deferred | disagreed | superseded
  rationale: <one-line reason; required for non-applied>
  location: <file:line or section name>
```

This list is held in memory during the unit loop, surfaced in the unit's progress report, and serialized into the commit message as structured trailers (see Commit message format below).

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
Peer review (claude, mode: cross-agent, iterations: <N>):
  - Applied: <count> findings
  - Deferred to tech-debt-tracker.md: <count> findings
  - Disagreed: <count> findings

phase: P<N>
peer-resolution: {"finding_id":"u3-1-1","u_id":"U3","iteration":1,"severity":"P1","status":"applied","title":"Race in refresh path"}
peer-resolution: {"finding_id":"u3-1-2","u_id":"U3","iteration":1,"severity":"P2","status":"deferred","rationale":"low conf, tracked TD12","title":"Edge case"}
```

**Trailers contract.** Each finding becomes one `peer-resolution:` git-trailer line containing single-line JSON. The JSON conforms to the per-unit resolution schema above (`finding_id`, `u_id`, `iteration`, `severity`, `status`, `title`, `rationale` when applicable). One trailer per finding; the human-readable counts above stay as a quick summary.

Why trailers: `git interpret-trailers --parse` and `git log --grep="^peer-resolution:"` are stable, scriptable, and don't require per-unit metadata files. Reviewers can audit by greppable history; future automation (e.g. `/en-resolve-pr` mining what got deferred) reads trailers cleanly.

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
