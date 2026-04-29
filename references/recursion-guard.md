# Recursion guard

How Ensemble prevents peer-review subprocesses from recursively spawning peer reviews.

## The problem

`en-build` per unit invokes the peer agent. The peer agent, if it loaded the same skills, could itself trigger an `en-review` or `en-cross-review` that fires another peer subprocess. Without a guard, this nests indefinitely.

## The mechanism

A single env var: `ENSEMBLE_PEER_REVIEW`.

- The host sets `ENSEMBLE_PEER_REVIEW=true` in the subprocess environment **before** invoking the peer CLI.
- Every cross-review entry point checks this var **first**, before doing any work.
- If `true`, the entry point logs a one-line note and returns immediately (no findings, no error).

## Where the check lives

Every skill that can invoke cross-review begins with:

```bash
if [ "${ENSEMBLE_PEER_REVIEW:-false}" = "true" ]; then
  echo "Recursion guard active (ENSEMBLE_PEER_REVIEW=true). Skipping cross-review for this invocation." >&2
  # Continue with the rest of the skill, but skip the peer call.
fi
```

Specifically:

- `en-cross-review` — exits early with `verdict: skipped`.
- `en-foundation` — proceeds without the Outside Voice pass.
- `en-plan` — proceeds without the Outside Voice pass.
- `en-build` — proceeds without per-unit peer review.
- `en-review` — proceeds without `--peer` (even if requested).

## What stays enabled inside the peer subprocess

Reviewer agents (the persona reviewers in `en-review`) are not gated by this var because they're agents-within-the-host, not subprocess CLI calls. The guard is specifically about **subprocess** peer review.

The peer subprocess can still:

- Read files
- Run analysis
- Return findings JSON

It just can't fire another `claude -p` / `codex exec` peer call.

## Setting the var correctly

Inline in bash:

```bash
ENSEMBLE_PEER_REVIEW=true \
  $PEER_CMD $PEER_FORMAT --max-turns 1 "$prompt"
```

Or via `env`:

```bash
env ENSEMBLE_PEER_REVIEW=true $PEER_CMD $PEER_FORMAT --max-turns 1 "$prompt"
```

The host must **not** set the var globally (e.g., in `~/.zshrc`) — that would disable cross-review for normal use.

## Defense-in-depth

This guard is one of several. The full picture:

1. **`ENSEMBLE_PEER_REVIEW` env var** — primary recursion guard. This file.
2. **`peer_mode_override: "off"`** in `~/.ensemble/config.json` — global kill switch.
3. **`--no-peer` / `--no-peer-per-unit` flags** — per-invocation opt-out.
4. **`peer_timeout_seconds`** — bounded wall-clock cost per peer call.
5. **One-round rule** — the host doesn't re-invoke the peer after applying findings (per A5).

If any one of these is missing or fails, the others catch the loop.
