#!/usr/bin/env bash
# Tests for skills/en-ship/scripts/ensemble-floor-guard (EN25 U3).
#
# The guard blocks a ship that deletes a test, skips one, silences a checker or
# lowers a coverage threshold, and only reports removed assertions and stubs.
# Every fixture is a real repo with a `main` and a `feature` branch in a temp
# dir; nothing here runs against the Ensemble checkout.
#
# The suppression and skip strings are assembled from pieces below, so this file
# does not itself read as a skipped test or a silenced checker to the guard.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="floor guard"

G="$REPO_ROOT/skills/en-ship/scripts/ensemble-floor-guard"
assert_file_exists "$G" "the floor guard exists"
[ -x "$G" ] && pass "the floor guard is executable" || fail "the floor guard is executable"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

SKIP_CALL="it.sk""ip("
LINT_OFF="// eslint-""disable-next-line"
TS_OFF="// @ts-""ignore"

new_repo() {  # $1=name -> path on stdout; main has src, a test and a coverage config
  d="$WORK/$1"; mkdir -p "$d/src" "$d/tests"
  (
    cd "$d" && git init -q -b main . && git config user.email t@example.com && git config user.name tester
    printf 'function add(a, b) { return a + b; }\nmodule.exports = { add };\n' > src/add.js
    printf "const { add } = require('../src/add');\ntest('adds', () => {\n  expect(add(1, 2)).toBe(3);\n  expect(add(0, 0)).toBe(0);\n});\n" > tests/add.test.js
    printf "test('other', () => { expect(1).toBe(1); });\n" > tests/other.test.js
    printf '[tool.coverage.report]\nfail_under = 90\n' > pyproject.toml
    git add -A && git commit -qm init && git checkout -qb feature
  ) >/dev/null 2>&1
  printf '%s\n' "$d"
}

run() {  # $1=repo  $2..=extra args -> "<exit>" and leaves JSON in $OUT
  d="$1"; shift
  OUT=$(cd "$d" && "$G" --base main --json "$@" 2>"$WORK/err"); RC=$?
}

moves_in() {  # $1=bucket -> "move path" lines from $OUT
  printf '%s' "$OUT" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for m in d[sys.argv[1]]: print(m["move"], m["path"])' "$1" 2>/dev/null
}

# --- happy path ---------------------------------------------------------------
R=$(new_repo clean)
( cd "$R" && printf 'function sub(a, b) { return a - b; }\n' > src/sub.js \
  && printf "test('subs', () => { expect(1 - 1).toBe(0); });\n" > tests/sub.test.js \
  && git add -A && git commit -qm "feat: sub" ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "adding code and a test exits 0"
assert_eq "" "$(moves_in blocked)$(moves_in reported)" "nothing blocked or reported for a clean change"

# --- each blocking move, one fixture each -----------------------------------
R=$(new_repo deleted)
( cd "$R" && git rm -q tests/other.test.js && git commit -qm "drop test" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "deleting a test file blocks"
assert_contains "$(moves_in blocked)" "test-deleted tests/other.test.js" "the block names the deleted test"

R=$(new_repo skipped)
( cd "$R" && printf "%s'flaky', () => { expect(1).toBe(2); });\n" "$SKIP_CALL" >> tests/add.test.js && git commit -qam "skip" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "adding a skipped test blocks"
assert_contains "$(moves_in blocked)" "test-skipped tests/add.test.js" "the block names the skipped test"

R=$(new_repo silenced)
( cd "$R" && printf '%s\nconst unused = 1;\n' "$LINT_OFF" >> src/add.js && git commit -qam "silence" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "adding a lint suppression blocks"
assert_contains "$(moves_in blocked)" "checker-silenced src/add.js" "the block names the silenced file"

R=$(new_repo lowered)
( cd "$R" && sed -i.bak 's/fail_under = 90/fail_under = 80/' pyproject.toml && rm pyproject.toml.bak && git commit -qam "lower" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "lowering a coverage threshold blocks"
assert_contains "$(moves_in blocked)" "threshold-lowered pyproject.toml" "the block names the config"

R=$(new_repo emptied)
( cd "$R" && printf "test('other', () => {});\n" > tests/other.test.js && git commit -qam "empty it" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "a kept test file left with no assertions blocks"
assert_contains "$(moves_in blocked)" "test-deleted tests/other.test.js" "an emptied test reads as deleted"

R=$(new_repo threshold-gone)
( cd "$R" && printf '[tool.coverage.report]\n' > pyproject.toml && git commit -qam "drop threshold" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "deleting a coverage threshold outright blocks"
assert_contains "$(moves_in blocked)" "threshold-lowered pyproject.toml" "the deleted threshold is named"

R=$(new_repo textconv)
( cd "$R" && printf 'src/*.js -diff\n' > .gitattributes && git add .gitattributes && git commit -qm attrs \
  && git checkout -q main && git merge -q --ff-only feature 2>/dev/null; git checkout -q feature \
  && printf '%s\nconst unused = 1;\n' "$LINT_OFF" >> src/add.js && git commit -qam "silence behind -diff" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "a .gitattributes binary marker does not hide an added suppression"

# --- reported, never blocking --------------------------------------------------
R=$(new_repo asserts)
( cd "$R" && printf "const { add } = require('../src/add');\ntest('adds', () => {\n  expect(add(1, 2)).toBe(3);\n});\n" > tests/add.test.js && git commit -qam "weaken" ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "removing some assertions from a kept test does not block"
assert_contains "$(moves_in reported)" "assertion-removed tests/add.test.js" "removed assertions are reported"

R=$(new_repo stub)
( cd "$R" && printf 'function load() {\n  try { return read(); } catch (e) {}\n}\n' > src/load.js && git add -A && git commit -qm "stub" ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "an empty catch does not block"
assert_contains "$(moves_in reported)" "stub-added src/load.js" "the empty catch is reported"

# --- exceptions -----------------------------------------------------------------
R=$(new_repo trailer)
( cd "$R" && git rm -q tests/other.test.js \
  && git commit -qm "drop test" -m "Floor-Exception: test-deleted tests/other.test.js: superseded by add.test.js" ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "a Floor-Exception trailer excuses the deletion"
assert_contains "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print([m["by"] for m in json.load(sys.stdin)["excused"]])')" "trailer" "the excuse is the trailer"

R=$(new_repo ledger)
( cd "$R" && mkdir -p docs/test-audits && printf '| tests/other.test.js | D | none | dead export | - |\n' > docs/test-audits/batch-1.md \
  && git add docs && git rm -q tests/other.test.js \
  && git commit -qm "test: prune" -m "Test-Audit-Ledger: docs/test-audits/batch-1.md" ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "a Test-Audit-Ledger trailer whose ledger names the test excuses the deletion"
assert_contains "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print([m["by"] for m in json.load(sys.stdin)["excused"]])')" "ledger" "the excuse is the ledger"

R=$(new_repo ledger-missing)
( cd "$R" && git rm -q tests/other.test.js \
  && git commit -qm "test: prune" -m "Test-Audit-Ledger: docs/test-audits/nowhere.md" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "a ledger trailer naming a file that does not exist does not excuse"

R=$(new_repo ledger-other)
( cd "$R" && mkdir -p docs/test-audits && printf '| tests/add.test.js | R | kept | - | - |\n' > docs/test-audits/b.md \
  && git add docs && git rm -q tests/other.test.js \
  && git commit -qm "test: prune" -m "Test-Audit-Ledger: docs/test-audits/b.md" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "a ledger that does not name the deleted test does not excuse"

R=$(new_repo pending)
( cd "$R" && printf "%s'flaky', () => {});\n" "$SKIP_CALL" >> tests/add.test.js ) >/dev/null 2>&1
run "$R" --pending-exception "test-skipped tests/add.test.js: flaky upstream, tracked in #12"
assert_exit_code 0 "$RC" "a pending exception excuses uncommitted work"
assert_contains "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print([m["by"] for m in json.load(sys.stdin)["excused"]])')" "pending" "the excuse is pending"

R=$(new_repo wrongpath)
( cd "$R" && git rm -q tests/other.test.js \
  && git commit -qm "drop test" -m "Floor-Exception: test-deleted tests/add.test.js: wrong file named" ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "an exception naming a different path does not excuse the deletion"

# --- edge cases -----------------------------------------------------------------
R=$(new_repo untracked)
( cd "$R" && printf '%s\nconst x = 1;\n' "$TS_OFF" > src/new.ts ) >/dev/null 2>&1
run "$R"
assert_exit_code 1 "$RC" "an untracked file with a suppression blocks"

R=$(new_repo raised)
( cd "$R" && sed -i.bak 's/fail_under = 90/fail_under = 95/' pyproject.toml && rm pyproject.toml.bak && git commit -qam "raise" ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "raising a threshold does not block"

R=$(new_repo docs)
( cd "$R" && printf 'Never write `%s` in source.\n' "$LINT_OFF" > NOTES.md && git add -A && git commit -qm docs ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "a suppression named inside a markdown doc does not block"

# A removed content line "-- intro" prints as "--- intro" inside a hunk. A parser
# that matched file headers there would switch to a file named "intro" (not a
# doc) and charge the next added line, a suppression quoted in the README, to it.
R=$(new_repo dashes)
( cd "$R" && git checkout -q main && printf -- '-- intro\nbody\n' > README.md && git add -A && git commit -qm readme \
  && git checkout -q feature && git rebase -q main \
  && printf '%s example\nbody\n' "$LINT_OFF" > README.md && git commit -qam "readme" ) >/dev/null 2>&1
run "$R"
assert_exit_code 0 "$RC" "a removed line starting with dashes is not read as a file header"

# --- could not run ---------------------------------------------------------------
NB="$WORK/nobase"; mkdir -p "$NB"
( cd "$NB" && git init -q -b main . && git config user.email t@example.com && git config user.name tester \
  && echo a > a && git add a && git commit -qm a && git checkout -q --orphan other && git rm -qrf . \
  && echo b > b && git add b && git commit -qm b ) >/dev/null 2>&1
( cd "$NB" && "$G" --base main >/dev/null 2>&1 ); rc=$?
assert_exit_code 2 "$rc" "no merge base exits 2"

( cd "$WORK" && "$G" --base main >/dev/null 2>&1 ); rc=$?
assert_exit_code 2 "$rc" "outside a git work tree exits 2"

# A git shim that fails only `ls-files` isolates the listing step: every other
# subcommand reaches the real git, so a guard that swallowed the failure and
# treated the listing as empty would exit 0 here.
SHIM="$WORK/shim"; mkdir -p "$SHIM"; REAL_GIT=$(command -v git)
printf '#!/bin/sh\n[ "$1" = "ls-files" ] && { echo "shim: ls-files failed" >&2; exit 128; }\nexec "%s" "$@"\n' "$REAL_GIT" > "$SHIM/git"
chmod +x "$SHIM/git"
R=$(new_repo shim)
( cd "$R" && PATH="$SHIM:$PATH" "$G" --base main >/dev/null 2>&1 ); rc=$?
assert_exit_code 2 "$rc" "a failing git ls-files exits 2, never 0"

( cd "$R" && "$G" >/dev/null 2>&1 ); rc=$?
assert_exit_code 3 "$rc" "a missing --base is a usage error"
( cd "$R" && "$G" --base main --pending-exception "made-up tests/x: why" >/dev/null 2>&1 ); rc=$?
assert_exit_code 3 "$rc" "an exception with an unknown move is a usage error"

# --- markdown for the PR body -------------------------------------------------------
R=$(new_repo md)
( cd "$R" && printf 'function load() {\n  try { return read(); } catch (e) {}\n}\n' > src/load.js && git add -A && git commit -qm "stub" ) >/dev/null 2>&1
md=$(cd "$R" && "$G" --base main --markdown 2>/dev/null)
assert_contains "$md" "## Quality bar" "markdown mode renders a Quality bar section"
md=$(cd "$(new_repo mdclean)" && "$G" --base main --markdown 2>/dev/null)
assert_eq "" "$md" "markdown mode prints nothing when there is nothing to report"

report
