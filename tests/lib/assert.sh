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
