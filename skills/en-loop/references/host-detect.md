# Host detection

Single source of truth for cross-host portability across every Ensemble skill. Loaded on demand; sets variables that the rest of the skill branches on.

> **Why this lives in one place.** Skills don't hard-code Claude Code or Codex tool names, CLI flags, or peer-CLI invocations. They consult this reference. When the underlying CLIs change a flag or an env var, one update propagates everywhere.

## Variables every skill exports

| Variable | Possible values | Used for |
|---|---|---|
| `HOST` | `claude-code` \| `codex` | Branching logic in skills |
| `PEER` | `codex` \| `claude` \| `<same-as-host>` | Display in messages and progress reports |
| `PEER_MODE` | `cross-agent` \| `single-agent-fallback` \| `off` | Determines prompt augmentation; surfaced to user |
| `PEER_CMD` | `codex exec` \| `claude -p` \| `<host's own CLI>` | Subprocess invocation for peer review |
| `PEER_FORMAT` | `--json` \| `--output-format json` | Structured output flag |
| `PEER_TURNS` | `--max-turns 1` (claude peer) \| `` empty (codex peer) | Per-agent turn cap — `claude -p` supports `--max-turns`; `codex exec` removed it and is single-shot, so it needs none. Consumers write `$PEER_CMD $PEER_FORMAT $PEER_TURNS "$prompt"` (empty collapses for Codex). |
| `PEER_AVAILABLE` | `true` \| `false` | Skip cross-review entirely if false |
| `QUESTION_TOOL` | `AskUserQuestion` \| `request_user_input` | Blocking prompts |
| `BLOCKING_QUESTION_AVAILABLE` | `true` \| `false` | Fall back to numbered prose options if false |
| `TASK_TOOL` | `TaskCreate/TaskUpdate` \| `update_plan` | Per-task progress tracking |

## Detection logic

Three steps, in order:

1. **Identify host** via env vars (`CLAUDE_CODE_VERSION` / `CLAUDE_AGENT_NAME` for Claude Code; `CODEX_HOME` / `CODEX_VERSION` for Codex). User override via `ENSEMBLE_HOST` env var. Inverse-CLI presence is the last-resort fallback.
2. **Read user override** from `~/.ensemble/config.json` → `peer_mode_override`. Values: `auto` (default), `cross-agent-only`, `single-agent-only`, `off`.
3. **Detect peer mode**:
   - `peer_mode_override = off` → `PEER_AVAILABLE=false`. Skip cross-review with a one-line note.
   - Other CLI installed → `PEER_MODE=cross-agent`, `PEER_CMD` = the other CLI.
   - Other CLI missing AND `peer_mode_override = cross-agent-only` → fail with note. Don't fall back.
   - Other CLI missing AND `peer_mode_override` in {auto, single-agent-only} → `PEER_MODE=single-agent-fallback`, `PEER_CMD` = host's own CLI.

## Tool-name adaptations

Skills do not hard-code Claude Code tool names. Where a built-in differs across hosts:

| Function | Claude Code | Codex |
|---|---|---|
| Block-on user question | `AskUserQuestion` (deferred — preload via `ToolSearch`) | `request_user_input` |
| Update task list | `TaskCreate` / `TaskUpdate` / `TaskList` | `update_plan` |
| Spawn subagent | `Agent` tool with `subagent_type` | `spawn_agent` |
| Run shell command | `Bash` | `shell` |
| Read file | `Read` | `read_file` |
| Edit file | `Edit` | `apply_patch` |
| Search files | `Glob` / `Grep` | `find` / `grep` via `shell` |

When a skill needs to invoke one of these, it references the variable name, not the literal tool name.

## Running the detection

`$SKILL_DIR/scripts/ensemble-detect-host` is the implementation. Run it and `eval` its `KEY=VALUE` output: it reads `~/.ensemble/config.json` for the override, walks every detection branch above, applies the recursion-guard short-circuit and the session cache described below, and prints the resolved variables. The script is canonical. This file carried an inline copy of its logic until 2026-09-04; the copy lacked the short-circuit and the cache, and every carrier paid ~900 tokens per read for it.

## Setup-script behavior

On first install, `./setup` runs the detection and warns if `PEER_MODE` is `single-agent-fallback`:

> "Only $HOST CLI detected. Ensemble will run cross-review as single-agent fallback (fresh instance of $HOST). For full cross-agent peer review, install the other CLI: <install instructions>. To silence this warning, set `peer_mode_override: \"single-agent-only\"` in `~/.ensemble/config.json`."

The setup script doesn't block on single-agent fallback — Ensemble works fine with one CLI. The warning surfaces the value of installing both.

## Recursion guard

A peer process must not recursively invoke another peer. The host sets `ENSEMBLE_PEER_REVIEW=true` in the subprocess environment before calling the peer CLI. Every cross-review entry point checks this var first; if `true`, skip cross-review and return.

```bash
if [ "${ENSEMBLE_PEER_REVIEW:-false}" = "true" ]; then
  echo "Recursion guard active (ENSEMBLE_PEER_REVIEW=true). Skipping cross-review." >&2
  exit 0
fi
```

Every peer entry point checks the variable first and skips the peer when it is set; the peer subprocess itself can still read files and return findings.

## Performance: detection cache and recursion-guard short-circuit

`$SKILL_DIR/scripts/ensemble-detect-host` has two performance fast-paths so skills don't pay full detection cost on every invocation:

1. **Recursion-guard short-circuit.** When `ENSEMBLE_PEER_REVIEW=true`, the script emits `PEER_AVAILABLE=false` and exits immediately without doing any detection work. (The calling skill would short-circuit anyway; this just avoids the wasted bash.)
2. **Session cache.** Detection results are written to `$HOME/.ensemble/host-cache.env` with a 1-hour TTL (configurable via `ENSEMBLE_DETECT_CACHE_TTL_MIN`). The first invocation in a session populates the cache; subsequent invocations within the TTL read from it (~6× faster: ~50ms → ~8ms wall time).

Cache controls:

| Mechanism | Effect |
|---|---|
| `--no-cache` flag | Bypass cache for this invocation; do not read or write |
| `ENSEMBLE_DETECT_NO_CACHE=true` | Same as `--no-cache` (env-var form) |
| `ENSEMBLE_DETECT_CACHE_FILE=<path>` | Override cache file location (default `$HOME/.ensemble/host-cache.env`) |
| `ENSEMBLE_DETECT_CACHE_TTL_MIN=<minutes>` | Override TTL (default 60) |
| Delete `$HOME/.ensemble/host-cache.env` | Force re-detection on next invocation |

The cache is invalidated automatically when the file's mtime exceeds the TTL. Skills don't need to manage the cache themselves — they invoke `$SKILL_DIR/scripts/ensemble-detect-host` as before, and the script handles caching transparently.

**When to bypass cache:** if the user installs/uninstalls a CLI mid-session, or changes `~/.ensemble/config.json`, the cache will lag until TTL expiry. Either delete the file or pass `--no-cache` for one invocation to refresh it.
