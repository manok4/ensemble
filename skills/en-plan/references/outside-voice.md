# Outside Voice — cross-agent peer review

The contract every peer pass follows. Carried by the skills that run one: `en-foundation`, `en-plan`, `en-review`.

## The contract (D30)

**Peer reports, host applies.** The peer agent **only returns structured findings**. It does **not** edit files, run commands, modify state, or make commits. The host (the agent running the skill) is the sole modifier: it validates the peer's output as JSON, ignores anything outside the JSON object, and applies the findings it agrees with. A peer that edits files races the host on the same paths, which is why the peer runs as a tool-less subprocess rather than as a collaborator on the file.

## When the peer fires

| Skill | When | Default |
|---|---|---|
| `en-foundation` | After the draft is synthesized | On; `--no-peer` disables |
| `en-plan` | After the plan is fully drafted with U-IDs | On; `--no-peer` disables |
| `en-build` | Once, over the branch diff after `/en-simplify`, through `/en-review --peer` (D52) | On |
| `en-review` | Alongside the host personas | On; `--no-peer` disables |

## Single-agent fallback (D31)

With one CLI installed, the peer is a fresh subprocess of the host's own CLI: same model, empty context. The prompt builder adds a "be more aggressive, bias toward finding problems the implementing instance rationalized away" note when `--peer-mode single-agent-fallback` is passed, and the response echoes `peer_mode` so the user always knows which mode ran.

## How the host invokes it

Two helpers own the whole path. A skill never assembles the prompt or the command line by reasoning.

1. `$SKILL_DIR/scripts/ensemble-build-peer-prompt --brief references/peer-brief.md --project-context "<one line>" --goal "<one line>" --artifact-file <path> --peer-mode "$PEER_MODE"` writes the prompt to stdout: the reporter framing, this skill's review dimensions from its brief, the artifact verbatim, the inline JSON contract (severity definitions, required keys, `coverage`), and on re-review the `## Previous review context` section from `--iteration-context-file <path>`. `--help` lists every flag.
2. `ensemble_peer_invoke` (sourced from `$SKILL_DIR/scripts/ensemble-peer-invoke`) runs the peer with `ENSEMBLE_PEER_REVIEW=true` set, reading the prompt file on stdin. It owns the `timeout` wrapper (`peer_timeout_seconds`, default 600; `timeout` or `gtimeout` must be on PATH), failure classification (`auth` / `unknown` / `timeout` / flag drift), the single bounded retry, JSON recovery from fenced or prose-wrapped output, and the `peer_decision` object it prints (`references/peer-contract.md`).

**The isolation flags are Claude-CLI-only, and the helper applies them** when the peer command is `claude`: `--strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands --no-session-persistence --setting-sources project --tools ''`. No MCP servers, no skills, no session state, no user-level settings, and no tools, so `--max-turns 1` is reliably one model response and the peer physically cannot act. `codex exec` is single-shot and gets none of them. A CLI that rejects one of these flags costs one retry without the set, reported as `dropped-isolation-fragment`; `ENSEMBLE_PEER_ISOLATION=off` disables the set for a session.

**Not `--bare`.** Ensemble peer review runs on the host user's subscription (OAuth / keychain). `--bare` reads only an API key and fails with "Not logged in" on a subscription-only host, so no peer path uses it.

**Anti-pattern: never** capture the prompt into a shell variable and pass it as an argument: a large artifact hits `ARG_MAX` and the peer hangs silently, which is the failure that produced this file. Stdin, wrapped in `timeout`, always.

## Re-review iterations

When a skill re-runs the peer after applying findings, the prompt carries a `## Previous review context (iteration N)` section listing applied findings (the peer verifies the fix landed), deferred ones (do not re-flag) and disagreed-with ones (do not re-flag without new evidence), each by `finding_id`. The host assembles it from the artifact's structured resolution log (`peer_review_resolutions:` on a plan), never from the human-readable iteration prose. The peer must reuse the original `finding_id` when re-raising a point; a re-minted id defeats the suppression.

## Verdict handling

| Verdict | Host behavior |
|---|---|
| `approve` | Continue. On `/en-plan`: write `peer_review_plan_hash`, flip `status: draft → open`, auto-commit the plan file. |
| `revise` | Walk findings; apply, defer, or disagree per the skill's own peer brief; record each resolution. Re-invoke at most once, and only when the pass produced a `P0` or `P1` (D49). |
| `reject` | Pause and surface to the user. Do not proceed without explicit confirmation. |

## Failure handling

- **Timeout** → the helper reports `peer-failed:timeout`; the skill marks the pass skipped, says so, and continues. Never block on a peer failure.
- **Malformed JSON** → the helper recovers a fenced or prose-wrapped object locally; if nothing parses, retry once with a "return only JSON" suffix, then log and skip.
- **Empty findings with `approve`** → the artifact is clean from the peer's perspective. Say "Peer review: clean" and continue.

Notes:

- `ENSEMBLE_PEER_REVIEW=true` is the recursion guard (`references/recursion-guard.md`).
- `$PEER_TURNS` is `--max-turns 1` for a `claude -p` peer and empty for `codex exec`, which is single-shot.
