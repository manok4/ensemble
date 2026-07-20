#!/usr/bin/env bash
# Tests for skills/en-guardrail/bin/check-guardrail.sh — exercise destructive
# pattern detection and safe-exception logic by feeding synthetic tool-input
# JSON on stdin and inspecting the JSON the hook returns.
#
# Each case asserts either:
#   ask    — hook returns {"permissionDecision":"ask",...}
#   allow  — hook returns {} (or empty)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-guardrail hook"

HOOK="$REPO_ROOT/skills/en-guardrail/bin/check-guardrail.sh"
[ -x "$HOOK" ] || { fail "hook script missing or not executable: $HOOK"; report; exit 1; }

# Pipe one synthetic Bash tool-input through the hook and assert the verdict.
check() {
  local label="$1" expect="$2" cmd="$3"
  local payload out
  payload=$(printf '{"tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')")
  out=$(printf '%s' "$payload" | bash "$HOOK")

  case "$expect" in
    ask)
      if echo "$out" | grep -q '"permissionDecision":"ask"'; then
        pass "[ask]   $label"
      else
        fail "[ask]   $label" "got: $out"
      fi
      ;;
    allow)
      if [ "$out" = "{}" ]; then
        pass "[allow] $label"
      else
        fail "[allow] $label" "got: $out"
      fi
      ;;
  esac
}

# --- Should ASK: classic destructive patterns ---
check "rm -rf /tmp/foo"                       ask   "rm -rf /tmp/foo"
check "DROP TABLE on remote host"             ask   "psql -h prod-db -d app -c 'DROP TABLE users'"
check "TRUNCATE on remote host"               ask   "psql -h staging-db -d app -c 'TRUNCATE orders'"
check "DELETE FROM without WHERE"             ask   "psql -c 'DELETE FROM users'"
check "git push --force"                      ask   "git push --force origin main"
check "git push -f"                           ask   "git push -f origin main"
check "git reset --hard"                      ask   "git reset --hard HEAD~3"
check "git restore ."                         ask   "git restore ."
check "git checkout ."                        ask   "git checkout ."
check "git branch -D"                         ask   "git branch -D feature/x"
check "git tag -d"                            ask   "git tag -d v1.0.0"
check "git worktree remove --force"           ask   "git worktree remove --force ../wt"
check "kubectl delete"                        ask   "kubectl delete pod foo"
check "docker system prune"                   ask   "docker system prune -a"
check "docker rm -f"                          ask   "docker rm -f my-container"
check "terraform destroy"                     ask   "terraform destroy -auto-approve"
check "aws s3 rm --recursive"                 ask   "aws s3 rm s3://bkt/ --recursive"
check "gcloud compute instances delete"       ask   "gcloud compute instances delete my-vm"

# --- Should ASK: localhost without test/dev DB name (only one signal) ---
check "DROP on localhost prod_db"             ask   "psql -h localhost -d production -c 'DROP TABLE users'"
check "DROP on staging-db with test name"     ask   "psql -h staging-db -d test_app -c 'DROP TABLE users'"

# --- Should ALLOW: build-artifact recursive rms ---
check "rm -rf node_modules"                   allow "rm -rf node_modules"
check "rm -rf dist"                           allow "rm -rf dist"
check "rm -rf .next"                          allow "rm -rf .next"
check "rm -rf .cache"                         allow "rm -rf .cache"
check "rm -rf coverage"                       allow "rm -rf coverage"

# --- Should ALLOW: localhost + test/dev DB exemption ---
check "DROP on localhost test_db"             allow "psql -h localhost -d test_app -c 'DROP TABLE users'"
check "TRUNCATE on @127.0.0.1/myapp_test"     allow "psql postgresql://app@127.0.0.1/myapp_test -c 'TRUNCATE orders'"
check "DELETE-no-WHERE on localhost dev_db"   allow "psql -h localhost -d dev_db -c 'DELETE FROM users'"

# --- Should ALLOW: DELETE WITH WHERE (not flagged) ---
check "DELETE WITH WHERE clause"              allow "psql -h prod-db -c 'DELETE FROM users WHERE id=1'"

# --- Should ALLOW: non-recursive single-file rm (intentionally not flagged) ---
check "single-file rm"                        allow "rm foo.ts"
check "rm with multiple files (no -r)"        allow "rm foo.ts bar.ts baz.ts"

# --- EN09 U3 (A3/F1): the inline command-prefix bypass NO LONGER works ---
# A model-writable prefix must not be able to self-exempt.
check "inline ENSEMBLE_GUARDRAIL=off (no bypass)"     ask "ENSEMBLE_GUARDRAIL=off rm -rf /tmp/foo"
check "inline ENSEMBLE_GUARDRAIL_BYPASS=on (no bypass)" ask "ENSEMBLE_GUARDRAIL_BYPASS=on rm -rf /tmp/foo"

# --- Should ALLOW: routine commands ---
check "git status"                            allow "git status"
check "ls -la"                                allow "ls -la"
check "echo hello"                            allow "echo hello"
check "git log"                               allow "git log --oneline -10"

# --- Should ALLOW: empty/missing command ---
empty_payload='{"tool_input":{}}'
empty_out=$(printf '%s' "$empty_payload" | bash "$HOOK")
if [ "$empty_out" = "{}" ]; then
  pass "[allow] empty tool_input"
else
  fail "[allow] empty tool_input" "got: $empty_out"
fi

# --- Regression: commands with escaped double quotes must still match ---
# A grep+sed extractor stops at the first \" and silently drops the destructive
# tail. These must trigger the matchers and ASK.
check "DROP TABLE inside double-quoted -c"  ask   'psql -h prod -d app -c "DROP TABLE users"'
check "git reset --hard inside bash -lc"    ask   'bash -lc "git reset --hard HEAD~3"'
check "rm -rf inside ssh -c"                ask   'ssh host "rm -rf /var/data"'
check "TRUNCATE inside double-quoted -c"    ask   'psql -h staging -c "TRUNCATE orders"'
check "DELETE-no-WHERE inside double quotes" ask  'psql -c "DELETE FROM users"'
check "kubectl delete inside double quotes" ask   'kubectl exec pod -- bash -c "kubectl delete pod foo"'

# Exemption preserved — escaped quotes around localhost+test DB still allow
check "DROP on localhost test_db (double-quoted)" allow 'psql -h localhost -d test_app -c "DROP TABLE users"'

# ===================================================================
# EN09 U1 — safe-exception is a POSITIVE allowlist (A1/F5)
# ===================================================================
# Absolute / home / shell-expansion / parent-escape targets must NEVER be
# exempted by the artifact allowlist — they fall through to the rm -r prompt.
check "rm -rf /build (absolute)"              ask   "rm -rf /build"
check "rm -rf ~/dist (home)"                  ask   "rm -rf ~/dist"
check 'rm -rf $HOME/.cache (home var)'        ask   'rm -rf $HOME/.cache'
check 'rm -rf ${HOME}/dist (brace expand)'    ask   'rm -rf ${HOME}/dist'
check 'rm -rf $PWD/dist (var expand)'         ask   'rm -rf $PWD/dist'
check 'rm -rf $(pwd)/dist (cmd subst)'        ask   'rm -rf $(pwd)/dist'
check "rm -rf ../dist (parent escape)"        ask   "rm -rf ../dist"
check "rm -rf /* (glob at root)"              ask   "rm -rf /*"
# Relative in-tree artifacts still exempt (regression).
check "rm -rf ./dist (relative)"              allow "rm -rf ./dist"
check "rm -rf build/ (trailing slash)"        allow "rm -rf build/"
check "rm -rf packages/app/node_modules"      allow "rm -rf packages/app/node_modules"
# A non-artifact relative path is NOT exempt.
check "rm -rf src (non-artifact)"             ask   "rm -rf src"

# EN09 U1 — non-recursive destructive deleters (A2)
check "find -delete"                          ask   "find . -name '*.log' -delete"
check "find -exec rm"                         ask   "find / -name x -exec rm {} +"
check "rsync --delete"                        ask   "rsync -a --delete src/ dst/"
check "shred"                                 ask   "shred -u secret.pem"
check "truncate -s 0"                         ask   "truncate -s 0 db.sqlite"
check "unlink"                                ask   "unlink important.sock"

# EN09 U1 — output-redirection truncation contract (A2/F9/F14).
# These need real filesystem state, so run the hook from a temp dir.
RTMP=$(mktemp -d)
( cd "$RTMP" && echo data > existing.log && ln -s existing.log inlink.log \
    && ln -s /etc/hosts outlink.log && ln -s nonexistent broken.log )
redir() {
  local label="$1" expect="$2" cmd="$3" out
  out=$(cd "$RTMP" && printf '{"tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')" \
    | bash "$HOOK")
  case "$expect" in
    ask)   echo "$out" | grep -q '"permissionDecision":"ask"' && pass "[ask]   $label" || fail "[ask]   $label" "got: $out" ;;
    allow) [ "$out" = "{}" ] && pass "[allow] $label" || fail "[allow] $label" "got: $out" ;;
  esac
}
redir "redirect creates a new file"           allow "echo x > newfile.log"
redir "redirect appends (>>)"                 allow "echo x >> existing.log"
redir "redirect truncates existing file"      ask   "echo x > existing.log"
redir "redirect via symlink to in-tree file"  ask   "echo x > inlink.log"
redir "redirect via symlink out of tree"      ask   "echo x > outlink.log"
redir "redirect via broken symlink"           ask   "echo x > broken.log"
redir "redirect target has expansion"         ask   'echo x > $DIR/out.log'
rm -rf "$RTMP"

# ===================================================================
# EN09 U2 — UPDATE without a top-level WHERE (B3/F7/F11)
# ===================================================================
check "UPDATE no WHERE (prod)"                ask   'psql -h prod.db -c "UPDATE users SET active=false"'
check "UPDATE WHERE only in comment"          ask   'psql -h prod.db -c "UPDATE users SET active=false -- reset WHERE nobody"'
check "UPDATE WHERE only in literal"          ask   "psql -h prod.db -c \"UPDATE users SET note='delete WHERE x'\""
check "UPDATE WHERE only in subquery"         ask   'psql -h prod.db -c "UPDATE users SET a=(SELECT e FROM d WHERE id=1)"'
check "UPDATE WHERE in later statement"       ask   'psql -h prod.db -c "UPDATE users SET x=1; SELECT * FROM t WHERE y=2"'
check "UPDATE scoped (top-level WHERE)"       allow 'psql -h prod.db -c "UPDATE users SET x=1 WHERE id=2"'
check "UPDATE no WHERE on localhost test"     allow 'psql -h localhost -d test_app -c "UPDATE u SET a=false"'

# EN09 U2 — SQL from a file / stdin / pipe against a non-local target (B1/F4)
check "psql -f file (prod)"                   ask   "psql -h prod.db -f migrate.sql"
check "psql --file= (prod)"                   ask   "psql -h prod.db --file=migrate.sql"
check "psql < redirect (prod)"                ask   "psql -h prod.db < migrate.sql"
check "cat file | psql (prod)"                ask   "cat migrate.sql | psql -h prod.db"
check "mysql < redirect (prod)"               ask   "mysql -h prod.db appdb < dump.sql"
check "psql -f on localhost test (exempt)"    allow "psql -h localhost -d appdev -f migrate.sql"

# EN09 U2 — ORM / framework destructive migrations (B3)
check "prisma migrate reset"                  ask   "prisma migrate reset --force"
check "rails db:drop"                         ask   "rails db:drop"
check "rails db:reset"                        ask   "rails db:reset"
check "drizzle-kit push"                      ask   "drizzle-kit push"
check "sequelize db:drop"                     ask   "npx sequelize db:drop"

# EN09 U2 — regressions (must NOT over-fire)
check "npm run update-deps (not SQL)"         allow "npm run update-deps"
check "DELETE WITH WHERE stays allow"         allow "psql -h prod-db -c 'DELETE FROM users WHERE id=1'"
check "plain SELECT with a file"              allow "psql -h localhost -d appdev -f query.sql"

# ===================================================================
# EN09 U3 — bypass is read ONLY from the hook's own process env (A3/F1)
# ===================================================================
# With the env var set on the HOOK PROCESS (as a human's shell export would do),
# a matched destructive command is allowed through.
env_out=$(printf '{"tool_input":{"command":"rm -rf /tmp/foo"}}' | ENSEMBLE_GUARDRAIL_BYPASS=on bash "$HOOK")
if [ "$env_out" = "{}" ]; then
  pass "[allow] hook-process env ENSEMBLE_GUARDRAIL_BYPASS=on bypasses"
else
  fail "[allow] hook-process env bypass" "got: $env_out"
fi
# Without it, the same command asks (regression: bypass is opt-in only).
noenv_out=$(printf '{"tool_input":{"command":"rm -rf /tmp/foo"}}' | bash "$HOOK")
if echo "$noenv_out" | grep -q '"permissionDecision":"ask"'; then
  pass "[ask]   no bypass env -> destructive command still asks"
else
  fail "[ask]   no bypass env" "got: $noenv_out"
fi
# A wrong value does not bypass.
wrong_out=$(printf '{"tool_input":{"command":"rm -rf /tmp/foo"}}' | ENSEMBLE_GUARDRAIL_BYPASS=yes bash "$HOOK")
if echo "$wrong_out" | grep -q '"permissionDecision":"ask"'; then
  pass "[ask]   ENSEMBLE_GUARDRAIL_BYPASS=yes (wrong value) does not bypass"
else
  fail "[ask]   wrong bypass value" "got: $wrong_out"
fi

# ===================================================================
# EN09 U4 — MCP DB-writing tools (B2). Full tool_name+tool_input JSON fed
# directly to the hook (no real DB is ever touched — side-effect-free, F13).
# ===================================================================
mcp() {
  local label="$1" expect="$2" payload="$3" out
  out=$(printf '%s' "$payload" | bash "$HOOK")
  case "$expect" in
    ask)   echo "$out" | grep -q '"permissionDecision":"ask"' && pass "[ask]   $label" || fail "[ask]   $label" "got: $out" ;;
    allow) [ "$out" = "{}" ] && pass "[allow] $label" || fail "[allow] $label" "got: $out" ;;
  esac
}
mcp "Neon run_sql DROP on prod project"       ask   '{"tool_name":"mcp__Neon__run_sql","tool_input":{"sql":"DROP TABLE users","project":"prod-app"}}'
mcp "Neon run_sql DROP on dev (remote=ask,F12)" ask '{"tool_name":"mcp__Neon__run_sql","tool_input":{"sql":"DROP TABLE users","project":"dev-sandbox"}}'
mcp "Neon run_sql plain SELECT"               allow '{"tool_name":"mcp__Neon__run_sql","tool_input":{"sql":"SELECT * FROM users","project":"prod"}}'
mcp "F2 spoof: localhost inside SQL comment"  ask   '{"tool_name":"mcp__Neon__run_sql","tool_input":{"sql":"DROP TABLE users -- localhost test","project":"prod"}}'
mcp "F6 conflict: local label + prod project" ask   '{"tool_name":"mcp__Neon__run_sql","tool_input":{"sql":"DROP TABLE users","label":"localhost-test","project":"prod-app"}}'
mcp "Neon params.sql nesting DROP"            ask   '{"tool_name":"mcp__Neon__run_sql","tool_input":{"params":{"sql":"DROP TABLE t","project":"prod"}}}'
mcp "Neon run_sql UPDATE no WHERE"            ask   '{"tool_name":"mcp__Neon__run_sql","tool_input":{"sql":"UPDATE users SET a=1","project":"prod"}}'
mcp "Postgres execute DROP on local test"     allow '{"tool_name":"mcp__Postgres__execute","tool_input":{"sql":"DROP TABLE users","connectionString":"postgres://localhost/appdev_test"}}'
mcp "Postgres execute DROP on prod host"      ask   '{"tool_name":"mcp__Postgres__execute","tool_input":{"sql":"DROP TABLE users","connectionString":"postgres://prod.rds.aws/app"}}'
mcp "F8 un-adapted write-name (fail closed)"  ask   '{"tool_name":"mcp__Foo__run_sql","tool_input":{"sql":"DROP TABLE x"}}'
mcp "F8 un-adapted write-name, no sql field"  ask   '{"tool_name":"mcp__Foo__apply_migration","tool_input":{"foo":"bar"}}'
mcp "F15 unrelated MCP tool not prompted"     allow '{"tool_name":"mcp__foo__read","tool_input":{"path":"/x"}}'
mcp "malformed MCP input fails closed"        ask   '{"tool_name":"mcp__Neon__run_sql","tool_input":"not-an-object"}'

report
