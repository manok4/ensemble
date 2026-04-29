#!/usr/bin/env bash
# Adversarial test for bin/ensemble-doc-only-check.
#
# Sets up a temp git repo, stages various paths (some doc, some non-doc), and
# verifies the check accepts doc-only and rejects anything outside the allowlist.
# This is the P0-regression test from foundation §20.2.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-garden doc-only enforcement"

CHECK="$REPO_ROOT/bin/ensemble-doc-only-check"

setup_temp_repo() {
  local tmp="$1"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  pushd "$tmp" >/dev/null
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  # Make an initial commit so we can stage diffs cleanly.
  echo "init" > .init && git add .init && git commit -qm "init"
  popd >/dev/null
}

# --- Scenario 1: only doc paths staged → check accepts ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
mkdir -p docs
echo "doc content" > docs/architecture.md
git add docs/architecture.md
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 0 "$rc" "doc-only stage exits 0"
assert_contains "$output" "all staged paths under docs/ allowlist" "doc-only stage produces success message"
rm -rf "$TMP"

# --- Scenario 2: AGENTS.md staged → accepted ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
echo "agents content" > AGENTS.md
git add AGENTS.md
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 0 "$rc" "AGENTS.md stage exits 0"
rm -rf "$TMP"

# --- Scenario 3: CLAUDE.md staged → accepted ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
echo "claude content" > CLAUDE.md
git add CLAUDE.md
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 0 "$rc" "CLAUDE.md stage exits 0"
rm -rf "$TMP"

# --- Scenario 4: source file staged → REJECTED (P0) ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
mkdir -p src
echo "console.log('source code');" > src/index.ts
git add src/index.ts
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 1 "$rc" "source-file stage exits non-zero"
assert_contains "$output" "doc-only" "rejection mentions doc-only"
assert_contains "$output" "src/index.ts" "rejection cites the offending path"
rm -rf "$TMP"

# --- Scenario 5: mixed (doc + source) → REJECTED ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
mkdir -p docs src
echo "doc" > docs/architecture.md
echo "src" > src/billing.ts
git add docs/architecture.md src/billing.ts
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 1 "$rc" "mixed stage exits non-zero (source path present)"
assert_contains "$output" "src/billing.ts" "rejection cites the source-file offender"
rm -rf "$TMP"

# --- Scenario 6: config file staged → REJECTED ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
echo '{"new":"config"}' > package.json
git add package.json
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 1 "$rc" "package.json stage exits non-zero"
assert_contains "$output" "package.json" "rejection cites package.json"
rm -rf "$TMP"

# --- Scenario 7: test file staged → REJECTED ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
mkdir -p tests/auth
echo "test" > tests/auth/refresh.test.ts
git add tests/auth/refresh.test.ts
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 1 "$rc" "test-file stage exits non-zero (tests are not doc-only)"
assert_contains "$output" "tests/auth/refresh.test.ts" "rejection cites the test path"
rm -rf "$TMP"

# --- Scenario 8: .github/workflows/en-garden.yml staged → ACCEPTED (allowlisted) ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
mkdir -p .github/workflows
echo "name: en-garden" > .github/workflows/en-garden.yml
git add .github/workflows/en-garden.yml
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 0 "$rc" ".github/workflows/en-garden.yml is allowlisted"
rm -rf "$TMP"

# --- Scenario 9: empty stage → exit 0 with note ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 0 "$rc" "empty stage exits 0"
assert_contains "$output" "nothing staged" "empty-stage notes nothing-staged"
rm -rf "$TMP"

report
