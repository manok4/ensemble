---
name: en-guardrail
description: "Always-on safety guardrail against destructive commands. Trigger phrases: 'guardrail', 'safety mode', 'check guardrail', 'what's protected'. PreToolUse hooks inspect Bash commands and DB-writing MCP tools for destructive patterns (recursive rm, DROP TABLE, TRUNCATE, force-push, terraform destroy, and similar) and force a permission prompt. Build artifacts and local test databases pass without prompting."
---


# `/en-guardrail`

Always-on `PreToolUse` hook that prompts before destructive Bash commands. Vendored from `gstack/careful` and extended for Ensemble use.

> **Activation model.** The script is run by a global `PreToolUse` hook registered in `~/.claude/settings.json`. Once installed, it is on for **every** session and **every** Bash call — no opt-in per session needed.

## Process (when invoked manually)

1. **Resolve the skill directory** so the bundled scripts can be run and the installed hook compared against them. Nothing else here needs resolving: the guardrail has no modes, no peer, and no host branch — the same three scripts do the same thing wherever it runs.

2. **Status check.** Verify the hook is registered in `~/.claude/settings.json` (`PreToolUse` → `Bash` matcher → `bin/check-guardrail.sh`). If missing, surface the install snippet (see "Installation" below) and stop.
3. **Show protected patterns** — render the table from "What's protected" below.
4. **Show recent fires** if `~/.ensemble/analytics/guardrail.jsonl` exists — last 10 lines, summarized as `pattern × count × repo`.
5. **Optional dry-run.** If user passes a sample command (`/en-guardrail "rm -rf /tmp/foo"`), pipe a synthetic tool-input JSON through `bin/check-guardrail.sh` and show the verdict (`ask` vs `allow`).

## What's protected

| Pattern | Example | Risk |
|---|---|---|
| `rm -r` / `rm -rf` / `rm --recursive` | `rm -rf /var/data` | Recursive delete |
| `DROP TABLE` / `DROP DATABASE` | `DROP TABLE users;` | Schema/data loss |
| `TRUNCATE` | `TRUNCATE orders;` | Data loss |
| `DELETE FROM <table>` without `WHERE` | `DELETE FROM users;` | Silent table-wipe |
| `git push --force` / `-f` | `git push -f origin main` | Remote history rewrite |
| `git reset --hard` | `git reset --hard HEAD~3` | Uncommitted-work loss |
| `git checkout .` / `git restore .` | `git checkout .` | Working-tree wipe |
| `git branch -D` / `git tag -d` | `git branch -D feature/x` | Forced ref deletion |
| `git worktree remove --force` | `git worktree remove -f ../wt` | Forced worktree removal |
| `kubectl delete` | `kubectl delete pod` | Production impact |
| `docker rm -f` / `docker system prune` | `docker system prune -a` | Container/image loss |
| `terraform destroy` | `terraform destroy -auto-approve` | Infrastructure teardown |
| `aws s3 rm … --recursive` | `aws s3 rm s3://bkt/ --recursive` | Bulk object delete |
| `gcloud … delete` | `gcloud compute instances delete x` | Cloud-resource delete |
| `find … -delete` / `-exec rm` | `find / -name x -delete` | Bulk file delete (EN09) |
| `rsync … --delete` | `rsync -a --delete src/ dst/` | Destination file delete (EN09) |
| `shred` / `truncate -s 0` / `unlink` | `shred secret.pem` | File destruction (EN09) |
| `>` truncation of an existing file / symlink | `echo x > important.log` | Overwrite existing file (EN09) |
| `UPDATE …` without a top-level `WHERE` | `UPDATE users SET active=false` | Silent mass-update (EN09) |
| SQL from a file / stdin / pipe (non-local) | `psql -h prod -f migrate.sql` | Un-inspectable SQL (EN09) |
| ORM destroyers | `prisma migrate reset`, `rails db:drop` | Database wipe (EN09) |
| DB-writing **MCP tools** | `mcp__Neon__run_sql` running `DROP TABLE` | MCP DB write (EN09) |

Single-file `rm` (e.g. `rm foo.ts`) is **not** flagged — too noisy for routine cleanup. `UPDATE`/`DELETE` **with** a real top-level `WHERE`, `>>` append, and new-file `>` creation are likewise not flagged.

## Safe exceptions

These pass without prompting:

- `rm -rf` of common build artifacts: `node_modules`, `.next`, `dist`, `__pycache__`, `.cache`, `build`, `.turbo`, `coverage` — **only as a plain, in-tree relative path** (EN09). An absolute (`/build`), home (`~/dist`, `$HOME/…`), shell-expanded (`${HOME}/dist`, `$PWD/dist`, `$(pwd)/dist`), globbed (`/*`), or parent-escaping (`../dist`) target is NOT exempt and prompts — the exemption is a positive allowlist that fails closed, so a "safe" artifact name can never greenlight a delete outside the working tree.
- `DROP` / `TRUNCATE` / `DELETE`- or `UPDATE`-without-WHERE / SQL-from-file / ORM-reset against an explicit local test/dev DB. Both signals must be present in the same command:
  - **Localhost connection** — `-h localhost`, `-h 127.0.0.1`, `@localhost`, `@127.0.0.1`, or `host=localhost|127.0.0.1`.
  - **Test/dev/local DB name** — DB name (after `/`, `-d`, `dbname=`, or `database=`) contains `test`, `dev`, or `local`.

  Examples that exempt: `psql -h localhost -d test_app -c 'DROP TABLE users'`, `psql postgresql://app@127.0.0.1/myapp_test -c 'TRUNCATE orders'`. Examples that **don't** exempt: `psql -h localhost -d production`, `psql -h staging-db -d test_app`.

## MCP database tools (EN09)

A second `PreToolUse` matcher routes DB-writing MCP tools (e.g. `mcp__Neon__run_sql`, `mcp__Postgres__execute`) to the same hook, so a `DROP TABLE` issued through an MCP tool is caught the same as one via `psql`. The hook resolves the statement and the tool's **controlling target field** through a per-tool adapter; the local test/dev exemption is decided ONLY from that authoritative field, never from the SQL text (a `localhost`/`test` string in a comment can't spoof it). **Remote-only providers (e.g. Neon) never exempt** — a destructive statement there always prompts. A DB-write-named tool with no adapter, or unresolvable input, fails closed.

## Scope (what the guardrail is, and is not)

The guardrail is a **pattern-based accident brake**, not a path sandbox or a policy wall:

- **It does not enforce the working-folder boundary.** Which directories the agent may read/write is the **host permission system's** job (Claude Code). The guardrail adds a destructive-pattern prompt on top; it does not, on its own, confine deletes to the repo.
- **"Production" is inferred by exemption, not a positive detector.** Anything not provably a local test/dev target is treated as potentially production and prompts. A configurable positive production-marker (`production_hosts` / URL patterns) is a possible future extension, not implemented today.
- **Coverage is a maintained list, not exhaustive.** New destructive tools/verbs are added as they're identified; the behavioral test suite (`tests/en-guardrail/`) is the source of truth for exactly what's covered.

## Temporary disable (human-only, out-of-band — EN09)

The bypass is read **only from the hook's own process environment**, set by **you** in your shell **before launching** the agent:

```bash
export ENSEMBLE_GUARDRAIL_BYPASS=on   # in your shell, then start Claude Code
```

**Why not an inline prefix or a config file:** the old `ENSEMBLE_GUARDRAIL=off <command>` prefix was **model-writable** — an agent could prepend it to self-exempt — so it no longer bypasses anything (it now prompts like any other destructive command). A command-level `VAR=value <command>` assignment only scopes that subprocess and cannot reach the hook's environment, and the agent cannot mutate the already-running parent process's env. This makes the bypass a genuine human-only control within a session.

> **Agents: never set, export, or write `ENSEMBLE_GUARDRAIL_BYPASS`, and never edit shell profiles (`~/.zshrc`, `~/.bashrc`) to set it.** The bypass exists for the human operator only. (Editing a profile affects only *future* shells, not the running session, but it is still off-limits.)

To turn the guard back on, `unset ENSEMBLE_GUARDRAIL_BYPASS` (or start a new shell without the export).

## Installation

Use the installer this skill carries rather than editing settings by hand — it registers **both** matchers (Bash and the MCP DB-tool path, EN09), which the snippet below does not:

```
bash "$SKILL_DIR/bin/install-guardrail" status           # what is currently active
bash "$SKILL_DIR/bin/install-guardrail" install-project  # writes <repo>/.claude/settings.json
bash "$SKILL_DIR/bin/install-guardrail" install-global   # prints the one-liner to run yourself
```

Global scope is print-only on purpose: an agent must not write `~/.claude/`, so the installer hands you the command and you run it.

For reference, the hook is registered in `~/.claude/settings.json` under `hooks.PreToolUse`. The canonical Bash entry:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${ENSEMBLE_HOME:-$HOME/CodeRepo/ensemble}/skills/en-guardrail/bin/check-guardrail.sh\"",
            "statusMessage": "Checking for destructive commands..."
          }
        ]
      }
    ]
  }
}
```

The `${ENSEMBLE_HOME:-$HOME/CodeRepo/ensemble}` expansion lets you move the Ensemble checkout — set `ENSEMBLE_HOME` in your shell profile to override.

## How it works

Two scripts, and the split is the whole design.

**`bin/check-guardrail.sh` is a thin wrapper** — about fifty lines, and **zero pattern matching**. It reads the tool-input JSON on stdin, honours the human bypass, calls the analyzer, and writes the output envelope plus analytics. On a destructive verdict it returns `{"permissionDecision": "ask", "message": "[guardrail] <reason>"}` and Claude prompts; otherwise `{}` and Claude proceeds.

**`bin/guardrail_analyze.py` does all the deciding** — every pattern, the shell tokenisation (`shlex`), the structural parse of connection targets, and the statement-scope SQL analysis shared by the Bash and MCP paths.

**The split exists because bash-regex parsing was bypassable.** EN09 found six classes it could not handle: `rm` option ordering, compound commands, quoted redirection, spoofable `localhost` substrings, quoted or aliased `UPDATE` tables, and SQL piped through wrappers. A regex over a command string cannot tokenise, and each of those is a way to look different while doing the same thing. Proper parsing is not a refinement here; it is the reason the guard holds.

**Fail closed.** If the analyzer cannot run at all, the wrapper prompts rather than allowing — an unavailable analyzer must never read as a safe command.

The hook fires only on `Bash` tool calls — `Edit`, `Write`, `Read` are unaffected.

## Reference files

- `bin/check-guardrail.sh` — the hook entry point: stdin, bypass, output envelope, analytics. Carries no patterns.
- `bin/guardrail_analyze.py` — **the analyzer, and where every pattern lives.** Shell tokenisation, connection-target parsing, statement-scope SQL analysis, shared by the Bash and MCP paths. Change behaviour here.
- `bin/install-guardrail` — registers and reports both `PreToolUse` matchers; `status`, `install-project`, `install-global`.
- Upstream: `gstack/careful` — the original the wrapper was vendored from. The analyzer is Ensemble's own (EN09) and has no upstream to diff against.

## Failure protocol

| Failure | Behavior |
|---|---|
| `~/.claude/settings.json` lacks the `PreToolUse` registration | `/en-guardrail` surfaces the install snippet and exits non-zero — guardrail is **not** active |
| Hook script missing or unreadable | Claude Code's hook runner skips it silently — surface a warning when `/en-guardrail` runs |
| Pattern false positive (legitimate command flagged) | Override the prompt manually. If it recurs, narrow the rule in **`bin/guardrail_analyze.py`** — that is where every pattern lives. **Never add matching to `check-guardrail.sh`:** it is a wrapper with no regex by design, and a bash regex over a command string is what EN09 removed because it could not tokenise. Add a failing fixture to `tests/en-guardrail/` first. |
| Pattern false negative (destructive command not flagged) | Open a tech-debt entry, add a fixture that reproduces it, then add the pattern in **`bin/guardrail_analyze.py`**. Do **not** widen the safe-exceptions list reactively — an exemption added to silence one command is a hole for every command that resembles it. |
| `ENSEMBLE_GUARDRAIL_BYPASS=on` set in the launch environment | `/en-guardrail` warns that the bypass is active session-wide; suggest `unset ENSEMBLE_GUARDRAIL_BYPASS` and relaunch |
