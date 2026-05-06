# Outside Voice — cross-agent peer review

Single source of truth for invoking the peer agent. Loaded by every skill that runs a peer pass: `en-foundation`, `en-plan`, `en-build` (per unit), `en-cross-review`, optional `--peer` on `en-review` and others.

## The contract (D30)

**Peer reports, host applies.** The peer agent **only returns structured findings**. It does **not** edit files, run commands, modify state, or make commits. The host (the agent running the skill) is the sole code-modifier.

This is non-negotiable. If a peer process starts editing files, it races with the host on the same paths. The Outside Voice prompt (below) tells the peer this explicitly. The host validates the peer's output as JSON and ignores any non-JSON content.

## When the peer fires

| Skill | When | Mode |
|---|---|---|
| `en-foundation` | After draft is synthesized | On by default; `--no-peer` disables |
| `en-plan` | After plan is fully drafted with U-IDs | On by default |
| `en-build` | Per unit, after `code-simplifier` and verification gates | On per unit; `--no-peer-per-unit` disables |
| `en-cross-review` | The whole skill is the peer call | Always |
| `en-review` | Optional, on top of personas | Off by default; `--peer` enables |

## Single-agent fallback (D31)

If only one CLI is installed, the peer is a fresh subprocess of the **host's own CLI**. Same model, fresh context. Still useful — Superpowers' subagent-driven-development pattern relies on exactly this property: the implementing instance has rationalized things away that a fresh instance will not.

When `PEER_MODE=single-agent-fallback`, the prompt is augmented with explicit "be more aggressive, bias toward finding problems" framing (see template below).

The peer's JSON response carries `peer_mode: "cross-agent" | "single-agent-fallback"` so the user always knows which mode they're in.

## The Outside Voice prompt template

Composed by the host and passed to the peer subprocess. The placeholders below use **shell-style `$VAR` syntax** so they round-trip cleanly through the helper's HEREDOC (`bin/ensemble-build-peer-prompt`) AND through `envsubst` if a caller wants to template the file directly. The helper is the canonical path because it also handles the conditional blocks (single-agent fallback note, plan-specific review dimensions); raw `envsubst` would require the caller to set those conditionals manually.

```text
Peer review of a $ARTIFACT_TYPE. You are the REPORTER, not the fixer:
read the artifact, return structured JSON findings only. Do NOT edit files,
run commands, make commits, or take any action. The host applies findings.
$SINGLE_AGENT_NOTE

PROJECT: $PROJECT_CONTEXT
GOAL: $GOAL
$PLAN_REVIEW_DIMENSIONS
ARTIFACT:
---
$ARTIFACT_BODY
---

Return JSON conforming to references/finding-schema.md. Required keys:
verdict ("approve"|"revise"|"reject"), peer_mode (echo "$PEER_MODE"),
summary (2-3 sentences), findings[]. Each finding: severity (P0-P3),
confidence (1-10), title, location, why_it_matters, suggested_fix
(describe the change, don't apply it); finding_id optional.

Rules:
- Critique only; suppress confidence<5 unless severity P0.
- Output JSON only — no prose outside the JSON object.
- For iteration > 1, honor "## Previous review context" — don't re-flag
  applied/deferred/disagreed findings unless you have new evidence.
- "verdict: approve" with empty findings[] is correct when the artifact
  is solid.
```

### Variable contract

These shell variables are what `bin/ensemble-build-peer-prompt` populates inside its HEREDOC; they're also what `envsubst` would read if a caller wanted to template the file directly:

| Variable | Source | Required |
|---|---|---|
| `$ARTIFACT_TYPE` | `code` / `plan` / `markdown artifact` / `mixed` | yes |
| `$PROJECT_CONTEXT` | First paragraph of `AGENTS.md` or foundation §1 | yes |
| `$GOAL` | One-line goal: commit subject for diffs; user's stated reason for files | yes |
| `$ARTIFACT_BODY` | The artifact under review, verbatim | yes |
| `$PEER_MODE` | `cross-agent` or `single-agent-fallback` | yes |
| `$SINGLE_AGENT_NOTE` | Empty in cross-agent mode. In `single-agent-fallback`: `(Single-agent fallback: you're a fresh instance of the same model that wrote this. Be aggressive — bias toward finding problems the original instance rationalized away.)` | conditional |
| `$PLAN_REVIEW_DIMENSIONS` | Empty for non-plan artifacts. For plans: `Plan review dimensions: cross-check risk: against each unit's approach (DROP/TRUNCATE/mass-DELETE → destructive; backfills over large row counts → high; admin endpoints / feature-flag flips → gated:true). Flag dependency-vs-phase violations (low-risk depending on higher-risk). Misclassified destructive units are P0/P1.` | conditional |

The helper sets the conditional variables based on flag inputs (`--peer-mode`, `--artifact-type`); raw envsubst callers must set them themselves before substituting.

## How the host invokes it

**Skills should not assemble this prompt by reasoning** — that's slow and
error-prone. **And skills must NEVER capture the helper's output into a
shell variable and re-pass it via `argv`** — that hits `ARG_MAX` on large
artifacts (per-unit diffs, full plans) and produces silent hangs in the
peer subprocess. The canonical pattern pipes the helper's stdout directly
into the peer over stdin, runs the peer in `--bare` minimal mode, and
wraps the call in `timeout` for hang protection.

```bash
# After loading host-detect.md and resolving PEER_CMD, PEER_FORMAT, PEER_MODE:

if [ "$PEER_AVAILABLE" != "true" ]; then
  echo "Cross-review skipped (PEER_MODE=$PEER_MODE)." >&2
  exit 0
fi

# Pipe helper-stdout → peer-stdin. NO argv-inlining of the prompt.
# - --bare strips MCP, hooks, LSP, plugin sync, CLAUDE.md auto-discovery,
#   keychain reads — common silent-hang causes for non-interactive peer subprocs.
# - timeout enforces peer_timeout_seconds (default 600) so a hang fails fast.
# - stderr is captured for diagnostic visibility on failure.
ENSEMBLE_PEER_REVIEW=true bin/ensemble-build-peer-prompt \
  --artifact-type plan \
  --project-context "$ONE_LINE_PROJECT_CONTEXT" \
  --goal "$ONE_LINE_GOAL" \
  --artifact-file docs/plans/active/EN07-feature_auth-rotation.md \
  --peer-mode "$PEER_MODE" \
  | timeout "${peer_timeout_seconds:-600}" \
      $PEER_CMD --bare $PEER_FORMAT --max-turns 1 \
      > /tmp/peer-response.json \
      2>/tmp/peer-stderr.log
```

> **Note on `--bare`:** This is the Claude CLI flag. The Codex CLI has its
> own equivalent (`codex exec --skip-init` / similar — verify against the
> installed version). Skills resolve `$PEER_CMD` via host-detect; if the
> resolved peer doesn't support a `--bare`-equivalent, omit the flag and
> rely on `timeout` + stderr capture as the floor. Hang protection from
> `timeout` is universal.

For re-review iterations (the `/en-plan` finalize loop or `/en-build`'s
per-unit finalize loop), build the "## Previous review context" section
into a tempfile and pass `--iteration-context-file <path>`. The helper
inserts it between the artifact body and the JSON-shape instructions;
see `bin/ensemble-build-peer-prompt --help` for full args.

### Anti-pattern (do not use)

```bash
# WRONG — produced the silent-hang failure mode in the field:
prompt=$(bin/ensemble-build-peer-prompt ...)
$PEER_CMD $PEER_FORMAT --max-turns 1 "$prompt"   # argv-inlined large prompt
```

The helper writes the slim template to **stdout** by design. Capturing
back into a variable and re-passing via argv defeats that design and
hits the failure modes the canonical pattern was built to avoid.

Notes:

- `ENSEMBLE_PEER_REVIEW=true` is the recursion guard — see `references/recursion-guard.md`.
- `--max-turns 1` keeps the peer's turn budget to a single response.
- The host parses the JSON, applies findings it agrees with (per `references/severity.md`), defers to `tech-debt-tracker.md`, or disagrees with rationale.
- Timeout: respect `peer_timeout_seconds` from `~/.ensemble/config.json` (default 600 seconds).

## Re-review iterations (`/en-plan` finalize loop)

When `/en-plan` re-runs the peer pass after applying findings (per the
finalize-loop spec — depth-aware iteration cap: lightweight=1, standard=2,
deep=2), the prompt prepends a `## Previous review context` section:

```text
## Previous review context (iteration {N})

This is iteration {N+1} of finalization. Verify previously-applied findings
actually resolve the concern, and surface only NEW issues or unresolved-from-
previous. Do not re-litigate findings listed below unless you have new
evidence.

### Applied (peer should verify the fix landed):
- [{finding_id}] {title} — {applied_summary}

### Deferred (do NOT re-flag):
- [{finding_id}] {title} — Rationale: {rationale}

### Disagreed-with (do NOT re-flag unless new evidence):
- [{finding_id}] {title} — Rationale: {rationale}
```

The host assembles this section from the plan's `peer_review_resolutions:`
frontmatter — never from the human-readable iteration log.

## Verdict handling

| Verdict | Host behavior |
|---|---|
| `approve` | Continue. On `/en-plan` finalize: write `peer_review_plan_hash`, flip `status: draft → open`, auto-commit the plan file (per finalize-loop spec). |
| `revise` | Walk findings; apply, defer, or disagree per `references/severity.md`. Write structured entries to `peer_review_resolutions:`. Re-verify if any code changed. **`/en-plan` re-runs the peer pass automatically (subject to depth-aware iteration cap)** unless `--no-reloop` was passed. |
| `reject` | Pause and surface to user. Don't proceed without explicit confirmation. Status stays `draft`. |

## Failure handling

- **Peer subprocess timeout** → log to stderr, mark cross-review skipped for this artifact, continue. Do not block on peer failures.
- **Malformed JSON** → ask the peer to retry once with the same prompt + a "your previous response was not valid JSON; return only JSON" suffix. If it fails again, log and skip.
- **Empty findings + verdict approve** → the artifact is clean from the peer's perspective. Surface "Peer review: clean" in the progress report and continue.

## Cost controls

| Lever | Default | Override |
|---|---|---|
| Mid-tier model for peer | yes | `peer_model_codex` / `peer_model_claude` in `~/.ensemble/config.json` |
| Skip on small artifacts | <50 lines | `skip_peer_below_lines` |
| Skip on Lightweight depth | yes | `skip_peer_on_lightweight: false` |
| One round only | yes | not configurable in v1 |
