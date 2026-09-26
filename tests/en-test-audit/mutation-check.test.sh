#!/usr/bin/env bash
# tests/en-test-audit/mutation-check.test.sh
#
# ensemble-mutation-check turns "the keeper still catches it" into a measured
# result. It writes to the working tree, so half of what is asserted here is
# that the tree comes back byte for byte, including when the script is killed.
# The other half is that only the keeper failing counts: a red run from a
# syntax error, a sibling test or a timeout is inconclusive, never caught.
#
# Negative controls at authoring: removing the baseline run let the red-baseline
# scenario apply its patch; removing the --expect-in-baseline check let the
# name-only scenario report caught; treating a timeout as caught turned the
# hang scenario red; removing the trap left the TERM scenario's tree mutated.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
. "$SELF_DIR/lib.sh"
TEST_NAME="en-test-audit mutation check"

MC="$REPO_ROOT/skills/en-test-audit/scripts/ensemble-mutation-check"
[ -x "$MC" ] || { fail "missing or not executable: $MC"; report; exit 1; }

R=$(make_audit_repo)
P="$R/.git/patches"; mkdir -p "$P"
clean() { [ -z "$(cd "$R" && git status --porcelain)" ]; }
# mkpatch <name> <file> <new content> -> $P/<name>.diff, tree left clean
mkpatch() { (cd "$R" && printf '%s\n' "$3" > "$2" && git diff > "$P/$1.diff" && git checkout -q -- "$2"); }
mc() { (cd "$R" && "$MC" "$@" 2>&1); }

mkpatch minus src.sh 'add() { echo $(( $1 - $2 )); }'
mkpatch comment src.sh 'add() { echo $(( $1 + $2 )); }  # a comment'
mkpatch early src.sh 'exit 7'
mkpatch hang src.sh 'add() { while :; do :; done; }'

# --- caught, survived, inconclusive ---------------------------------------------
out=$(mc --patch "$P/minus.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 0 ] && clean \
  && pass "a mutation the keeper fails on, with its failure message, is caught; tree restored" \
  || fail "the + to - mutation must be caught" "rc=$rc out=$out"

out=$(mc --patch "$P/comment.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 1 ] && clean \
  && pass "a comment-only mutation survives (exit 1); tree restored" \
  || fail "a comment mutation must survive" "rc=$rc out=$out"

out=$(mc --patch "$P/early.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 5 ] && clean \
  && pass "red for an unrelated reason (the run dies before the keeper) is inconclusive, not caught" \
  || fail "a red run without the keeper's failure must be exit 5" "rc=$rc out=$out"

out=$(mc --patch "$P/hang.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers' --timeout 1); rc=$?
[ "$rc" -eq 5 ] && printf '%s' "$out" | grep -q 'timed out' && clean \
  && pass "a timed-out mutated run is inconclusive, not caught; tree restored" \
  || fail "a hang must be exit 5 with the tree restored" "rc=$rc out=$out"

# --- the keeper, not a sibling ----------------------------------------------------
(
  cd "$R" || exit 1
  cat > test.sh <<'EOF'
. ./src.sh
pass() { echo "ok $1"; }
fail() { echo "FAIL $1"; exit 1; }
[ "$(add 2 3)" = 5 ] && pass "adds two numbers" || fail "adds two numbers"
[ "$(add 0 0)" = 0 ] && pass "zero is zero" || fail "zero is zero"
EOF
  git commit -qam sibling
)
mkpatch zero src.sh 'add() { [ "$1" = 0 ] && echo 1 || echo $(( $1 + $2 )); }'
out=$(mc --patch "$P/zero.diff" --test 'sh test.sh' --expect 'adds two numbers'); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qi 'baseline' && clean \
  && pass "--expect text that a passing run prints is refused as not failure-specific" \
  || fail "a name-only --expect must be refused" "rc=$rc out=$out"
out=$(mc --patch "$P/zero.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 5 ] && clean \
  && pass "only a sibling failing, with the keeper green, is inconclusive" \
  || fail "a sibling-only failure must be exit 5" "rc=$rc out=$out"
(cd "$R" && git reset -q --hard HEAD~1)

# --- refusals ----------------------------------------------------------------------
(cd "$R" && printf 'add() { echo 0; }\n' > src.sh && git commit -qam red)
mkpatch redcomment src.sh 'add() { echo 0; }  # c'
out=$(mc --patch "$P/redcomment.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 3 ] && clean \
  && pass "a red baseline exits 3 and the patch is never applied" \
  || fail "a red baseline must exit 3" "rc=$rc out=$out"
(cd "$R" && git reset -q --hard HEAD~1)

echo '# local edit' >> "$R/src.sh"
out=$(mc --patch "$P/minus.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 2 ] && [ "$(tail -1 "$R/src.sh")" = '# local edit' ] \
  && pass "a target with uncommitted changes is refused and left untouched" \
  || fail "a dirty target must be refused" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- src.sh)

printf 'not a patch\n' > "$P/junk.diff"
out=$(mc --patch "$P/junk.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 2 ] && clean && pass "a patch that does not apply is refused" || fail "a junk patch must exit 2" "rc=$rc out=$out"

out=$(mc --patch "$P/minus.diff" --test 'sh test.sh'); rc=$?
[ "$rc" -eq 2 ] && clean && pass "--expect is required" || fail "a missing --expect must exit 2" "rc=$rc out=$out"

# --- killed mid-run -----------------------------------------------------------------
(cd "$R" && exec "$MC" --patch "$P/hang.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers' --timeout 60 >/dev/null 2>&1) &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.3
  (cd "$R" && git diff --quiet) || break     # the mutation is applied
done
kill -TERM "$pid" 2>/dev/null
wait "$pid" 2>/dev/null; rc=$?
[ "$rc" -ne 0 ] && clean \
  && pass "killed with TERM while the mutated test runs, it restores the tree" \
  || fail "TERM mid-run must restore the tree" "rc=$rc status=$(cd "$R" && git status --porcelain)"

rm -rf "$R"
report
