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
| `$PLAN_REVIEW_DIMENSIONS` | Empty for non-plan artifacts. For plans: `Plan review dimensions: (1) cross-check risk: against each unit's approach (DROP/TRUNCATE/mass-DELETE → destructive; backfills over large row counts → high). Misclassified destructive units are P0/P1. (2) Flag dependency-vs-phase violations (low-risk depending on higher-risk). (3) Challenge gated:true choices — gated is for production-state-changing units only (customer-facing flag flips, production backfills, real-side-effect 3rd-party APIs, API contract breaks, production config changes). Flag any gated:true unit whose approach is just an internal/UI rename, refactor, test addition, or new code behind an off flag — over-gating trains users to autopilot through prompts and erodes signal value. Equally flag missing gated:true on units that DO change production state (e.g. an admin endpoint flag flip with gated:false).` | conditional |

The helper sets the conditional variables based on flag inputs (`--peer-mode`, `--artifact-type`); raw envsubst callers must set them themselves before substituting.

## How the host invokes it

**Skills should not assemble this prompt by reasoning** — that's slow and
error-prone. **And skills must NEVER capture the helper's output into a
shell variable and re-pass it via `argv`** — that hits `ARG_MAX` on large
artifacts (per-unit diffs, full plans) and produces silent hangs in the
peer subprocess. The canonical pattern pipes the helper's stdout directly
into the peer over stdin and wraps the call in `timeout` for hang
protection.

**Auth contract: Ensemble peer review uses the host user's Claude
subscription (OAuth / claude.ai / keychain).** This is a deliberate
product decision: peer review piggy-backs on the existing subscription
instead of requiring API credit. Therefore Ensemble does NOT use Claude's
`--bare` flag, even though `--bare` would suppress more startup work —
because `--bare` reads only `ANTHROPIC_API_KEY` / `apiKeyHelper` and
explicitly skips OAuth and keychain. On a subscription-only host, `--bare`
fails with `Not logged in · Please run /login`. We trade some startup
overhead for working subscription auth, then bound the cost with
`timeout`.

```bash
# After loading host-detect.md and resolving PEER_CMD, PEER_FORMAT, PEER_MODE:

if [ "$PEER_AVAILABLE" != "true" ]; then
  echo "Cross-review skipped (PEER_MODE=$PEER_MODE)." >&2
  exit 0
fi

# Resolve a timeout binary (BSD macOS doesn't ship one; coreutils provides
# gtimeout via Homebrew). Fail fast if neither is present rather than
# silently dropping the wrapper — that re-enables the silent-hang failure
# mode that prompted PR #9.
ENSEMBLE_TIMEOUT_BIN=$(command -v timeout || command -v gtimeout) || {
  echo "ERROR: peer review requires 'timeout' or 'gtimeout' on PATH" >&2
  echo "  Install on macOS: brew install coreutils" >&2
  echo "  This guards against silent peer-subprocess hangs (per PR #9)." >&2
  exit 1
}

# Pipe helper-stdout → peer-stdin. NO argv-inlining of the prompt.
# Isolation flags below skip MCP, skills, session persistence, and
# project/local settings — every suppression we can do that DOESN'T
# require API-key auth (i.e. doesn't use --bare).
# - timeout enforces peer_timeout_seconds (default 600) so a hang fails fast.
# - stderr is captured for diagnostic visibility on failure.
ENSEMBLE_PEER_REVIEW=true $SKILL_DIR/scripts/ensemble-build-peer-prompt \
  --artifact-type plan \
  --project-context "$ONE_LINE_PROJECT_CONTEXT" \
  --goal "$ONE_LINE_GOAL" \
  --artifact-file docs/plans/active/EN07-feature_auth-rotation.md \
  --peer-mode "$PEER_MODE" \
  | "$ENSEMBLE_TIMEOUT_BIN" "${peer_timeout_seconds:-600}" \
      $PEER_CMD $PEER_FORMAT $PEER_TURNS "${CLAUDE_ISOLATION[@]}" \
      > /tmp/peer-response.json \
      2>/tmp/peer-stderr.log
```

**The isolation flags are Claude-CLI-only and must be applied conditionally (EN10).** `--strict-mcp-config`, `--mcp-config`, `--disable-slash-commands`, `--no-session-persistence`, `--setting-sources`, and `--tools ''` are **Claude flags**; passing them to `codex exec` errors on argument parsing. Resolve them per peer as a bash array (an array is required because `--tools ''` is an empty argument that cannot survive unquoted string-splitting):

```bash
if [ "$PEER_CMD" = "claude -p" ]; then
  CLAUDE_ISOLATION=(--strict-mcp-config --mcp-config '{"mcpServers":{}}' \
    --disable-slash-commands --no-session-persistence --setting-sources project --tools '')
else
  CLAUDE_ISOLATION=()   # codex exec is already lightweight + single-shot; no hardening flags
fi
```

> **Required on PATH:** `timeout` or `gtimeout` (GNU coreutils). macOS: `brew install coreutils`. Linux distros typically ship coreutils by default. Without it, peer review fails fast with a clear install instruction — never runs unwrapped.

> **Why this set of flags (not `--bare`):**
> - `--bare` is the strongest startup suppressor — but it forces
>   `ANTHROPIC_API_KEY` / `apiKeyHelper` auth and bypasses OAuth/keychain
>   entirely. Ensemble's contract is subscription-first; `--bare` breaks
>   that. **Do not use `--bare`** in any peer-review code path.
> - `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` — skip MCP
>   server loading. The inline JSON must include the `mcpServers` key:
>   an empty `{}` fails Claude's MCP-config schema validation.
> - `--disable-slash-commands` — skip skill / slash-command loading.
> - `--no-session-persistence` — don't write session state (works only
>   with `--print`; we always use `-p`, so safe).
> - `--setting-sources project` — load project-level settings only; skip
>   user-level config which typically carries the LSP plugin and other
>   globally-enabled tools. Field-observed: `--setting-sources user`
>   loaded the LSP and triggered a tool call that consumed `--max-turns 1`
>   before producing JSON output.
> - `--tools ''` — **load-bearing.** Disable ALL built-in tools (Bash,
>   Edit, Read, etc.) for the peer subprocess. Physically prevents the
>   model from making tool calls regardless of which settings load,
>   guaranteeing `--max-turns 1` is reliably one model response. Also
>   the strongest mechanical enforcement of D30 (peer reports, never
>   acts).
> - Hooks, LSP load, plugin sync, CLAUDE.md auto-discovery still happen
>   at startup, but cannot fire tool calls (because `--tools ''`).
>   Bounded by `timeout`.
> - **`timeout` portability**: macOS doesn't ship `timeout` in `/usr/bin/`.
>   Resolve with `command -v timeout || command -v gtimeout` (the latter
>   is what `brew install coreutils` provides). The canonical invocation
>   **fails fast (`exit 1`) if neither is present** — running peer
>   review without hang protection re-enables the silent-hang failure
>   mode that prompted PR #9. macOS users without coreutils get a clear
>   install instruction, not a silently-degraded peer call.

> **Cross-host note:** This flag set is for the Claude CLI. The Codex CLI
> has its own minimization flags — skills resolve `$PEER_CMD` via
> host-detect and adapt. If the resolved peer doesn't support a flag
> here, omit it and rely on `timeout` + stderr capture as the floor.

> **Auth preflight (recommended).** On the first peer dispatch in a
> session, run `claude auth status` and fail loudly if `loggedIn != true`.
> Cheaper than seeing every per-unit peer call fail with `Please run
> /login`. Cache via the host-detect session cache so it doesn't re-fire.

For re-review iterations (the `/en-plan` finalize loop or `/en-build`'s
per-unit finalize loop), build the "## Previous review context" section
into a tempfile and pass `--iteration-context-file <path>`. The helper
inserts it between the artifact body and the JSON-shape instructions;
see `bin/ensemble-build-peer-prompt --help` for full args.

### Anti-patterns (do not use)

```bash
# WRONG — argv-inlined large prompt, produced the silent-hang failure
# mode in the field:
prompt=$(bin/ensemble-build-peer-prompt ...)
$PEER_CMD $PEER_FORMAT $PEER_TURNS "$prompt"

# WRONG — --bare bypasses subscription auth; fails with
# "Not logged in · Please run /login" on hosts without a valid
# ANTHROPIC_API_KEY (the common case for Ensemble users):
... | claude --bare -p ...

# WRONG — bare `timeout` fails on macOS-without-coreutils with
# "timeout: command not found" before Claude is invoked. Use the
# resolved `$ENSEMBLE_TIMEOUT_BIN` variable from the canonical pattern,
# which falls back to `gtimeout` and fails fast with an install
# instruction if neither is present:
... | timeout 600 claude -p ...

# WRONG — dropping the timeout wrapper "to make it work" silently
# re-enables the silent-hang failure mode that prompted PR #9.
# A peer call without an upper bound is the original bug, not a workaround:
... | claude -p ...
```

The helper writes the slim template to **stdout** by design. Capturing
back into a variable and re-passing via argv defeats that design and
hits the failure modes the canonical pattern was built to avoid.
`--bare` would be tempting for startup speed, but it breaks Ensemble's
subscription-first auth contract. Bare `timeout` and dropped-`timeout`
both regress the hang-protection contract — fail fast on missing
binary, never run unwrapped.

Notes:

- `ENSEMBLE_PEER_REVIEW=true` is the recursion guard — see `references/recursion-guard.md`.
- `$PEER_TURNS` keeps the peer's turn budget to a single response: `--max-turns 1` for a `claude -p` peer; empty for `codex exec`, which is single-shot (it removed `--max-turns`).
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
