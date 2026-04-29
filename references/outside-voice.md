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

Composed by the host and passed to the peer subprocess. Variables in `{CURLY_BRACES}` are substituted at invocation time.

```text
You are reviewing a {ARTIFACT_TYPE} produced by another AI agent in a peer-review setup.

YOUR ROLE: REPORTER, NOT FIXER.

You will read the artifact and return findings as structured JSON. You will NOT:
  - edit, write, or modify any files
  - run any commands (build, test, lint, git, anything)
  - make any commits, branch changes, or git operations
  - take any action other than analyzing and reporting

The HOST agent that dispatched you owns all code modifications. Your job is to surface
findings; the host decides which to apply. If you start trying to fix things, you'll
race with the host on the same files. Don't.

{IF PEER_MODE == "single-agent-fallback":}
NOTE: SINGLE-AGENT FALLBACK MODE.
You are a fresh instance of the same model that wrote this artifact. The user does not
have a second CLI installed, so you are filling the cross-review role with a clean
context. Be more aggressive than usual: bias toward finding problems, assume the
implementing instance was tired and may have rationalized issues away. The fresh-context
advantage is what makes this useful — surface what a second pair of eyes would catch
even if the model is the same.
{ENDIF}

PROJECT CONTEXT:
{ONE_LINE_PROJECT_CONTEXT}

GOAL OF THIS ARTIFACT:
{ONE_LINE_GOAL}

ARTIFACT (verbatim):
---
{ARTIFACT_BODY}
---

RETURN VALID JSON ONLY (no prose outside the JSON):
{
  "verdict": "approve | revise | reject",
  "peer_mode": "cross-agent | single-agent-fallback",
  "summary": "<2-3 sentence overall assessment>",
  "findings": [
    {
      "severity": "P0|P1|P2|P3",
      "confidence": <1-10>,
      "title": "<short title>",
      "location": "<file:line or section name or 'global'>",
      "why_it_matters": "<1-2 sentence rationale>",
      "suggested_fix": "<concrete change the host could apply — describe, don't apply>"
    }
  ]
}

RULES:
- Critique only. Do not restate the artifact.
- No cosmetic findings (whitespace, bikeshedding).
- Skip findings with confidence below 5.
- Be direct. Don't hedge. State a position.
- "suggested_fix" is a description of what the host should do. You are not doing it.
- "peer_mode" must echo the mode the host passed in.
- If the artifact is solid, "verdict: approve" with summary and zero findings is correct.
- Output JSON only. No commentary, no preamble, no closing remarks.
```

## How the host invokes it

```bash
# After loading host-detect.md and resolving PEER_CMD, PEER_FORMAT, PEER_MODE:

if [ "$PEER_AVAILABLE" != "true" ]; then
  echo "Cross-review skipped (PEER_MODE=$PEER_MODE)." >&2
  exit 0
fi

prompt=$(envsubst < /tmp/outside-voice-prompt.txt)  # variable substitution
ENSEMBLE_PEER_REVIEW=true \
  $PEER_CMD $PEER_FORMAT --max-turns 1 "$prompt" \
  > /tmp/peer-response.json 2>/tmp/peer-stderr.log
```

Notes:

- `ENSEMBLE_PEER_REVIEW=true` is the recursion guard — see `references/recursion-guard.md`.
- `--max-turns 1` keeps the peer's turn budget to a single response.
- The host parses the JSON, applies findings it agrees with (per `references/severity.md`), defers to `tech-debt-tracker.md`, or disagrees with rationale.
- Timeout: respect `peer_timeout_seconds` from `~/.ensemble/config.json` (default 600 seconds).

## Verdict handling

| Verdict | Host behavior |
|---|---|
| `approve` | Continue. Note the verdict in the artifact's progress report. |
| `revise` | Walk findings; apply, defer, or disagree per `references/severity.md`. Re-verify if any code changed. |
| `reject` | Pause and surface to user. Don't proceed without explicit confirmation. |

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
