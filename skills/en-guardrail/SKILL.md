---
name: en-guardrail
description: "Always-on safety guardrail. PreToolUse hook on Bash inspects each command for destructive patterns (recursive rm, DROP TABLE, DELETE-without-WHERE, force-push, git reset --hard, branch -D, kubectl delete, docker rm -f / system prune, terraform destroy, aws s3 rm --recursive, gcloud delete) and forces a permission prompt. Build artifacts and localhost+test/dev databases pass without prompting. Per-command bypass via ENSEMBLE_GUARDRAIL=off. Trigger phrases: 'guardrail', 'safety mode', 'check guardrail', 'what's protected'."
---

# `/en-guardrail`

Always-on `PreToolUse` hook that prompts before destructive Bash commands. Vendored from `gstack/careful` and extended for Ensemble use.

> **Activation model.** The script is run by a global `PreToolUse` hook registered in `~/.claude/settings.json`. Once installed, it is on for **every** session and **every** Bash call — no opt-in per session needed.

## Process (when invoked manually)

1. **Detect host.** Source `references/host-detect.md`.
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

Single-file `rm` (e.g. `rm foo.ts`) is **not** flagged — too noisy for routine cleanup.

## Safe exceptions

These pass without prompting:

- `rm -rf` of common build artifacts: `node_modules`, `.next`, `dist`, `__pycache__`, `.cache`, `build`, `.turbo`, `coverage`.
- `DROP` / `TRUNCATE` / `DELETE-without-WHERE` against an explicit local test/dev DB. Both signals must be present in the same command:
  - **Localhost connection** — `-h localhost`, `-h 127.0.0.1`, `@localhost`, `@127.0.0.1`, or `host=localhost|127.0.0.1`.
  - **Test/dev/local DB name** — DB name (after `/`, `-d`, `dbname=`, or `database=`) contains `test`, `dev`, or `local`.

  Examples that exempt: `psql -h localhost -d test_app -c 'DROP TABLE users'`, `psql postgresql://app@127.0.0.1/myapp_test -c 'TRUNCATE orders'`. Examples that **don't** exempt: `psql -h localhost -d production`, `psql -h staging-db -d test_app`.

## Temporary disable

For a single shell:

```bash
ENSEMBLE_GUARDRAIL=off <your-command>
```

The hook honors `ENSEMBLE_GUARDRAIL=off` for the **single command's environment**. Don't `export` it globally — that defeats the guardrail for the rest of the session.

## Installation

The hook is registered in `~/.claude/settings.json` under `hooks.PreToolUse`. The canonical entry:

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

`bin/check-guardrail.sh` reads the tool-input JSON on stdin, extracts `tool_input.command`, normalizes case, and matches against the destructive-pattern catalog. On match, it returns `{"permissionDecision": "ask", "message": "[guardrail] <reason>"}` — Claude pauses and prompts the user. On no match (or safe-exception hit), it returns `{}` — Claude proceeds normally.

The hook fires only on `Bash` tool calls — `Edit`, `Write`, `Read` are unaffected.

## Reference files

- `bin/check-guardrail.sh` — the hook script (canonical source).
- `references/host-detect.md` — host detection.
- Upstream: `gstack/careful` — the original this is vendored from. To pull updates, diff against the upstream and selectively re-apply.

## Failure protocol

| Failure | Behavior |
|---|---|
| `~/.claude/settings.json` lacks the `PreToolUse` registration | `/en-guardrail` surfaces the install snippet and exits non-zero — guardrail is **not** active |
| Hook script missing or unreadable | Claude Code's hook runner skips it silently — surface a warning when `/en-guardrail` runs |
| Pattern false positive (legitimate command flagged) | Override the prompt manually; if it recurs, tighten the regex in `bin/check-guardrail.sh` |
| Pattern false negative (destructive command not flagged) | Open a tech-debt entry; add the pattern. Do **not** widen the safe-exceptions list reactively |
| `ENSEMBLE_GUARDRAIL=off` exported globally | `/en-guardrail` warns that the bypass is set session-wide; suggest `unset ENSEMBLE_GUARDRAIL` |
