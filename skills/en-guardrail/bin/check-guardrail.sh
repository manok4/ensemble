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

# --- Empty tool_input.command: a non-Bash tool. Cover DB-writing MCP tools ---
# (EN09 U4/B2). The Bash matchers below all key off $CMD, so without this an MCP
# `run_sql` executing DROP TABLE would sail through. Per-tool adapters (F6) name
# the statement field AND the controlling target field; the local exemption is
# from that field ONLY (never SQL text, F2); remote-only providers never exempt
# (F12); a write-named tool with no adapter fails closed (F8/F15).
if [ -z "$CMD" ]; then
  MCP_VERDICT=$(python3 -c '
import sys, json, re
try:
    d = json.loads(sys.argv[1])
except Exception:
    print("ask"); sys.exit(0)          # malformed on a tool call -> fail closed
tool = d.get("tool_name", "") or ""
ti = d.get("tool_input", {}) or {}
if not isinstance(ti, dict): ti = {}
# Server-qualified, adapter-backed registry (F8/F15): stmt field, controlling
# target fields, local_capable. Only these tools are treated as DB writers.
ADAPTERS = {
    "mcp__Neon__run_sql":                    ("sql",            ["project","projectId","branch","branchId"], False),
    "mcp__Neon__run_sql_transaction":        ("sql_statements", ["project","projectId","branch","branchId"], False),
    "mcp__Neon__prepare_database_migration": ("migration_sql",  ["project","projectId"],                     False),
    "mcp__Postgres__query":                  ("sql",            ["connectionString","connection","database"], True),
    "mcp__Postgres__execute":                ("sql",            ["connectionString","connection","database"], True),
}
# Conservative fail-closed naming policy for un-adapted but clearly DB-writing tools.
WRITE_NAME = re.compile(r"^mcp__.+__(run_sql|run_sql_transaction|execute_sql|apply_migration|prepare_database_migration)(_.*)?$", re.I)
if tool not in ADAPTERS:
    print("ask" if WRITE_NAME.match(tool) else "na"); sys.exit(0)
stmt_field, ctrl_fields, local_capable = ADAPTERS[tool]
def getf(obj, name):
    if isinstance(obj, dict):
        if name in obj: return obj[name]
        p = obj.get("params")
        if isinstance(p, dict) and name in p: return p[name]
    return None
stmt = getf(ti, stmt_field)
if stmt is None:
    print("ask"); sys.exit(0)           # unresolvable statement on a write tool
if isinstance(stmt, list): stmt = " ; ".join(str(x) for x in stmt)
low = str(stmt).lower()
destructive = bool(re.search(r"\bdrop\s+(table|database|schema)\b|\btruncate\b|\bdelete\s+from\b|\balter\s+table\b|\bupdate\s+\w+\s+set\b", low))
if not destructive:
    print("allow"); sys.exit(0)
if not local_capable:
    print("ask"); sys.exit(0)           # remote-only provider (e.g. Neon) never exempts
def proves_local_testdev():
    for f in ctrl_fields:               # controlling target fields ONLY (not SQL text, F2)
        v = getf(ti, f)
        if not isinstance(v, str): continue
        vl = v.lower()
        if ("localhost" in vl or "127.0.0.1" in vl) and any(k in vl for k in ("test","dev","local")):
            return True
    return False
print("allow" if proves_local_testdev() else "ask")
' "$INPUT" 2>/dev/null || echo "ask")
  case "$MCP_VERDICT" in
    allow|na)
      echo '{}'
      exit 0
      ;;
    *)   # ask, or any error -> fail closed
      mkdir -p ~/.ensemble/analytics 2>/dev/null || true
      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
      printf '{"event":"hook_fire","skill":"en-guardrail","pattern":"mcp_db_write","ts":"%s","repo":"unknown"}\n' \
        "$TS" >> ~/.ensemble/analytics/guardrail.jsonl 2>/dev/null || true
      printf '{"permissionDecision":"ask","message":"[guardrail] MCP database tool: a destructive or non-locally-targeted statement. Confirm before running."}\n'
      exit 0
      ;;
  esac
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

# --- Helper: does the command truncate an EXISTING file via `>` redirection? ---
# Returns 0 (ask) when a truncating redirect (`>`, `1>`, `2>`, `&>`, NOT `>>`)
# targets an existing regular file OR a symlink (redirection follows symlinks,
# so a link can truncate a file outside the tree), OR the target can't be safely
# resolved (shell expansion). Returns 1 (allow) for new-file creation or no
# truncating redirect. Paths resolve against the hook's cwd (best-effort). (EN09 A2/F9/F14)
redir_truncates_existing() {
  local cmd="$1" targets t
  targets=$(printf '%s' "$cmd" \
    | sed -E 's/>>/@APPEND@/g' \
    | grep -oE '([0-9]*|&)>[[:space:]]*[^[:space:]|&;<>]+' 2>/dev/null \
    | sed -E 's/^([0-9]*|&)>[[:space:]]*//')
  [ -z "$targets" ] && return 1
  set -f
  for t in $targets; do
    case "$t" in
      *'$'*|*'`'*|*'~'*|*'*'*|*'?'*) set +f; return 0 ;;   # unresolvable -> fail closed
    esac
    if [ -L "$t" ]; then set +f; return 0; fi              # symlink -> may escape tree
    if [ -f "$t" ]; then set +f; return 0; fi              # existing regular file
  done
  set +f
  return 1
}

# --- Safe exception: rm -rf of build artifacts (positive allowlist, EN09) ---
# A target is exempt ONLY if it is a literal, plain, in-tree RELATIVE path whose
# final segment is a known build artifact. Any absolute (`/…`), home (`~…`),
# shell expansion (`$`, `${}`, `$()`, backtick), glob (`*` `?` `[`), quote, or
# `..` escape disqualifies the WHOLE command from the exemption -> it falls
# through to the recursive-rm prompt (fail closed). This closes EN09 A1/F5:
# the old `*/build|build` globs matched `/build` and `~/dist` and greenlit
# filesystem-root / home-dir deletes.
if printf '%s' "$CMD" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+|--recursive[[:space:]]+)' 2>/dev/null; then
  SAFE_ONLY=true
  RM_ARGS=$(printf '%s' "$CMD" | sed -E 's/.*rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*//;s/--recursive[[:space:]]*//')
  # Any shell expansion / substitution / home ref anywhere in the command voids
  # the exemption (a resolved target could land outside the tree).
  case "$CMD" in
    *'$'*|*'`'*|*'~'*|*'"'*|*"'"*) SAFE_ONLY=false ;;
  esac
  if [ "$SAFE_ONLY" = true ]; then
    set -f  # no globbing while we word-split RM_ARGS
    for target in $RM_ARGS; do
      case "$target" in
        -*) continue ;;                                  # a flag, not a target
      esac
      case "$target" in
        /*|~*|..|../*|*/..|*/../*|*'*'*|*'?'*|*'['*)      # absolute / escape / glob
          SAFE_ONLY=false; break ;;
      esac
      base=${target%/}          # tolerate a trailing slash (dist/)
      base=${base##*/}          # final path segment
      case "$base" in
        node_modules|.next|dist|__pycache__|.cache|build|.turbo|coverage) ;;
        *) SAFE_ONLY=false; break ;;
      esac
    done
    set +f
  fi
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

# --- Non-recursive destructive deleters (EN09 A2) ---
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])find[[:space:]].*(-delete\b|-exec[[:space:]]+rm\b)' 2>/dev/null; then
  WARN="find -delete / -exec rm removes every matched file."
  PATTERN="find_delete"
fi
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])rsync[[:space:]].*--delete' 2>/dev/null; then
  WARN="rsync --delete removes destination files not present in the source."
  PATTERN="rsync_delete"
fi
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])shred([[:space:]]|$)' 2>/dev/null; then
  WARN="shred irrecoverably destroys file contents."
  PATTERN="shred"
fi
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])truncate[[:space:]]+.*-s[[:space:]=]*0(\b|$)' 2>/dev/null; then
  WARN="truncate -s 0 empties a file."
  PATTERN="truncate_zero"
fi
if [ -z "$WARN" ] && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])unlink([[:space:]]|$)' 2>/dev/null; then
  WARN="unlink removes a file."
  PATTERN="unlink"
fi
# Output-redirection truncation of an existing file / symlink (not new-file creation).
if [ -z "$WARN" ] && redir_truncates_existing "$CMD"; then
  WARN="output redirection (>) truncates an existing file."
  PATTERN="redir_truncate"
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

# --- UPDATE without a TOP-LEVEL WHERE (EN09 B3/F7/F11) — exempt local test/dev ---
# A word-boundary WHERE test is defeated by a WHERE in a comment, a string
# literal, a subquery, or a later statement. Delegate the scope analysis to
# python (already a dependency): strip comments + literals, split on `;`, and
# require a WHERE at parenthesis-depth 0 in the UPDATE's own statement.
# Gated behind a cheap grep so the common case pays no python cost.
if [ -z "$WARN" ] && printf '%s' "$CMD_LOWER" | grep -qE '\bupdate\b' 2>/dev/null; then
  UPDATE_UNSCOPED=$(printf '%s' "$CMD" | python3 -c '
import sys, re
s = sys.stdin.read()
s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)   # block comments
s = re.sub(r"--[^\n]*", " ", s)                # line comments
# Strip SQL SINGLE-quoted string literals only. Double quotes here are the
# shell quoting around the -c payload (and SQL double quotes are identifiers,
# not strings), so stripping them would delete the SQL itself.
s = re.sub(r"\x27(?:\x27\x27|[^\x27])*\x27", "\x27\x27", s)
out = "no"
for stmt in s.split(";"):
    m = re.search(r"\bupdate\b\s+[a-zA-Z_][\w.$]*\s+set\b", stmt, re.I)
    if not m:
        continue
    depth = 0; has_where = False
    for mm in re.finditer(r"[()]|\bwhere\b", stmt[m.end():], re.I):
        t = mm.group(0)
        if t == "(": depth += 1
        elif t == ")": depth = max(0, depth - 1)
        elif depth == 0: has_where = True; break
    if not has_where:
        out = "yes"; break
print(out)
' 2>/dev/null || echo "no")
  if [ "$UPDATE_UNSCOPED" = "yes" ] && ! is_local_test_db "$CMD_LOWER"; then
    WARN="UPDATE without a top-level WHERE modifies every row in the table."
    PATTERN="update_no_where"
  fi
fi

# --- SQL from a file / stdin / pipe that the hook can't inspect (EN09 B1/F4) ---
# A DB client fed SQL via -f/--file, input redirection, a heredoc, a client
# file command (\i / \. / source), or a pipe can carry a hidden DROP. Against a
# non-local target, fail closed (ask). Exempt the explicit local test/dev target.
if [ -z "$WARN" ] \
   && printf '%s' "$CMD_LOWER" | grep -qE '(^|[[:space:]|(])(psql|mysql|mariadb|mongosh|sqlite3|cockroach|clickhouse-client|usql)([[:space:]]|$)' 2>/dev/null; then
  if printf '%s' "$CMD" | grep -qE '(-f[[:space:]=]|--file([[:space:]=])|[[:space:]]-f[^[:space:]]|[[:space:]]<[[:space:]]|<<|\\i[[:space:]]|\\\.[[:space:]]|[[:space:]]source[[:space:]]|(-e|--execute)[[:space:]=][^[:space:]]*\.sql)' 2>/dev/null \
     || printf '%s' "$CMD_LOWER" | grep -qE '\|[[:space:]]*(psql|mysql|mariadb|mongosh|sqlite3|cockroach)([[:space:]]|$)' 2>/dev/null; then
    if ! is_local_test_db "$CMD_LOWER"; then
      WARN="SQL from a file / stdin / pipe can't be inspected; it may contain destructive statements."
      PATTERN="sql_from_file"
    fi
  fi
fi

# --- ORM / framework destructive migrations (EN09 B3) — exempt local test/dev ---
if [ -z "$WARN" ] && printf '%s' "$CMD_LOWER" | grep -qE '(prisma[[:space:]]+migrate[[:space:]]+reset|rails[[:space:]]+db:(drop|reset)|drizzle-kit[[:space:]]+push|sequelize[[:space:]]+db:drop|php[[:space:]]+artisan[[:space:]]+migrate:(fresh|reset)|alembic[[:space:]]+downgrade[[:space:]]+base)' 2>/dev/null; then
  if ! is_local_test_db "$CMD_LOWER"; then
    WARN="ORM destructive migration (reset / drop / fresh) can wipe the database."
    PATTERN="orm_destructive"
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
