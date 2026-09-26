#!/usr/bin/env bash
# tests/en-test-audit/preflight.test.sh
#
# The preflight is where /en-test-audit refuses to start: on the default branch,
# on a dirty tree, with no scope, or with no Test command to prove a deletion
# safe. It also records the baseline, and it is the only way back into a batch
# that stopped staged, so its resume check decides what a resumed commit may
# contain.
#
# Negative controls at authoring: dropping the main|master case let the
# default-branch scenario pass; dropping the untracked-files flag let the dirty
# scenario pass; dropping the Seams removed block turned the staged-seam
# scenario red. After the EN21 branch review: dropping keepers from the resume
# allowlist, and accepting a scope outside the repository, each turned red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
. "$SELF_DIR/lib.sh"
TEST_NAME="en-test-audit preflight"

PF="$REPO_ROOT/skills/en-test-audit/scripts/ensemble-test-audit-preflight"
[ -x "$PF" ] || { fail "missing or not executable: $PF"; report; exit 1; }

run() { (cd "$R" && "$PF" "$@" 2>&1); }
unchanged() { [ -z "$(cd "$R" && git status --porcelain)" ]; }

# --- ready -------------------------------------------------------------------
R=$(make_audit_repo)
out=$(run); rc=$?
head_sha=$(cd "$R" && git rev-parse HEAD)
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qx 'branch=audit' \
   && printf '%s' "$out" | grep -qx "baseline_sha=$head_sha" \
   && printf '%s' "$out" | grep -qx 'test_command=sh test.sh' \
   && printf '%s' "$out" | grep -qx 'baseline=green' && unchanged; then
  pass "a clean feature branch is ready, with branch, baseline SHA, test command and a green baseline"
else
  fail "a clean feature branch must be ready" "rc=$rc out=$out"
fi

# --- refusals ------------------------------------------------------------------
(cd "$R" && git switch -q main)
out=$(run); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'refusing: default branch' && unchanged \
  && pass "the default branch is refused" \
  || fail "the default branch must be refused" "rc=$rc out=$out"
(cd "$R" && git switch -q audit)

(cd "$R" && git update-ref refs/remotes/origin/HEAD refs/heads/audit \
   && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/audit \
   && git update-ref refs/remotes/origin/audit HEAD)
out=$(run); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'default branch (audit)' \
  && pass "origin/HEAD names the default branch when a remote declares one" \
  || fail "origin/HEAD must override the main/master convention" "rc=$rc out=$out"
(cd "$R" && git symbolic-ref -d refs/remotes/origin/HEAD && git update-ref -d refs/remotes/origin/audit)

echo scratch > "$R/notes.txt"
out=$(run); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'refusing: dirty tree' \
  && pass "an untracked file makes the tree dirty" \
  || fail "an untracked file must refuse" "rc=$rc out=$out"
rm "$R/notes.txt"

out=$(run --scope missing/); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'refusing: scope missing/\{0,1\} does not exist' && unchanged \
  && pass "a missing scope is refused" \
  || fail "a missing scope must be refused" "rc=$rc out=$out"

mkdir -p "$R/lib" && touch "$R/lib/.keep" && (cd "$R" && git add lib && git commit -qm lib)
out=$(run --scope lib); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qx 'scope=lib' \
  && pass "an existing scope is accepted and printed repo-relative" \
  || fail "--scope lib must print scope=lib" "rc=$rc out=$out"
out=$(cd "$R/lib" && "$PF" --scope . 2>&1); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qx 'scope=lib' \
  && pass "a scope is resolved against the caller's directory, so '.' in lib/ is lib" \
  || fail "--scope . from lib/ must print scope=lib" "rc=$rc out=$out"
for outside in .. /; do
  out=$(run --scope "$outside"); rc=$?
  [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'outside the repository' \
    && pass "a scope outside the repository ($outside) is refused" \
    || fail "--scope $outside must be refused" "rc=$rc out=$out"
done

(cd "$R" && printf -- '- **Test:** `<unset>`\n' > AGENTS.md && git commit -qam unset)
out=$(run); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'declares no Test command' && unchanged \
  && pass "an unset Test command is refused" \
  || fail "an unset Test command must be refused" "rc=$rc out=$out"
(cd "$R" && git reset -q --hard HEAD~1)

# --- a red baseline is reported, not refused -------------------------------------
(cd "$R" && printf 'add() { echo 0; }\n' > src.sh && git commit -qam red)
out=$(run); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qx 'baseline=red' && unchanged \
  && pass "a red baseline is reported with exit 0, for the skill to raise as a product bug" \
  || fail "a red baseline must be reported, not refused" "rc=$rc out=$out"
(cd "$R" && git reset -q --hard HEAD~1)
rm -rf "$R"

# --- resume ------------------------------------------------------------------------
R=$(make_audit_repo)
(
  cd "$R" || exit 1
  mkdir -p docs/test-audits/m lib
  echo 'reset() { :; }' > lib/reset-for-tests.sh
  printf 'check() { :; }\n' > old.test.sh
  printf 'pass "covers addition"\n' > keeper.sh
  git add . && git commit -qm more
  cat > docs/test-audits/2026-09-26-x.md <<'EOF'
---
type: test-audit
---

## Ledger

| Test | Mark | Keeper or contract | Evidence | Mutation |
|---|---|---|---|---|
| old.test.sh | D | none: duplicate of test.sh | same assertion | - |
| test.sh::adds two numbers | F | addition | tightened | m/add.diff |
| test.sh::rejects nothing | C | keeper.sh::covers addition | moved into keeper.sh | m/add.diff |

## Seams removed

| Path | Reason |
|---|---|
| lib/reset-for-tests.sh | only tests called it |
EOF
  echo 'diff' > docs/test-audits/m/add.diff
  echo '{"result": "caught"}' > docs/test-audits/m/add.diff.caught
  git rm -q old.test.sh
  echo '# tightened' >> test.sh
  echo 'pass "moved assertion"' >> keeper.sh
  git add docs test.sh keeper.sh
)
out=$(run --resume "$R/docs/test-audits/2026-09-26-x.md"); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qx 'branch=audit' && ! printf '%s' "$out" | grep -q '^baseline=' \
  && pass "a staged batch of the ledger, its diff and receipt, its rows' files and a C row's keeper resumes" \
  || fail "the ledger's own staged batch must resume" "rc=$rc out=$out"

(cd "$R" && git rm -q lib/reset-for-tests.sh)
out=$(run --resume docs/test-audits/2026-09-26-x.md); rc=$?
[ "$rc" -eq 0 ] \
  && pass "a staged seam removal listed under Seams removed resumes" \
  || fail "a listed seam removal must be allowed on resume" "rc=$rc out=$out"

(cd "$R" && sed -i.bak '/reset-for-tests/d' docs/test-audits/2026-09-26-x.md && rm docs/test-audits/2026-09-26-x.md.bak \
   && git add docs/test-audits/2026-09-26-x.md)
out=$(run --resume docs/test-audits/2026-09-26-x.md); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'lib/reset-for-tests.sh' \
  && pass "the same seam removal without its listing is refused, and named" \
  || fail "an unlisted staged seam removal must be refused" "rc=$rc out=$out"
(cd "$R" && git reset -q HEAD lib/reset-for-tests.sh && git checkout -q -- lib/reset-for-tests.sh)

echo 'add() { :; }' >> "$R/src.sh"
out=$(run --resume docs/test-audits/2026-09-26-x.md); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'src.sh' \
  && pass "an unstaged edit blocks a resume, and is named" \
  || fail "an unstaged edit must block a resume" "rc=$rc out=$out"
(cd "$R" && git checkout -q -- src.sh)

(cd "$R" && echo x > stray.txt && git add stray.txt)
out=$(run --resume docs/test-audits/2026-09-26-x.md); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'stray.txt' \
  && pass "a staged file the ledger does not name blocks a resume, and is named" \
  || fail "a staged stranger must block a resume" "rc=$rc out=$out"
rm -rf "$R"

report
