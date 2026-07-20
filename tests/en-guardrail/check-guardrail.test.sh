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

# --- Should ALLOW: per-command bypass ---
check "ENSEMBLE_GUARDRAIL=off rm -rf"         allow "ENSEMBLE_GUARDRAIL=off rm -rf /tmp/foo"

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

report
