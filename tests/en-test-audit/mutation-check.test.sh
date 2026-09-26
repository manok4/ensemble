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
# After the EN21 branch review: reading quoted numstat output, removing the
# restore check, and keeping a stale receipt each turned its scenario red.

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

# --- receipts ---------------------------------------------------------------------
rm -f "$P"/*.caught
mc --patch "$P/minus.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers' >/dev/null
rc=$?
if [ "$rc" -eq 0 ] && grep -q '"result": "caught"' "$P/minus.diff.caught" \
   && grep -qF "\"patch\": \"$(git hash-object "$P/minus.diff")\"" "$P/minus.diff.caught"; then
  pass "a caught run writes a receipt keyed to the patch's blob id"
else
  fail "a caught run must write <patch>.caught naming the patch" "rc=$rc $(cat "$P/minus.diff.caught" 2>&1)"
fi
cp "$P/comment.diff" "$P/flip.diff"; echo '{"result": "caught"}' > "$P/flip.diff.caught"
mc --patch "$P/flip.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers' >/dev/null; rc=$?
[ "$rc" -eq 1 ] && [ ! -e "$P/flip.diff.caught" ] \
  && pass "a run that does not catch removes any earlier receipt for the patch" \
  || fail "a survived run must not leave a receipt behind" "rc=$rc"

# --- staged changes are fine, unstaged and untracked are not ------------------------
(cd "$R" && echo '# staged by the batch' >> src.sh && git add src.sh)
mkpatch staged src.sh "$(cd "$R" && cat src.sh | sed 's/+ \$2/- $2/')"
(cd "$R" && git add src.sh)
staged_before=$(cd "$R" && git diff --cached)
out=$(mc --patch "$P/staged.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 0 ] && [ "$(cd "$R" && git diff --cached)" = "$staged_before" ] && (cd "$R" && git diff --quiet) \
  && pass "a target with only staged changes is mutated and restored to exactly the staged content" \
  || fail "staged-only targets must be allowed and restored" "rc=$rc out=$out"
(cd "$R" && git reset -q --hard HEAD)

(cd "$R" && printf 'x\n' > loose.sh)
printf -- '--- a/loose.sh\n+++ b/loose.sh\n@@ -1 +1 @@\n-x\n+y\n' > "$P/loose.diff"
out=$(mc --patch "$P/loose.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'untracked: loose.sh' && [ "$(cat "$R/loose.sh")" = x ] \
  && pass "an untracked target is refused, since git could not restore it" \
  || fail "an untracked target must be refused" "rc=$rc out=$out"
rm -f "$R/loose.sh"

# --- a non-ASCII target is dirty-checked and restore-checked like any other ----------
(cd "$R" && printf 'add() { echo $(( $1 + $2 )); }\n' > café.sh && sed -i.bak 's#\./src\.sh#./café.sh#' test.sh && rm test.sh.bak \
   && git add café.sh test.sh && git commit -qm unicode)
mkpatch cafe café.sh 'add() { echo $(( $1 - $2 )); }'
out=$(mc --patch "$P/cafe.diff" --test 'sh test.sh' --expect 'FAIL adds two numbers'); rc=$?
[ "$rc" -eq 0 ] && clean && pass "a mutation on a non-ASCII path is caught and restored" || fail "a non-ASCII target must work" "rc=$rc out=$out"
# The test itself edits the target while failing, so the reverse cannot apply.
out=$(mc --patch "$P/cafe.diff" --test 'sh test.sh || { echo junk >> café.sh; exit 1; }' --expect 'FAIL adds two numbers' 2>&1); rc=$?
[ "$rc" -eq 4 ] && printf '%s' "$out" | grep -q 'caf' && ! clean \
  && pass "a restore that cannot put the file back is exit 4, naming it, never 'caught'" \
  || fail "a failed restore must be exit 4" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- . && git reset -q --hard HEAD~1)

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
