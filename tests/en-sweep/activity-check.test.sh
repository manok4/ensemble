#!/usr/bin/env bash
# Tests for bin/ensemble-sweep-activity-check — the activity gate for
# scheduled /en-sweep runs.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-sweep-activity-check"

CHECK="$REPO_ROOT/skills/en-sweep/scripts/ensemble-sweep-activity-check"
[ -x "$CHECK" ] || { fail "missing or not executable: $CHECK"; report; exit 1; }

# Helper — set up a synthetic repo with a sequence of commits.
# Returns the absolute path to the repo.
make_repo() {
  local tmp; tmp=$(mktemp -d)
  cd "$tmp"
  git init -q -b main
  git config user.email "t@t"
  git config user.name "t"
  echo "init" > README.md
  git add . && git -c init.defaultBranch=main commit -q -m "init"
  # Tag the init commit as origin/main so the script can find it.
  git update-ref refs/remotes/origin/main HEAD
  echo "$tmp"
}

mark_origin() {
  # After making more commits, refresh origin/main to point at HEAD.
  git update-ref refs/remotes/origin/main HEAD
}

# --- 1. Manual flag short-circuits to should-run=true ---
TMP=$(make_repo)
out=$("$CHECK" --manual)
cd - >/dev/null
rm -rf "$TMP"
if echo "$out" | grep -q "should-run=true" && echo "$out" | grep -qi "manual trigger"; then
  pass "--manual returns should-run=true with reason"
else
  fail "--manual flag did not short-circuit" "$out"
fi

# --- 2. No prior sweep commit → should-run=true (first run after install) ---
# NB: make_repo runs `cd "$tmp"` in a subshell (it's invoked via `$()`), so the
# parent test shell is still in the ensemble repo until we cd in explicitly.
# A previous version did `git add` *before* the cd and accidentally committed
# work-in-progress files into the parent repo.
TMP=$(make_repo)
cd "$TMP"
echo "x" > a.txt
git add . && git commit -q -m "feat: add a"
mark_origin
out=$("$CHECK")
cd - >/dev/null
rm -rf "$TMP"
if echo "$out" | grep -q "should-run=true" && echo "$out" | grep -q "no prior sweep"; then
  pass "no prior sweep commit → should-run=true"
else
  fail "first-run case wrong" "$out"
fi

# --- 3. Sweep commit at HEAD with no commits since → should-run=false ---
TMP=$(make_repo)
cd "$TMP"
echo "x" > a.txt
git add . && git commit -q -m "chore(sweep): clean up cross-refs"
mark_origin
out=$("$CHECK")
cd - >/dev/null
rm -rf "$TMP"
if echo "$out" | grep -q "should-run=false" && echo "$out" | grep -q "no non-sweep commits"; then
  pass "sweep at HEAD, nothing since → should-run=false"
else
  fail "should have skipped" "$out"
fi

# --- 4. Sweep commit, then non-sweep commit → should-run=true ---
TMP=$(make_repo)
cd "$TMP"
echo "x" > a.txt
git add . && git commit -q -m "chore(sweep): old work"
echo "y" > b.txt
git add . && git commit -q -m "feat: real change"
mark_origin
out=$("$CHECK")
cd - >/dev/null
rm -rf "$TMP"
if echo "$out" | grep -q "should-run=true" && echo "$out" | grep -q "1 new commit"; then
  pass "sweep + 1 non-sweep commit → should-run=true (count=1)"
else
  fail "non-sweep commit since sweep should run" "$out"
fi

# --- 5. Sweep commit, then 3 non-sweep + 1 sweep commit → counts only non-sweep ---
TMP=$(make_repo)
cd "$TMP"
echo "1" > 1.txt && git add . && git commit -q -m "chore(sweep): first sweep"
echo "2" > 2.txt && git add . && git commit -q -m "feat: real 1"
echo "3" > 3.txt && git add . && git commit -q -m "fix: real 2"
echo "4" > 4.txt && git add . && git commit -q -m "chore(arch): doc update"   # sweep-authored; should be excluded
echo "5" > 5.txt && git add . && git commit -q -m "feat: real 3"
mark_origin
out=$("$CHECK")
cd - >/dev/null
rm -rf "$TMP"
# The most recent sweep commit is "chore(arch):" (4 commits after init); commits since: 1 (the "feat: real 3").
if echo "$out" | grep -q "should-run=true" && echo "$out" | grep -q "1 new commit"; then
  pass "uses most recent sweep commit; counts non-sweep commits since"
else
  fail "wrong counting logic" "$out"
fi

# --- 6. All sweep commit prefixes recognized ---
# chore(docs) left this list with D65: humans type it, and a scope shared with
# humans silences the gate (D84 found this copy still recognising it).
for prefix in "chore(sweep)" "chore(arch)" "chore(plans)" "chore(learnings)" "chore(maps)"; do
  TMP=$(make_repo)
  cd "$TMP"
  echo "x" > a.txt
  git add . && git commit -q -m "$prefix: sweep work"
  mark_origin
  out=$("$CHECK")
  cd - >/dev/null
  rm -rf "$TMP"
  if echo "$out" | grep -q "should-run=false"; then
    pass "recognizes '$prefix:' as a sweep commit"
  else
    fail "did not recognize '$prefix:' prefix" "$out"
  fi
done

# --- 7. --branch flag overrides default origin/main ---
TMP=$(make_repo)
cd "$TMP"
git checkout -q -b dev
echo "x" > a.txt && git add . && git commit -q -m "feat: dev work"
git update-ref refs/remotes/origin/dev HEAD
out=$("$CHECK" --branch origin/dev)
cd - >/dev/null
rm -rf "$TMP"
if echo "$out" | grep -q "should-run=true"; then
  pass "--branch flag scopes the gate to a non-default branch"
else
  fail "--branch override didn't work" "$out"
fi

# --- 8. Output is GITHUB_OUTPUT-compatible (key=value lines, no blanks) ---
TMP=$(make_repo)
cd "$TMP"
echo "x" > a.txt && git add . && git commit -q -m "feat: x"
mark_origin
out=$("$CHECK")
cd - >/dev/null
rm -rf "$TMP"
if echo "$out" | grep -q "^should-run=" && echo "$out" | grep -q "^reason="; then
  pass "output is key=value lines (GITHUB_OUTPUT-compatible)"
else
  fail "output format wrong" "$out"
fi

# --- 9. Help text ---
out=$("$CHECK" --help 2>&1 || true)
if echo "$out" | grep -q "Usage:"; then
  pass "--help prints usage"
else
  fail "--help did not print usage" "$out"
fi

# --- 10. Unknown flag exits non-zero ---
TMP=$(make_repo)
cd "$TMP"
out=$("$CHECK" --bogus 2>&1 || true)
rc=$?
cd - >/dev/null
rm -rf "$TMP"
# Note: $? captures the test's last bash command exit, not the subshell's.
# Re-run to capture rc deterministically.
TMP=$(make_repo)
cd "$TMP"
"$CHECK" --bogus >/dev/null 2>&1
rc=$?
cd - >/dev/null
rm -rf "$TMP"
if [ "$rc" -ne 0 ]; then
  pass "unknown flag exits non-zero"
else
  fail "unknown flag should exit non-zero" "rc=$rc"
fi

# --- D65 holds in this copy too: no scope a human would type ---------------
assert_not_contains "$(grep '^SWEEP_PATTERN=' "$CHECK")" "docs" "SWEEP_PATTERN claims no scope humans share (en-setup copy)"

report
