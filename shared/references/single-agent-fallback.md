# Single-agent fallback (D31)

What happens when a user has only one CLI installed (only Claude Code or only Codex) and Ensemble still wants to run cross-review.

## The pattern

Same model, **fresh context**. The host shells out to its own CLI in a clean subprocess (e.g., `claude -p` from within Claude Code, `codex exec` from within Codex). The fresh subprocess hasn't seen the implementing session's reasoning, hasn't rationalized away anything, and has no context budget pressure on the artifact.

Superpowers' subagent-driven-development pattern relies on exactly this property: **a fresh instance of the same model catches what the implementing instance has rationalized away.** The model is the same; the cognitive context is not.

## Detection

Set during host detection (see `references/host-detect.md`):

- Both CLIs present → `PEER_MODE=cross-agent`. This is the preferred path.
- Only host's CLI present → `PEER_MODE=single-agent-fallback`. Fall through to a fresh subprocess of the host CLI.
- `peer_mode_override: cross-agent-only` and only host's CLI present → `PEER_MODE=off`, skip cross-review with a note.
- `peer_mode_override: off` → `PEER_MODE=off`, skip everywhere.

## The contract still holds

D30 ("peer reports, host applies") applies to single-agent fallback exactly as it applies to cross-agent mode. The peer subprocess does **not** edit files, run commands, or commit. It returns structured JSON.

The `peer_mode` field in the JSON response carries `"single-agent-fallback"` so the user always knows which mode they're in.

## Prompt augmentation

The Outside Voice template (in `references/outside-voice.md`) includes a conditional block that fires only when `PEER_MODE=single-agent-fallback`:

```text
NOTE: SINGLE-AGENT FALLBACK MODE.
You are a fresh instance of the same model that wrote this artifact. The user does not
have a second CLI installed, so you are filling the cross-review role with a clean
context. Be more aggressive than usual: bias toward finding problems, assume the
implementing instance was tired and may have rationalized issues away. The fresh-context
advantage is what makes this useful — surface what a second pair of eyes would catch
even if the model is the same.
```

This framing combats same-model systematic bias. The fresh instance still has the same blind spots, but the augmented prompt nudges it to be more aggressive about surfacing rather than rationalizing.

## What the user sees

In progress reports:

> Peer review: **single-agent-fallback** (fresh `claude -p` subprocess). 2 findings (1 P1, 1 P2). [details below]

When the user reads this, they know:

1. Cross-review fired.
2. The peer was a same-model fresh subprocess, not a different model.
3. Findings are real but may have systematic-bias gaps that a different model would catch.

## Setup-script behavior

`./setup` runs host detection on first install. If only one CLI is present, the script prints:

> "Only $HOST CLI detected. Ensemble will run cross-review as single-agent fallback (fresh instance of $HOST). For full cross-agent peer review, install the other CLI: <install instructions>. To silence this warning, set `peer_mode_override: \"single-agent-only\"` in `~/.ensemble/config.json`."

The script doesn't block on this — Ensemble works with one CLI. The warning surfaces the value of installing both.

## When NOT to use single-agent fallback

For genuinely high-stakes artifacts (a security-critical decision, a deployment that touches production, a major architectural pivot), the user might want `peer_mode_override: cross-agent-only` so the skill *fails* rather than silently falling back to same-model review. Documented in `~/.ensemble/config.json` as an opt-in.

## Cost

Single-agent fallback costs ~the same as cross-agent in API spend (one peer call per artifact). Latency is similar; the primary difference is *quality* of the findings — different-model perspective is genuinely more valuable than same-model fresh context, but fresh context still beats no review.
