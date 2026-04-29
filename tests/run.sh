#!/usr/bin/env bash
# tests/run.sh — discover and run every *.test.sh under tests/.
# Each test file is a self-contained bash script that sources tests/lib/assert.sh,
# performs assertions, and exits 0 (pass) or 1 (fail).
#
# Usage:
#   ./tests/run.sh            # run all tests
#   ./tests/run.sh -k <patt>  # run only tests whose path matches <patt>
#   ./tests/run.sh -v         # verbose (show all assertion lines)

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
PATTERN=""
VERBOSE="false"

while [ $# -gt 0 ]; do
  case "$1" in
    -k) PATTERN="$2"; shift 2 ;;
    -v|--verbose) VERBOSE="true"; shift ;;
    -h|--help)
      cat <<EOF
Usage: ./tests/run.sh [-k <pattern>] [-v]

  -k <pattern>  Only run tests whose path matches <pattern>
  -v            Verbose: show every assertion line
EOF
      exit 0
      ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

# Find all test files
TEST_FILES=$(find "$ROOT" -name '*.test.sh' -type f | sort)

if [ -n "$PATTERN" ]; then
  TEST_FILES=$(echo "$TEST_FILES" | grep "$PATTERN" || true)
fi

if [ -z "$TEST_FILES" ]; then
  echo "No test files found." >&2
  exit 1
fi

# Color helpers
if [ -t 1 ]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  GREEN=""; RED=""; YELLOW=""; RESET=""
fi

TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
FAILED_LIST=""

echo "Running tests from $ROOT (against repo $REPO_ROOT)..."
echo ""

while IFS= read -r test_file; do
  [ -z "$test_file" ] && continue
  TOTAL_FILES=$((TOTAL_FILES + 1))
  rel="${test_file#$REPO_ROOT/}"

  if [ "$VERBOSE" = "true" ]; then
    if bash "$test_file"; then
      PASSED_FILES=$((PASSED_FILES + 1))
    else
      FAILED_FILES=$((FAILED_FILES + 1))
      FAILED_LIST="$FAILED_LIST $rel"
    fi
  else
    output=$(bash "$test_file" 2>&1)
    rc=$?
    summary_line=$(echo "$output" | tail -1)
    if [ "$rc" -eq 0 ]; then
      PASSED_FILES=$((PASSED_FILES + 1))
      echo "$summary_line"
    else
      FAILED_FILES=$((FAILED_FILES + 1))
      FAILED_LIST="$FAILED_LIST $rel"
      echo "$output"
    fi
  fi
done <<EOF
$TEST_FILES
EOF

echo ""
echo "—— Test summary ——"
echo "  Files passed: $PASSED_FILES"
echo "  Files failed: $FAILED_FILES"
echo "  Total files:  $TOTAL_FILES"

if [ "$FAILED_FILES" -gt 0 ]; then
  echo ""
  echo "${RED}Failed files:${RESET}"
  for f in $FAILED_LIST; do
    echo "  - $f"
  done
  exit 1
fi

echo ""
echo "${GREEN}All tests passed.${RESET}"
exit 0
