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
# full-coverage rule each turned its scenario red. After the EN21 branch review:
# an empty pathspec for scope '.', a reconcile that only checks new names,
# dropping the R/F still-present check, allowing paths outside the repo, passing
# rebaselined_from to git unvalidated, skipping the staged-evidence check, and
# requiring test_glob only in campaigns each turned its scenario red.

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
# What ensemble-mutation-check writes on a caught run, keyed to the patch's blob id.
receipt() { printf '{"result": "caught", "patch": "%s"}\n' "$(git hash-object "$1")" > "$1.caught"; }
receipt "$LD/m/a.diff"; receipt "$LD/m/b.diff"

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
# The skill verifies with --tree just before the commit, with its evidence staged.
verify() {
  case " $* " in *" --tree "*) (cd "$R" && git add -A docs) ;; esac
  "$LV" "$LD/l.md" "$@" 2>&1
}

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

# --- rules each mark carries, without --tree ------------------------------------------
for row in '| old.test.sh | D | - | removed | - |' '| old.test.sh | D | none: | removed | - |' '| old.test.sh | D | foo | removed | - |'; do
  ledger batch cross-agent "$row"
  out=$(verify); rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'D row needs a keeper' \
    && pass "a D row keeper of '$(printf '%s' "$row" | cut -d'|' -f4 | xargs)' is refused" \
    || fail "a D row needs <path>::<name> or none: <reason>" "row=$row rc=$rc out=$out"
done
ledger batch cross-agent '| test.sh::adds two numbers | R | | kept | - |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'must name the contract' \
  && pass "an R row with no contract fails" || fail "an R row must name its contract" "rc=$rc out=$out"
ledger batch cross-agent "$GOOD_R"; sed -i.bak '/^mode: /d' "$LD/l.md"; rm -f "$LD/l.md.bak"
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'mode is required' \
  && pass "frontmatter without mode fails" || fail "a missing mode must fail" "rc=$rc out=$out"

# --- mutation receipts ------------------------------------------------------------------
echo diff > "$LD/m/c.diff"
ledger batch cross-agent '| test.sh::rejects letters | F | input validation | tightened | m/c.diff |'
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no caught receipt' \
  && pass "a mutation diff with no caught receipt fails: a file alone proves nothing ran" \
  || fail "a receipt-less mutation must fail" "rc=$rc out=$out"
receipt "$LD/m/c.diff"; echo 'edited after the check' >> "$LD/m/c.diff"
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not a caught run of this patch' \
  && pass "a receipt for a different version of the patch fails" \
  || fail "a receipt must match the patch it names" "rc=$rc out=$out"
receipt "$LD/m/c.diff"; out=$(verify); rc=$?
[ "$rc" -eq 0 ] && pass "a receipt matching the patch passes" || fail "a matching receipt must pass" "rc=$rc out=$out"

ledger batch cross-agent "$GOOD_R"; sed -i.bak '/^test_glob: /d' "$LD/l.md"; rm -f "$LD/l.md.bak"
out=$(verify); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'test_glob is required' \
  && pass "a batch ledger without test_glob fails, since removals elsewhere would go unseen" \
  || fail "test_glob must be required in batch mode" "rc=$rc out=$out"

# What --tree checks is what the commit will carry: evidence edited after staging fails.
(cd "$R" && sed -i.bak '/adds two numbers/d' test.sh && rm test.sh.bak)
ledger batch cross-agent '| test.sh::adds two numbers | C | keeper.sh::covers addition | same | m/c.diff |'
(cd "$R" && git add -A docs)
echo ' ' >> "$LD/m/c.diff.caught"
out=$("$LV" "$LD/l.md" --tree 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'm/c.diff.caught: not staged as verified' \
  && pass "a receipt that differs from its staged copy fails: the commit would not carry what was checked" \
  || fail "unstaged evidence must fail --tree" "rc=$rc out=$out"
receipt "$LD/m/c.diff"; (cd "$R" && git checkout -q -- test.sh)

# --- every removal has a row; retained tests are still there ------------------------------
ledger batch cross-agent "$GOOD_R"
(cd "$R" && sed -i.bak '/pass "adds two numbers"/d' test.sh && rm test.sh.bak)
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'R row, but the declaration is gone' \
  && pass "an R row whose test was deleted anyway fails" \
  || fail "a retained test that vanished must fail" "rc=$rc out=$out"
ledger batch cross-agent '| test.sh::rejects letters | R | validation | kept | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'test.sh::adds two numbers: declaration removed since baseline without a D or C row' \
  && pass "a declaration removed from a judged file with no row fails" \
  || fail "an unrecorded removal in a judged file must fail" "rc=$rc out=$out"
ledger batch cross-agent '| test.sh | R | addition | kept whole | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'whole-file R row, but declarations were removed' \
  && pass "a whole-file R row over a file that lost a declaration fails" \
  || fail "a whole-file R row must not cover a removal" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- test.sh)
(cd "$R" && sed -i.bak '/old one/d' old.test.sh && rm old.test.sh.bak)
ledger batch cross-agent "$GOOD_R"
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'old.test.sh::old one' \
  && pass "a test removed from a changed test file the ledger never mentions fails" \
  || fail "an unmentioned test file's removal must fail" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- old.test.sh)

# --- keepers --------------------------------------------------------------------------
(cd "$R" && sed -i.bak '/adds two numbers/d' test.sh && rm test.sh.bak)
ledger batch cross-agent '| test.sh::adds two numbers | C | keeper.sh::no such keeper | same | m/b.diff |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'keeper keeper.sh::no such keeper is not in the tree' \
  && pass "a keeper file that exists but lacks the named declaration fails" \
  || fail "the keeper's declaration, not just its file, must exist" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- test.sh)

# --- duplicate names -------------------------------------------------------------------
(
  cd "$R" || exit 1
  printf 'pass "works"\npass "works"\n' > dup.test.sh && git add dup.test.sh && git commit -qm dup
  printf 'pass "works"\n' > dup.test.sh
)
BASE=$(cd "$R" && git rev-parse HEAD)
ledger batch cross-agent '| dup.test.sh::works | D | none: second copy of the same check | identical body | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 0 ] && pass "deleting one of two same-named declarations with one D row passes" || fail "a duplicate name must be deletable" "rc=$rc out=$out"
ledger batch cross-agent '| dup.test.sh::works | D | none: dup | x | - |' '| dup.test.sh::works | D | none: dup | x | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'still in the tree' \
  && pass "two D rows for one removal fail: one copy is still there" \
  || fail "D rows must not outnumber the removals" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- dup.test.sh)

# --- paths stay inside the repository ------------------------------------------------------
(cd "$R" && sed -i.bak '/adds two numbers/d' test.sh && rm test.sh.bak)
printf 'pass "covers addition"\n' > "$R/../outside-keeper.sh"
ledger batch cross-agent '| test.sh::adds two numbers | D | ../outside-keeper.sh::covers addition | outside | - |'
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'path outside the repository' \
  && pass "a keeper outside the repository is refused" \
  || fail "a ../ keeper must be refused" "rc=$rc out=$out"
rm -f "$R/../outside-keeper.sh"
(cd "$R" && git checkout -q -- test.sh)

# --- revisions are validated before git sees them --------------------------------------------
echo keep > "$R/victim.txt"
EXTRA_FM="rebaselined_from: --output=$R/victim.txt"
ledger campaign cross-agent "$GOOD_R"
out=$(verify --tree); rc=$?
[ "$rc" -eq 2 ] && [ "$(cat "$R/victim.txt")" = keep ] \
  && pass "a rebaselined_from that is not a SHA is refused before git runs, and nothing is written" \
  || fail "rebaselined_from must never reach git as an option" "rc=$rc victim=$(cat "$R/victim.txt")"
EXTRA_FM=""; rm -f "$R/victim.txt"

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

# Main changes two existing declarations in one file; reconciling one is not enough.
OLD=$BASE
(cd "$R" && printf 'pass "one"   # now stricter\npass "two"   # now stricter too\npass "three"\n' > tests/a.test.sh && git commit -qam main-again)
BASE=$(cd "$R" && git rev-parse HEAD); EXTRA_FM="rebaselined_from: $OLD"
ledger campaign cross-agent '| tests/a.test.sh::one | R | one | reconciled: stricter | - |' "$A2" "$A3" "$B1"; cscope
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'tests/a.test.sh::two' && ! printf '%s' "$out" | grep -q 'tests/a.test.sh::one' \
  && pass "each declaration main changed needs its own reconciled: row, not one per file" \
  || fail "a second changed declaration must need its own reconciled row" "rc=$rc out=$out"
EXTRA_FM=""; EXTRA_BODY=""

# Scope "." is the whole repo, and must list files rather than silently list none.
EXTRA_BODY="$LANES_BOTH"
ledger campaign cross-agent "$A1" "$A2" "$A3" "$B1"
out=$(verify --tree); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'old.test.sh: test file is in no lane' \
  && pass "scope '.' covers the whole repo: a test file outside every lane fails" \
  || fail "scope '.' must list the repo's test files" "rc=$rc out=$out"
EXTRA_BODY=""

rm -rf "$R"
report
