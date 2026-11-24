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
TEST_NAME="en-sweep doc-only enforcement"

# An en-sweep test reading en-review's copy. en-review does not gate doc-only
# PRs — /en-sweep does — so it stopped carrying the check.
CHECK="$REPO_ROOT/skills/en-sweep/scripts/ensemble-doc-only-check"

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

# --- Scenario 8: .github/workflows/en-sweep.yml staged → REJECTED (D101: the
#     workflow is retired, and a workflow file is not a doc) ---
TMP=$(mktemp -d)
setup_temp_repo "$TMP"
pushd "$TMP" >/dev/null
mkdir -p .github/workflows
echo "name: en-sweep" > .github/workflows/en-sweep.yml
git add .github/workflows/en-sweep.yml
output=$("$CHECK" 2>&1); rc=$?
popd >/dev/null
assert_exit_code 1 "$rc" ".github/workflows/en-sweep.yml is no longer allowlisted"
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

# --- Strategy section: sweep never edits it (EN32 U8) ---
# The author owns docs/foundation.md's Strategy section; a staged change to it,
# marker date included, is refused. A reader error on either revision fails
# closed before any comparison.
FX="$REPO_ROOT/tests/strategy/fixtures"
strategy_repo() {  # $1 = fixture committed as docs/foundation.md
  TMP=$(mktemp -d); setup_temp_repo "$TMP"; pushd "$TMP" >/dev/null
  mkdir -p docs && cp "$1" docs/foundation.md && git add docs/foundation.md && git commit -qm foundation
}
staged_check() { git add docs/foundation.md; output=$("$CHECK" 2>&1); rc=$?; popd >/dev/null; rm -rf "$TMP"; }

strategy_repo "$FX/numbered.md"
printf '\n- G2. Small.\n' >> docs/foundation.md
staged_check
assert_exit_code 0 "$rc" "an edit outside the Strategy section is accepted"

strategy_repo "$FX/numbered.md"
sed -i.bak 's/^Every command prints plain text\.$/Every command prints plain text, always./' docs/foundation.md && rm docs/foundation.md.bak
staged_check
assert_exit_code 1 "$rc" "an edit inside the Strategy section is refused"
assert_contains "$output" "en-sweep never edits the Strategy section; file a strategy-drift TD instead" "the refusal says what to do instead"

strategy_repo "$FX/numbered.md"
sed -i.bak 's/author-approved 2026-11-01/author-approved 2026-11-02/' docs/foundation.md && rm docs/foundation.md.bak
staged_check
assert_exit_code 1 "$rc" "moving only the marker date is refused"

strategy_repo "$FX/no-marker.md"
printf '\nMore text.\n' >> docs/foundation.md
staged_check
assert_exit_code 0 "$rc" "with no Strategy section in HEAD or the index the check passes"

strategy_repo "$FX/duplicate.md"
sed -i.bak 's/^### ST2\. Also small$/### ST2. Also very small/' docs/foundation.md && rm docs/foundation.md.bak
staged_check
assert_exit_code 1 "$rc" "two Strategy headings fail closed"
assert_contains "$output" "cannot read the Strategy section in HEAD docs/foundation.md" "and name the revision the reader could not read"

# A rename shows only its new path under git's default rename detection, so a
# moved foundation would skip the Strategy comparison, and a source file moved
# into docs/ would pass the allowlist with its deleted source unseen.
strategy_repo "$FX/numbered.md"
git mv docs/foundation.md docs/foundation-old.md
output=$("$CHECK" 2>&1); rc=$?; popd >/dev/null; rm -rf "$TMP"
assert_exit_code 1 "$rc" "renaming the foundation away is refused as a Strategy edit"
assert_contains "$output" "en-sweep never edits the Strategy section" "the rename refusal names the Strategy rule"

TMP=$(mktemp -d); setup_temp_repo "$TMP"; pushd "$TMP" >/dev/null
mkdir -p src docs && printf 'code\n' > src/x.js && git add src/x.js && git commit -qm code
git mv src/x.js docs/x.js
output=$("$CHECK" 2>&1); rc=$?; popd >/dev/null; rm -rf "$TMP"
assert_exit_code 1 "$rc" "moving a source file into docs/ is refused"
assert_contains "$output" "src/x.js" "the refusal names the source path the move deleted"

# A foundation the batch does not touch is never read, so a repo whose HEAD
# already has two Strategy headings can still ship unrelated doc fixes.
strategy_repo "$FX/duplicate.md"
printf 'x\n' > docs/other.md && git add docs/other.md
output=$("$CHECK" 2>&1); rc=$?; popd >/dev/null; rm -rf "$TMP"
assert_exit_code 0 "$rc" "an untouched foundation with two Strategy headings does not block other docs"

report
