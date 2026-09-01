#!/usr/bin/env bash
# Tiny assertion library used by tests/. No external deps; macOS bash 3.2 compatible.
#
# Each assertion that fails sets FAIL=1 and prints a diagnostic; the test file
# can call `report` at the end to exit with the right status.

# Initialize counters when the test file sources us.
: "${TEST_PASS:=0}"
: "${TEST_FAIL:=0}"
: "${TEST_NAME:=unnamed}"

# Color helpers (no-color in non-tty environments)
if [ -t 1 ]; then
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RESET=$'\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  RESET=""
fi

pass() {
  TEST_PASS=$((TEST_PASS + 1))
  printf '  %sok%s — %s\n' "$GREEN" "$RESET" "$1"
}

fail() {
  TEST_FAIL=$((TEST_FAIL + 1))
  printf '  %sFAIL%s — %s\n' "$RED" "$RESET" "$1"
  if [ -n "${2:-}" ]; then
    printf '         %s\n' "$2"
  fi
}

assert_eq() {
  local expected="$1" actual="$2" label="${3:-values}"
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label" "expected '$expected', got '$actual'"
  fi
}

assert_ne() {
  local not_expected="$1" actual="$2" label="${3:-values differ}"
  if [ "$not_expected" != "$actual" ]; then
    pass "$label"
  else
    fail "$label" "got '$actual' which should NOT equal '$not_expected'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-contains}"
  case "$haystack" in
    *"$needle"*) pass "$label" ;;
    *) fail "$label" "expected to find '$needle' in output (showing first 200 chars): ${haystack:0:200}" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-does not contain}"
  case "$haystack" in
    *"$needle"*) fail "$label" "found '$needle' in output but expected absence" ;;
    *) pass "$label" ;;
  esac
}

assert_exit_code() {
  local expected="$1" actual="$2" label="${3:-exit code}"
  if [ "$expected" -eq "$actual" ]; then
    pass "$label"
  else
    fail "$label" "expected exit $expected, got $actual"
  fi
}

assert_file_exists() {
  local path="$1" label="${2:-file exists: $1}"
  if [ -e "$path" ]; then
    pass "$label"
  else
    fail "$label" "$path does not exist"
  fi
}

assert_file_missing() {
  local path="$1" label="${2:-file missing: $1}"
  if [ ! -e "$path" ]; then
    pass "$label"
  else
    fail "$label" "$path exists but should not"
  fi
}

# Print a per-file summary; exit code reflects pass/fail.
# Flatten a markdown file to one line with emphasis markers stripped, so an
# assertion can match a sentence that wraps or carries **bold**/`code` without
# encoding the line breaks. Ten copies of this had accumulated across the
# reference-checking suites under three different names.
# NOTE: strips _ as an emphasis marker, so it mangles snake_case identifiers
# (problem_type -> problemtype). grep the raw file when matching a field name.
flat() { tr '\n' ' ' < "$1" | sed 's/[*_`]//g; s/  */ /g'; }

# Portable content hash. `md5 -q` is macOS-only; `md5sum` is the Linux spelling.
# A parity suite that dies on the hash never reaches the comparison it exists for.
hash_file() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else shasum "$1" | cut -d' ' -f1
  fi
}

# Assert a path appears in a SKILL.md's `requires:` BLOCK, not merely somewhere in
# the file. Several suites grepped the whole SKILL.md, so runtime prose naming the
# same path satisfied them after the declaration itself was deleted.
# Successor to assert_declared, which asked whether a hand-written requires:
# block listed a path. That question was answerable without the file being
# reachable, or even useful — the manifest was a second copy of the truth, kept
# in sync by hand. This asks the load-bearing question instead: does the skill's
# own flow reach the file? The answer is derived from the body, so it cannot
# drift from it.
_ENS_DERIVED="${TMPDIR:-/tmp}/ens-derived-$$"
_ens_derive() {
  [ -s "$_ENS_DERIVED" ] && return 0
  ( cd "${REPO_ROOT:-.}" && python3 tests/lib/skill-payload.py derive ) > "$_ENS_DERIVED" 2>/dev/null
}

assert_reached() {  # $1=SKILL.md  $2=relative path  $3=label
  _ens_derive
  local skill; skill="$(basename "$(dirname "$1")")"
  if grep -qxF -- "$skill	$2" "$_ENS_DERIVED"; then
    pass "$3"
  else
    fail "$3" "$skill carries no path $2 that its own flow reaches"
  fi
}

report() {
  local total=$((TEST_PASS + TEST_FAIL))
  if [ "$TEST_FAIL" -eq 0 ]; then
    printf '%s✓ %s%s — %d/%d passed\n' "$GREEN" "$TEST_NAME" "$RESET" "$TEST_PASS" "$total"
    exit 0
  else
    printf '%s✗ %s%s — %d failed, %d passed\n' "$RED" "$TEST_NAME" "$RESET" "$TEST_FAIL" "$TEST_PASS"
    exit 1
  fi
}
