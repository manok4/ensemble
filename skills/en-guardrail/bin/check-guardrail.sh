#!/usr/bin/env bash
# check-guardrail.sh — PreToolUse hook for /en-guardrail
#
# Reads tool-input JSON from stdin and decides whether a Bash command or a
# DB-writing MCP tool call is destructive enough to force a permission prompt.
# Emits {"permissionDecision":"ask","message":"..."} to prompt, or {} to allow.
#
# Thin wrapper (EN09): all shell/SQL parsing lives in guardrail_analyze.py —
# proper tokenization (shlex), structural connection-target parsing, and a
# single statement-scope analyzer shared by the Bash and MCP paths. Bash-regex
# parsing of shell and SQL was bypassable (rm option ordering / compound
# commands, quoted redirection, spoofable localhost substrings, quoted/aliased
# UPDATE tables, piped SQL through wrappers). This wrapper only handles stdin,
# the human bypass, and the output envelope + analytics.
set -euo pipefail

INPUT=$(cat)

# Bypass (EN09 A3/F1): read ONLY from the hook's own inherited process
# environment, which the human exports in their shell BEFORE launching the
# agent. Never parsed from the command string and never from an agent-writable
# file, so a command-level `VAR=value <cmd>` assignment (which only scopes the
# subprocess) cannot activate it and the agent cannot self-exempt within the
# session. The old inline `ENSEMBLE_GUARDRAIL=off` command prefix no longer
# bypasses. Applies to Bash AND MCP tool calls.
if [ "${ENSEMBLE_GUARDRAIL_BYPASS:-}" = "on" ]; then
  echo '{}'
  exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Fail closed: if the analyzer can't run, prompt (never silently allow).
RESULT=$(printf '%s' "$INPUT" | python3 "$SCRIPT_DIR/guardrail_analyze.py" 2>/dev/null || printf 'ASK\tanalyzer_error\tguardrail analyzer failed; confirm the command is safe.')

VERDICT=${RESULT%%$'\t'*}

if [ "$VERDICT" = "ALLOW" ]; then
  echo '{}'
  exit 0
fi

# ASK — parse the pattern + message (tab-separated) and emit the prompt.
REST=${RESULT#ASK$'\t'}
PATTERN=${REST%%$'\t'*}
MESSAGE=${REST#*$'\t'}
[ "$MESSAGE" = "$REST" ] && MESSAGE="destructive command detected."

mkdir -p ~/.ensemble/analytics 2>/dev/null || true
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
printf '{"event":"hook_fire","skill":"en-guardrail","pattern":"%s","ts":"%s","repo":"%s"}\n' \
  "$PATTERN" "$TS" "$REPO" >> ~/.ensemble/analytics/guardrail.jsonl 2>/dev/null || true

MSG_ESCAPED=$(printf '%s' "$MESSAGE" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"permissionDecision":"ask","message":"[guardrail] %s"}\n' "$MSG_ESCAPED"
