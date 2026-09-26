# tests/en-test-audit/lib.sh — a throwaway repo shaped like a project the skill audits.
#
# Sourced, not run. Every en-test-audit script test drives the real script
# against one of these, so what is asserted is exit codes, output lines and the
# repo state afterwards, the only surface the skill itself ever sees.

# make_audit_repo -> prints the repo path. On branch `audit`, one commit on
# `main` before it, clean tree. src.sh defines add(); test.sh checks it and
# prints `FAIL adds two numbers` when it breaks.
make_audit_repo() {
  local tmp; tmp=$(mktemp -d)
  (
    cd "$tmp" || exit 1
    git init -q -b main
    git config user.email t@t
    git config user.name t
    printf -- '- **Test:** `sh test.sh`\n' > AGENTS.md
    printf 'add() { echo $(( $1 + $2 )); }\n' > src.sh
    cat > test.sh <<'EOF'
. ./src.sh
pass() { :; }
fail() { echo "FAIL $1"; exit 1; }
[ "$(add 2 3)" = 5 ] && pass "adds two numbers" || fail "adds two numbers"
EOF
    git add . && git commit -q -m init
    git switch -q -c audit
  ) || return 1
  printf '%s' "$tmp"
}
