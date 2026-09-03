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

# ===================================================================
# EN09 branch-review bypasses (CR1-CR6) — each must now be closed.
# ===================================================================
# CR2: rm option ordering + compound commands
check "rm -f -r absolute (option order)"      ask   "rm -f -r /important"
check "rm --force --recursive absolute"       ask   "rm --force --recursive /important"
check "compound rm: destructive then safe"    ask   "rm -rf /important; rm -rf dist"
check "compound rm: safe then destructive"    ask   "rm -rf node_modules && rm -rf ~/data"
check "compound both-safe still allowed"      allow "rm -rf node_modules && rm -rf dist"
# CR1: spoofed localhost host must NOT exempt
check "spoof host localhost.example.com"      ask   "psql -h localhost.example.com -d app_test -c 'DROP TABLE users'"
mcp "MCP spoof host localhost.example.com"    ask   '{"tool_name":"mcp__Postgres__execute","tool_input":{"sql":"DROP TABLE users","connectionString":"postgres://localhost.example.com/app_test"}}'
# CR4: quoted / aliased UPDATE table
check "UPDATE quoted table no WHERE"          ask   'psql -h prod -c "UPDATE \"users\" SET active=false"'
check "UPDATE aliased table no WHERE"         ask   'psql -h prod -c "UPDATE users u SET u.active=false"'
# CR5: piped SQL through a wrapper, and compact input redirection
check "piped SQL through env wrapper"         ask   "cat migrate.sql | env DATABASE_URL=x psql -h prod"
check "piped SQL through timeout wrapper"     ask   "cat migrate.sql | timeout 30 psql -h prod"
check "compact input redirection <file"       ask   "psql -h prod <migrate.sql"
# CR6: MCP scoped DELETE/UPDATE should NOT prompt (matches the documented contract)
mcp "MCP scoped DELETE (WHERE) allowed"       allow '{"tool_name":"mcp__Postgres__execute","tool_input":{"sql":"DELETE FROM users WHERE id=1","connectionString":"postgres://prod/app"}}'
mcp "MCP scoped UPDATE (WHERE) allowed"       allow '{"tool_name":"mcp__Postgres__execute","tool_input":{"sql":"UPDATE users SET x=1 WHERE id=2","connectionString":"postgres://prod/app"}}'
mcp "MCP unscoped DELETE prompts"             ask   '{"tool_name":"mcp__Postgres__execute","tool_input":{"sql":"DELETE FROM users","connectionString":"postgres://prod/app"}}'

# CR3: quoted redirection target with a space — must see the real existing file.
# Use an absolute path so the check is independent of the hook's cwd.
CRTMP=$(mktemp -d)
printf data > "$CRTMP/important file"
crpayload=$(printf 'echo x > "%s/important file"' "$CRTMP" \
  | python3 -c 'import sys,json; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')
crredir_out=$(printf '%s' "$crpayload" | bash "$HOOK")
if echo "$crredir_out" | grep -q '"permissionDecision":"ask"'; then
  pass "[ask]   CR3 quoted redirection truncates existing 'important file'"
else
  fail "[ask]   CR3 quoted redirection" "got: $crredir_out"
fi
rm -rf "$CRTMP"

# =============================================================================
# EN09 bypass-class regression suite
# =============================================================================
# check-guardrail.sh's own header names six classes that bash-regex parsing
# could not handle, and that moving the logic into guardrail_analyze.py fixed:
#
#   rm option ordering · compound commands · quoted redirection ·
#   spoofable localhost substrings · quoted/aliased UPDATE tables ·
#   SQL piped through wrappers
#
# Until now the suite tested canonical forms — `rm -rf /tmp/foo`,
# `git push --force`. Those pass whether or not the parsing is real. Each class
# below is a way to look different while doing the same thing, so each gets a
# fixture: a refactor of the analyzer that reopened any one of them would
# otherwise land green.
#
# These were confirmed passing against the analyzer as it stands. They are
# recorded here so that stays true, not to describe a fix still to make.

# --- class 1: rm option ordering ---------------------------------------------
# A regex anchored on the literal "-rf" misses four of these five.
check "EN09-B1 rm -rf"                    ask "rm -rf /var/data"
check "EN09-B1 rm -fr (reversed)"         ask "rm -fr /var/data"
check "EN09-B1 rm -r -f (split)"          ask "rm -r -f /var/data"
check "EN09-B1 rm -f -r (split, other order)" ask "rm -f -r /var/data"
check "EN09-B1 rm --recursive --force"    ask "rm --recursive --force /var/data"

# --- class 2: compound commands ----------------------------------------------
# The destructive verb is not the first word, so a command-prefix match misses it.
check "EN09-B2 && chain"                  ask "ls && rm -rf /var/data"
check "EN09-B2 ; sequence"                ask "echo hi; rm -rf /var/data"
check "EN09-B2 || fallback"               ask "true || rm -rf /var/data"
check "EN09-B2 cd then delete"            ask "cd /tmp && rm -rf /var/data"

# --- class 3: the artifact exemption is a positive allowlist -----------------
# The exemption is the most dangerous rule in the file: a "safe" artifact name
# must never greenlight a delete outside the tree. Only a plain in-tree relative
# path may pass, so every escape shape gets a fixture.
check "EN09-B3 in-tree node_modules"      allow "rm -rf node_modules"
check "EN09-B3 in-tree ./dist"            allow "rm -rf ./dist"
check "EN09-B3 absolute /dist"            ask   "rm -rf /dist"
check "EN09-B3 home ~/dist"               ask   "rm -rf ~/dist"
check "EN09-B3 \$HOME/dist"               ask   "rm -rf \$HOME/dist"
check "EN09-B3 \${HOME}/dist"             ask   "rm -rf \${HOME}/dist"
check "EN09-B3 parent-escaping ../dist"   ask   "rm -rf ../dist"
check "EN09-B3 command-substituted pwd"   ask   "rm -rf \$(pwd)/dist"
check "EN09-B3 glob /*"                   ask   "rm -rf /*"

# --- class 4: localhost cannot be spoofed from SQL text ----------------------
# The exemption is decided from the connection target, never from the statement.
# A remote host stays remote however the SQL is worded.
check "EN09-B4 keywords in a trailing comment" ask \
  "psql -h prod.example.com -d app -c \"DROP TABLE users -- localhost test\""
check "EN09-B4 keywords in the table name"     ask \
  "psql -h prod -d app -c 'DROP TABLE localhost_test'"
check "EN09-B4 test db name on a remote host"  ask \
  "psql -h staging-db -d test_app -c 'DROP TABLE users'"
# ...and a genuinely local target still exempts, or the rule is just "always ask".
check "EN09-B4 real localhost + test db"       allow \
  "psql -h localhost -d test_app -c 'DROP TABLE users'"
check "EN09-B4 real 127.0.0.1 + _test db"      allow \
  "psql postgresql://app@127.0.0.1/myapp_test -c 'TRUNCATE orders'"

# --- class 5: UPDATE scope is structural, not textual ------------------------
# A WHERE inside a subquery does not scope the UPDATE, and a WHERE inside a
# comment does not exist. Both need parsing; neither survives substring search.
check "EN09-B5 unscoped UPDATE"           ask   "psql -h prod -c 'UPDATE users SET active=false'"
# Both directions, because depth is the whole point. A WHERE at depth 0 scopes
# the UPDATE even when a subquery sits inside it; a WHERE that exists ONLY inside
# a subquery scopes nothing. My first draft asserted the opposite on the first of
# these — a wrong expectation in a security test is worse than no test, since it
# would have been "fixed" by making the analyzer over-prompt.
check "EN09-B5 top-level WHERE, subquery inside" allow \
  "psql -h prod -c 'UPDATE users SET a=1 WHERE id IN (SELECT id FROM t)'"
check "EN09-B5 WHERE only inside a subquery"     ask \
  "psql -h prod -c 'UPDATE users SET a=(SELECT x FROM t WHERE id=1)'"
check "EN09-B5 WHERE only in a comment"   ask   "psql -h prod -c \"UPDATE users SET a=1 -- WHERE id=2\""
check "EN09-B5 quoted + aliased table"    ask   "psql -h prod -c 'UPDATE \"users\" AS u SET a=1'"

# --- class 6: the bypass is human-only ---------------------------------------
# An agent must not be able to exempt itself from inside a command. A
# VAR=value prefix scopes one subprocess and cannot reach the hook's own
# environment; an export in a chained command cannot either.
check "EN09-B6 retired inline prefix"     ask "ENSEMBLE_GUARDRAIL=off rm -rf /var/data"
check "EN09-B6 inline bypass prefix"      ask "ENSEMBLE_GUARDRAIL_BYPASS=on rm -rf /var/data"
check "EN09-B6 export then chain"         ask "export ENSEMBLE_GUARDRAIL_BYPASS=on && rm -rf /var/data"

report
