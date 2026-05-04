#!/usr/bin/env bash
# check-guardrail.sh — PreToolUse hook for /en-guardrail
#
# Reads tool-input JSON from stdin, inspects tool_input.command for destructive
# patterns. Emits {"permissionDecision":"ask","message":"..."} to force a
# permission prompt, or {} to allow the command through silently.
#
# Vendored from gstack/careful and extended:
#   - DELETE FROM <table> without WHERE
#   - terraform destroy
#   - aws s3 rm --recursive
#   - gcloud ... delete
#   - git branch -D, git tag -d, git worktree remove --force
#   - localhost+test/dev DB exemption for DROP/TRUNCATE/DELETE-without-WHERE
#
# To bypass for a single command, set ENSEMBLE_GUARDRAIL=off in that command's env.
set -euo pipefail

# Read stdin (JSON with tool_input)
INPUT=$(cat)

# Extract tool_input.command via Python — JSON-aware so escaped quotes inside
# the command (e.g. `psql -c "DROP TABLE users"` or `bash -lc "git reset --hard"`)
# don't truncate the extracted string. Earlier versions used grep+sed as a fast
# path; that silently dropped everything after the first escaped quote, making
# destructive substrings invisible to the matchers below.
CMD=$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
    print(json.loads(sys.stdin.read()).get("tool_input",{}).get("command",""))
except Exception:
    pass' 2>/dev/null || true)

# Empty command — nothing to inspect.
if [ -z "$CMD" ]; then
  echo '{}'
  exit 0
fi

# Per-command bypass: ENSEMBLE_GUARDRAIL=off prefix.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])ENSEMBLE_GUARDRAIL=off([[:space:]]|$)'; then
  echo '{}'
  exit 0
fi

CMD_LOWER=$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')

# --- Helper: is the command targeting an explicit local test/dev DB? ---
# Both signals must be present:
#   1) localhost connection (-h localhost, -h 127.0.0.1, @localhost, @127.0.0.1, host=localhost)
#   2) DB name (after /, -d, dbname=, database=) contains "test", "dev", or "local"
is_local_test_db() {
  local cmd_lower="$1"
  if ! printf '%s' "$cmd_lower" | grep -qE -- '(-h[ =](localhost|127\.0\.0\.1)|@(localhost|127\.0\.0\.1)|host=(localhost|127\.0\.0\.1))'; then
    return 1
  fi
  if ! printf '%s' "$cmd_lower" | grep -qE -- '(/|-d[ =]+|dbname=|database=)[a-z0-9_-]*(test|dev|local)[a-z0-9_-]*'; then
    return 1
  fi
  return 0
}

# --- Safe exception: rm -rf of build artifacts ---
if printf '%s' "$CMD" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+|--recursive[[:space:]]+)' 2>/dev/null; then
  SAFE_ONLY=true
  RM_ARGS=$(printf '%s' "$CMD" | sed -E 's/.*rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*//;s/--recursive[[:space:]]*//')
  for target in $RM_ARGS; do
    case "$target" in
      */node_modules|node_modules|*/.next|.next|*/dist|dist|*/__pycache__|__pycache__|*/.cache|.cache|*/build|build|*/.turbo|.turbo|*/coverage|coverage)
        ;;
      -*)
        ;;
      *)
        SAFE_ONLY=false
        break
        ;;
    esac
  done
  if [ "$SAFE_ONLY" = true ]; then
    echo '{}'
    exit 0
  fi
fi

WARN=""
PATTERN=""

# rm -r / rm -rf / rm --recursive
if printf '%s' "$CMD" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*r|--recursive)' 2>/dev/null; then
  WARN="recursive delete (rm -r). This permanently removes files."
  PATTERN="rm_recursive"
fi

# DROP TABLE / DROP DATABASE — exempt explicit local test/dev DBs
if [ -z "$WARN" ] && printf '%s' "$CMD_LOWER" | grep -qE 'drop[[:space:]]+(table|database)' 2>/dev/null; then
  if ! is_local_test_db "$CMD_LOWER"; then
    WARN="SQL DROP detected. This permanently deletes database objects."
    PATTERN="drop_table"
  fi
fi

# TRUNCATE — exempt explicit local test/dev DBs
if [ -z "$WARN" ] && printf '%s' "$CMD_LOWER" | grep -qE '\btruncate\b' 2>/dev/null; then
  if ! is_local_test_db "$CMD_LOWER"; then
    WARN="SQL TRUNCATE detected. This deletes all rows from a table."
    PATTERN="truncate"
  fi
fi

# DELETE FROM <table> without WHERE — exempt explicit local test/dev DBs
if [ -z "$WARN" ] && printf '%s' "$CMD_LOWER" | grep -qE 'delete[[:space:]]+from[[:space:]]+[a-z_][a-z0-9_.]*' 2>/dev/null; then
  if ! printf '%s' "$CMD_LOWER" | grep -qE '\bwhere\b' 2>/dev/null; then
    if ! is_local_test_db "$CMD_LOWER"; then
      WARN="DELETE FROM without WHERE deletes every row in the table."
      PATTERN="delete_no_where"
    fi
  fi
fi

# git push --force / -f
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(-f\b|--force)' 2>/dev/null; then
  WARN="git force-push rewrites remote history. Other contributors may lose work."
  PATTERN="git_force_push"
fi

# git reset --hard
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard' 2>/dev/null; then
  WARN="git reset --hard discards all uncommitted changes."
  PATTERN="git_reset_hard"
fi

# git checkout . / git restore .
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'git[[:space:]]+(checkout|restore)[[:space:]]+\.' 2>/dev/null; then
  WARN="discards all uncommitted changes in the working tree."
  PATTERN="git_discard"
fi

# git branch -D
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'git[[:space:]]+branch[[:space:]]+(-[a-zA-Z]*D|--delete[[:space:]]+--force)' 2>/dev/null; then
  WARN="git branch -D force-deletes a branch even if its work is unmerged."
  PATTERN="git_branch_force_delete"
fi

# git tag -d
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'git[[:space:]]+tag[[:space:]]+(-[a-zA-Z]*d|--delete)' 2>/dev/null; then
  WARN="git tag -d removes a tag locally; if pushed it can affect releases."
  PATTERN="git_tag_delete"
fi

# git worktree remove --force
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'git[[:space:]]+worktree[[:space:]]+remove[[:space:]]+(-[a-zA-Z]*f|--force)' 2>/dev/null; then
  WARN="git worktree remove --force discards uncommitted changes in the worktree."
  PATTERN="git_worktree_force_remove"
fi

# kubectl delete
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'kubectl[[:space:]]+delete' 2>/dev/null; then
  WARN="kubectl delete removes Kubernetes resources. May impact production."
  PATTERN="kubectl_delete"
fi

# docker rm -f / docker system prune
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'docker[[:space:]]+(rm[[:space:]]+-f|system[[:space:]]+prune)' 2>/dev/null; then
  WARN="Docker force-remove or prune. May delete running containers or cached images."
  PATTERN="docker_destructive"
fi

# terraform destroy
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'terraform[[:space:]]+destroy' 2>/dev/null; then
  WARN="terraform destroy tears down all managed infrastructure."
  PATTERN="terraform_destroy"
fi

# aws s3 rm --recursive
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'aws[[:space:]]+s3[[:space:]]+rm[[:space:]]+.*--recursive' 2>/dev/null; then
  WARN="aws s3 rm --recursive bulk-deletes objects from a bucket."
  PATTERN="aws_s3_rm_recursive"
fi

# gcloud ... delete
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE 'gcloud([[:space:]]+[a-z-]+)+[[:space:]]+delete\b' 2>/dev/null; then
  WARN="gcloud delete removes a cloud resource."
  PATTERN="gcloud_delete"
fi

# --- Output ---
if [ -n "$WARN" ]; then
  mkdir -p ~/.ensemble/analytics 2>/dev/null || true
  REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"event":"hook_fire","skill":"en-guardrail","pattern":"%s","ts":"%s","repo":"%s"}\n' \
    "$PATTERN" "$TS" "$REPO" >> ~/.ensemble/analytics/guardrail.jsonl 2>/dev/null || true

  WARN_ESCAPED=$(printf '%s' "$WARN" | sed 's/"/\\"/g')
  printf '{"permissionDecision":"ask","message":"[guardrail] %s"}\n' "$WARN_ESCAPED"
else
  echo '{}'
fi
