#!/usr/bin/env bash
# tests/en-test-audit/ledger-verify.test.sh
#
# ensemble-test-ledger-verify is what stands between an agent's "I marked it D
# with evidence" and a commit. /en-test-audit commits only on its exit 0, so
# every rule here is a deletion that would otherwise land unjustified.
#
# Scenarios build a throwaway repo (tests/en-test-audit/lib.sh) whose baseline
# commit holds test.sh with `pass "adds two numbers"` and `pass "rejects
# letters"`, then write ledgers against it.
#
# Negative controls at authoring: disabling the D-row evidence rule, the
# baseline-existence check, the comment-line rejection and the campaign
# full-coverage rule each turned its scenario red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
. "$SELF_DIR/lib.sh"
TEST_NAME="en-test-audit ledger verifier"

LV="$REPO_ROOT/skills/en-test-audit/scripts/ensemble-test-ledger-verify"
[ -x "$LV" ] || { fail "missing or not executable: $LV"; report; exit 1; }

R=$(make_audit_repo)
(
  cd "$R" || exit 1
  cat >> test.sh <<'EOF'
case "$(add a 1 2>/dev/null)" in '') pass "rejects letters" ;; *) pass "rejects letters" ;; esac
EOF
  printf 'pass "covers addition"\n' > keeper.sh
  printf 'pass "old one"\n' > old.test.sh
  git add . && git commit -qm baseline
)
BASE=$(cd "$R" && git rev-parse HEAD)
LD="$R/docs/test-audits"; mkdir -p "$LD/m"; echo diff > "$LD/m/a.diff"; echo diff > "$LD/m/b.diff"

# ledger <mode> <preservation or ""> <rows...> ; extra frontmatter via $EXTRA_FM,
# extra sections via $EXTRA_BODY. Writes $LD/l.md.
ledger() {
  local mode="$1" pres="$2"; shift 2
  {
    echo "---"; echo "type: test-audit"; echo "mode: $mode"; echo "scope: ."
    echo 'test_glob: "*.test.sh"'; echo "baseline_sha: $BASE"; echo "created: 2026-09-26"
    [ -n "$pres" ] && echo "preservation_review: $pres"
    [ -n "${EXTRA_FM:-}" ] && printf '%s\n' "$EXTRA_FM"
    echo "---"; echo; echo "## Ledger"; echo
    echo "| Test | Mark | Keeper or contract | Evidence | Mutation |"
    echo "|---|---|---|---|---|"
    for row in "$@"; do echo "$row"; done
    [ -n "${EXTRA_BODY:-}" ] && printf '\n%s\n' "$EXTRA_BODY"
  } > "$LD/l.md"
}
verify() { "$LV" "$LD/l.md" "$@" 2>&1; }

GOOD_R='| test.sh::adds two numbers | R | addition, public | only test of add | - |'
GOOD_F='| test.sh::rejects letters | F | input validation | asserted nothing, now checks empty | m/a.diff |'
GOOD_C='| test.sh::adds two numbers | C | keeper.sh::covers addition | same contract | m/b.diff |'
GOOD_D='| old.test.sh | D | none: exercises a deleted export | export removed | - |'

# --- structure ------------------------------------------------------------------
ledger batch cross-agent "$GOOD_R" "$GOOD_F" "$GOOD_C" "$GOOD_D"
out=$(verify); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] \
  && pass "one valid row of each mark passes silently" \
  || fail "a valid ledger must pass silently" "rc=$rc out=$out"

ledger batch cross-agent '| old.test.sh | D | none: duplicate | | - |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ] \
   && printf '%s' "$out" | grep -q '^ledger: old.test.sh: .*evidence' \
  && pass "a D row with no evidence is one violation, naming the row" \
  || fail "a D row with no evidence must fail" "rc=$rc out=$out"

ledger batch cross-agent '| test.sh::adds two numbers | C | none: duplicate | same | m/b.diff |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qi 'keeper' \
  && pass "a C row needs a real keeper, not none:" \
  || fail "a C row with keeper none: must fail" "rc=$rc out=$out"

ledger batch cross-agent '| test.sh::rejects letters | F | input validation | tightened | - |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qi 'mutation' \
  && pass "an F row needs a mutation" \
  || fail "an F row without a mutation must fail" "rc=$rc out=$out"

ledger batch cross-agent '| test.sh::rejects letters | F | input validation | tightened | m/missing.diff |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'm/missing.diff' \
  && pass "a mutation path that does not exist fails, and is named" \
  || fail "a missing mutation file must fail" "rc=$rc out=$out"

ledger batch cross-agent '| old.test.sh | X | whatever | because | - |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qi 'mark' \
  && pass "an unknown mark fails" \
  || fail "mark X must fail" "rc=$rc out=$out"

ledger batch cross-agent '| old.test.sh | D | none: dup | | - |' '| old.test.sh | X | a | b | - |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 2 ] \
  && pass "every violation is reported, not just the first" \
  || fail "two broken rows must give two lines" "rc=$rc out=$out"

ledger batch "" "$GOOD_R"
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'preservation_review' \
  && pass "a ledger that does not say what reviewed it fails" \
  || fail "missing preservation_review must fail" "rc=$rc out=$out"

printf -- '---\ntype: test-audit\n---\n\nno table here\n' > "$LD/l.md"
out=$(verify); rc=$?
[ "$rc" -eq 2 ] && pass "no Ledger heading is malformed (exit 2)" || fail "no Ledger heading must exit 2" "rc=$rc out=$out"

ledger batch cross-agent "$GOOD_R"; sed -i.bak 's/| Keeper or contract |/| Keeper |/' "$LD/l.md"; rm -f "$LD/l.md.bak"
out=$(verify); rc=$?
[ "$rc" -eq 2 ] && pass "a wrong column header is malformed (exit 2)" || fail "a wrong header must exit 2" "rc=$rc out=$out"

ledger batch cross-agent '| old.test.sh | D | none: a | b | c | - |'
out=$(verify); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'old.test.sh' \
  && pass "a row with a pipe inside a cell is malformed, and named" \
  || fail "a six-cell row must exit 2" "rc=$rc out=$out"

out=$("$LV" "$LD/nope.md" 2>&1); rc=$?
[ "$rc" -eq 2 ] && pass "a missing ledger exits 2" || fail "a missing ledger must exit 2" "rc=$rc"

# --- --tree: declarations against the baseline and the working tree ----------------
ledger batch cross-agent '| test.sh::adds two numbers | D | keeper.sh::covers addition | keeper covers it | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'still' \
  && pass "a D declaration still in the tree fails" \
  || fail "a D declaration still present must fail" "rc=$rc out=$out"

(cd "$R" && sed -i.bak 's/.*pass "adds two numbers".*/# pass "adds two numbers" moved to keeper.sh/' test.sh && rm test.sh.bak)
out=$(verify --tree); rc=$?
[ "$rc" -eq 0 ] \
  && pass "once removed it passes, and the name left in a comment is not a declaration" \
  || fail "a declaration left only in a comment must count as gone" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- test.sh)

ledger batch cross-agent '| test.sh::no such test | D | none: typo | x | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qi 'baseline' \
  && pass "a name not found at baseline fails closed" \
  || fail "an unknown declaration must fail against baseline" "rc=$rc out=$out"

ledger batch cross-agent '| test.sh::adds two numbers | C | nokeeper.sh::covers addition | same | m/b.diff |'
(cd "$R" && sed -i.bak '/adds two numbers/d' test.sh && rm test.sh.bak)
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'nokeeper.sh' \
  && pass "a C row whose keeper is absent fails" \
  || fail "an absent keeper must fail" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- test.sh)

ledger batch cross-agent "$GOOD_D"
(cd "$R" && rm old.test.sh)
out=$(verify --tree); rc=$?
[ "$rc" -eq 0 ] && pass "a whole-file D row passes once the file is gone" || fail "a removed whole file must pass" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- old.test.sh)
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && pass "a whole-file D row fails while the file remains" || fail "a present whole file must fail" "rc=$rc out=$out"
ledger batch cross-agent '| never.test.sh | D | none: x | y | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qi 'baseline' \
  && pass "a whole-file row for a file absent at baseline fails" \
  || fail "a whole file absent at baseline must fail" "rc=$rc out=$out"

# --- campaign ----------------------------------------------------------------------
(
  cd "$R" || exit 1
  mkdir -p tests
  printf 'pass "one"\npass "two"\n' > tests/a.test.sh
  printf 'pass "keeps order"\n' > tests/b.test.sh
  git add . && git commit -qm campaign-baseline
)
BASE=$(cd "$R" && git rev-parse HEAD)
LANES_BOTH=$'## Lanes\n\n| Lane | Files |\n|---|---|\n| one | tests/a.test.sh |\n| two | tests/b.test.sh |'
cscope() { sed -i.bak 's#^scope: .#scope: tests#' "$LD/l.md"; rm -f "$LD/l.md.bak"; }
A1='| tests/a.test.sh::one | R | one | keep | - |'
A2='| tests/a.test.sh::two | R | two | keep | - |'
B1='| tests/b.test.sh | R | order | keep | - |'

EXTRA_BODY=$'## Lanes\n\n| Lane | Files |\n|---|---|\n| one | tests/a.test.sh |'
ledger campaign cross-agent "$A1" "$A2" "$B1"; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'tests/b.test.sh' \
  && pass "a test file in no lane fails, and is named" \
  || fail "an unlaned file must fail" "rc=$rc out=$out"

EXTRA_BODY="$LANES_BOTH"$'\n| three | tests/a.test.sh |'
ledger campaign cross-agent "$A1" "$A2" "$B1"; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'tests/a.test.sh' \
  && pass "a file in two lanes fails" \
  || fail "a doubly-laned file must fail" "rc=$rc out=$out"

EXTRA_BODY="$LANES_BOTH"
ledger campaign cross-agent "$A1" "$A2"; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'tests/b.test.sh' \
  && pass "a laned file with no ledger row fails" \
  || fail "a file with no row must fail" "rc=$rc out=$out"

ledger campaign cross-agent "$A1" "$B1"; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'tests/a.test.sh::two' \
  && pass "an unlisted declaration fails, by full coverage" \
  || fail "a missing declaration row must fail" "rc=$rc out=$out"
ledger campaign cross-agent '| tests/a.test.sh | R | both | keep | - |' "$B1"; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 0 ] && pass "a whole-file row covers every declaration in it" || fail "a whole-file row must cover the file" "rc=$rc out=$out"

EXTRA_BODY="$LANES_BOTH"$'\n\n## Product defects\n\n| Defect | Fix commit | Control evidence |\n|---|---|---|\n| rounding | abc123 | |'
ledger campaign cross-agent "$A1" "$A2" "$B1"; cscope
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qi 'control' \
  && pass "a product defect with no control evidence fails" \
  || fail "an empty control cell must fail" "rc=$rc out=$out"

# --- rebaseline ----------------------------------------------------------------------
OLD=$BASE
(
  cd "$R" || exit 1
  printf 'pass "keeps order"  # now checks reverse too\n' > tests/b.test.sh
  printf 'pass "one"\npass "two"\npass "three"\n' > tests/a.test.sh
  git commit -qam main-moved
)
BASE=$(cd "$R" && git rev-parse HEAD)
EXTRA_BODY="$LANES_BOTH"; EXTRA_FM="rebaselined_from: $OLD"
A3='| tests/a.test.sh::three | R | three | reconciled: added on main | - |'
ledger campaign cross-agent "$A1" "$A2" "$A3" "$B1"; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'tests/b.test.sh' && ! printf '%s' "$out" | grep -q 'tests/a.test.sh' \
  && pass "a file main changed with no reconciled: row fails" \
  || fail "a changed file must need a reconciled row" "rc=$rc out=$out"
ledger campaign cross-agent "$A1" "$A2" "$A3" '| tests/b.test.sh | R | order | reconciled: reverse check added | - |'; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 0 ] && pass "with a reconciled: row per changed file, the rebaselined ledger passes" \
  || fail "a reconciled ledger must pass" "rc=$rc out=$out"
ledger campaign cross-agent "$A1" "$A2" '| tests/b.test.sh | R | order | reconciled: x | - |'; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'tests/a.test.sh::three' \
  && pass "a declaration main added with no row fails" \
  || fail "main's new declaration must need a row" "rc=$rc out=$out"
EXTRA_FM=""; EXTRA_BODY=""

rm -rf "$R"
report
