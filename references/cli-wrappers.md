# CLI wrappers — `claude -p` and `codex exec`

Single source of truth for CLI flags. Skills consult this file instead of embedding flag strings, so when an upstream CLI changes a flag, **one update propagates everywhere**.

> **Defaults to verify, not promises.** Both ecosystems evolve quickly. The flags below are correct as of 2026-04. The setup script tests them against the installed CLIs and surfaces deprecation warnings if a flag is rejected.

## Claude Code (`claude -p`)

Headless one-shot prompt mode.

| Flag | Purpose | Notes |
|---|---|---|
| `-p <prompt>` or `--prompt <prompt>` | The prompt | Positional after the flag |
| `--output-format json` | Return structured JSON instead of pretty-printed | Required for parseable peer responses |
| `--max-turns <N>` | Cap on conversation turns | Use `1` for peer review (single response) |
| `--skill <name>` | Pre-load a specific skill | Used by `bin/en-garden-ci` |
| `--system-prompt <text>` | Override the system prompt | Rare; usually leave default |
| `--include-partial-messages` | Stream partial responses | Skip for peer review (we want the final JSON) |

### Canonical peer-review invocation

```bash
ENSEMBLE_PEER_REVIEW=true \
  claude -p \
  --output-format json \
  --max-turns 1 \
  "$prompt"
```

### Canonical CI invocation (used by `bin/en-garden-ci`)

```bash
claude -p \
  --output-format json \
  --max-turns 50 \
  --skill en-garden \
  "$@"
```

## Codex (`codex exec`)

Headless command-execution mode.

| Flag | Purpose | Notes |
|---|---|---|
| `<prompt>` | The prompt | Positional |
| `--json` | Return structured JSON | Required for parseable peer responses |
| `--skill <name>` | Pre-load a specific skill | Used by `bin/en-garden-ci` |
| `--max-turns <N>` | Cap on conversation turns | Use `1` for peer review |

### Canonical peer-review invocation

```bash
ENSEMBLE_PEER_REVIEW=true \
  codex exec \
  --json \
  --max-turns 1 \
  "$prompt"
```

### Canonical CI invocation

```bash
codex exec --json --skill en-garden "$@"
```

## How skills consume this file

Skills don't embed flags. They reference variables set by `references/host-detect.md`:

- `PEER_CMD` — `claude -p` or `codex exec`
- `PEER_FORMAT` — `--output-format json` or `--json`

A skill builds its peer call as:

```bash
ENSEMBLE_PEER_REVIEW=true $PEER_CMD $PEER_FORMAT --max-turns 1 "$prompt"
```

When a flag changes upstream, this file and `host-detect.md` get updated; skills don't.

## Verification on install

`bin/ensemble-detect-host` runs a smoke test against the installed CLIs:

```bash
echo "ping" | claude -p --output-format json --max-turns 1 >/dev/null 2>&1 \
  && echo "  Claude CLI: ✓" \
  || echo "  Claude CLI: flag mismatch — check references/cli-wrappers.md"

echo "ping" | codex exec --json --max-turns 1 >/dev/null 2>&1 \
  && echo "  Codex CLI: ✓" \
  || echo "  Codex CLI: flag mismatch — check references/cli-wrappers.md"
```

If either smoke test fails, the setup script prints the mismatch loudly. Users get a clear pointer to this file rather than a silent breakage at first peer-review attempt.

## Updating this file

When a CLI changes a flag:

1. Update the relevant table above.
2. Update the canonical invocation snippets.
3. Update `references/host-detect.md` if it references the flag literal.
4. Bump version in `package.json`; note the change in `CHANGELOG.md`.
5. Re-run smoke tests via `bin/ensemble-detect-host` to confirm.

Skills do not need to be touched.
