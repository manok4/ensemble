#!/usr/bin/env bash
# Tests for the red record in ensemble-verification-receipt (EN25 U4).
#
# A fix's test must fail before the fix. `red` runs the test command itself and
# records only a real failure; `verify --requires red_test --since <sha>` accepts
# only a record for this fix's start commit, for a test this fix added or
# changed, whose content is unchanged since it ran. Every fixture is a scratch
# repo; nothing touches this checkout's .git.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="verification receipt red records"

R="$REPO_ROOT/skills/en-ship/scripts/ensemble-verification-receipt"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A repo on branch `fix` whose src.sh prints a value and whose bug is that it
# prints 1 where 2 is right. t.sh is the regression test the fix adds.
new_repo() {  # $1=name -> path
  d="$WORK/$1"; mkdir -p "$d"
  (
    cd "$d" && git init -q -b main . && git config user.email t@example.com && git config user.name tester
    printf 'echo 1\n' > src.sh && git add src.sh && git commit -qm init && git checkout -qb fix
  ) >/dev/null 2>&1
  printf '%s\n' "$d"
}
add_test() {  # in cwd: a test that passes only when src.sh prints 2
  printf '[ "$(sh src.sh)" = 2 ]\n' > t.sh
}
fix_bug() { printf 'echo 2\n' > src.sh; }
reason() {  # $1=repo  $2..=verify args -> "<exit> <reason>"
  d="$1"; shift
  out=$(cd "$d" && "$R" verify --json "$@" 2>/dev/null); rc=$?
  r=$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("reason",""))
except Exception: print("UNPARSEABLE")')
  printf '%s %s\n' "$rc" "$r"
}

# --- happy path: red before, green after, verify passes --------------------
D=$(new_repo happy); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test t.sh --since "$S" -- sh t.sh) >/dev/null 2>&1; rc=$?
assert_exit_code 0 "$rc" "red records a test that fails before the fix"
(cd "$D" && fix_bug && sh t.sh && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "0 ok" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "red then green verifies"

# --- red against a test that already passes -----------------------------------
D=$(new_repo passing); S=$(git -C "$D" rev-parse HEAD)
out=$(cd "$D" && fix_bug && add_test && "$R" red --test t.sh --since "$S" -- sh t.sh 2>&1); rc=$?
assert_exit_code 1 "$rc" "a test that passes before the fix is refused"
assert_contains "$out" "red-test-passed" "the refusal says the test passed"
assert_file_missing "$D/.git/ensemble/red-tests.json" "a passing test writes no record"

# --- a command that does not run the test ---------------------------------------
D=$(new_repo unnamed); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test t.sh --since "$S" -- false) >/dev/null 2>&1; rc=$?
assert_exit_code 3 "$rc" "a command that does not name the test is a usage error"
(cd "$D" && "$R" red --test t.sh --since "$S" -- nosuchcommand-xyz t.sh) >/dev/null 2>&1; rc=$?
assert_exit_code 1 "$rc" "a command that never ran (exit 127) is refused"
assert_file_missing "$D/.git/ensemble/red-tests.json" "a command that never ran writes no record"

# --- --since must be HEAD or an ancestor of it ------------------------------------
D=$(new_repo since)
(cd "$D" && git checkout -qb elsewhere && printf 'x\n' > other && git add other && git commit -qm other \
  && git checkout -q fix) >/dev/null 2>&1
ELSE=$(git -C "$D" rev-parse elsewhere)
(cd "$D" && add_test && "$R" red --test t.sh --since "$ELSE" -- sh t.sh) >/dev/null 2>&1; rc=$?
assert_exit_code 3 "$rc" "--since naming a commit that is not an ancestor of HEAD is a usage error"
# A fix may commit a standalone refactor before its test; its start stays the base.
S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && printf 'echo 1 # room\n' > src.sh && git commit -qam "refactor: make room") >/dev/null 2>&1
(cd "$D" && "$R" red --test t.sh --since "$S" -- sh t.sh) >/dev/null 2>&1; rc=$?
assert_exit_code 0 "$rc" "--since may name the fix's start after a standalone commit"

# --- the test changed after it went red ------------------------------------------
D=$(new_repo changed); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test t.sh --since "$S" -- sh t.sh && fix_bug \
  && printf 'true\n' > t.sh && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "1 red-test-changed" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "editing the test after its red run refuses"

# --- an earlier fix's record cannot stand in for a later fix -----------------------
D=$(new_repo reuse); S1=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test t.sh --since "$S1" -- sh t.sh && fix_bug \
  && git add -A && git commit -qm "fix A") >/dev/null 2>&1
S2=$(git -C "$D" rev-parse HEAD)
(cd "$D" && printf 'echo 2 # tidy\n' > src.sh && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "1 red-test-stale" "$(reason "$D" --requires targeted_tests,red_test --since "$S2")" "a second fix on the same branch without its own red run is stale"

# --- a record made at an earlier start commit, test still uncommitted ----------
# The test is in the diff and unchanged, so only the start commit tells this
# record apart from one made for the fix being verified.
D=$(new_repo since-bound); S1=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test t.sh --since "$S1" -- sh t.sh \
  && printf 'x\n' > other && git add other && git commit -qm "unrelated commit") >/dev/null 2>&1
S2=$(git -C "$D" rev-parse HEAD)
(cd "$D" && fix_bug && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "1 red-test-stale" "$(reason "$D" --requires targeted_tests,red_test --since "$S2")" "a record for an earlier start commit does not satisfy a later --since"

# --- a red record for a test this fix did not touch ---------------------------------
D=$(new_repo unrelated)
(cd "$D" && add_test && git add t.sh && git commit -qm "existing test") >/dev/null 2>&1
S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && "$R" red --test t.sh --since "$S" -- sh t.sh && fix_bug && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "1 red-test-missing" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "a test outside this fix's diff does not count"

# --- a record from another branch ---------------------------------------------------
D=$(new_repo branch); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test t.sh --since "$S" -- sh t.sh && git checkout -qb other \
  && fix_bug && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "1 red-test-missing" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "a red record from another branch does not count"

# --- malformed records fail closed ----------------------------------------------------
D=$(new_repo malformed); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && fix_bug && "$R" write --check targeted_tests=passed --by test \
  && printf '{not json' > .git/ensemble/red-tests.json) >/dev/null 2>&1
assert_eq "1 malformed" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "a malformed red file refuses, never passes"

# --- a test named ./t.sh, or from a subdirectory, still verifies --------------------
D=$(new_repo dotslash); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test ./t.sh --since "$S" -- sh ./t.sh && fix_bug && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "0 ok" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "a test recorded as ./t.sh verifies"
D=$(new_repo subdir); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && mkdir -p sub && printf '[ "$(sh ../src.sh)" = 2 ]\n' > sub/t.sh && cd sub && "$R" red --test t.sh --since "$S" -- sh t.sh \
  && cd .. && fix_bug && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
assert_eq "0 ok" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "a test recorded from a subdirectory verifies from the root"

# --- a record missing a field fails closed, never an empty verdict --------------
D=$(new_repo fieldless); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && fix_bug && "$R" write --check targeted_tests=passed --by test \
  && printf '{"schema":1,"records":{"t.sh":{"since":"%s","branch":"fix"}}}' "$S" > .git/ensemble/red-tests.json) >/dev/null 2>&1
assert_eq "1 malformed" "$(reason "$D" --requires targeted_tests,red_test --since "$S")" "a record missing its test fields refuses as malformed"

# --- commands that name the test without running it are refused -----------------
D=$(new_repo shellc); S=$(git -C "$D" rev-parse HEAD)
(cd "$D" && add_test && "$R" red --test t.sh --since "$S" -- sh -c 'exit 1' t.sh) >/dev/null 2>&1; rc=$?
assert_exit_code 3 "$rc" "a shell -c wrapper that ignores the test is refused"
(cd "$D" && "$R" red --test t.sh --since "$S" -- false t.sh) >/dev/null 2>&1; rc=$?
assert_exit_code 3 "$rc" "false naming the test is refused"

# --- red_test without --since is a usage error; without red_test nothing changes ------
D=$(new_repo usage)
(cd "$D" && "$R" write --check targeted_tests=passed --by test) >/dev/null 2>&1
(cd "$D" && "$R" verify --requires targeted_tests,red_test >/dev/null 2>&1); rc=$?
assert_exit_code 3 "$rc" "--requires red_test without --since is a usage error"
assert_eq "0 ok" "$(reason "$D" --requires targeted_tests)" "verify without red_test is unchanged"

report
