#!/usr/bin/env bash
# Drift guards for en-setup installing the en-ship-watch workflow + wrapper (EN04 U4).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup watch install"

SETUP="$REPO_ROOT/skills/en-setup/SKILL.md"
TEMPLATE="$REPO_ROOT/references/templates/github-workflow-en-ship-watch.yml"

# --- installs the workflow from the template ---
if grep -qF "en-ship-watch.yml" "$SETUP" && grep -qF "github-workflow-en-ship-watch.yml" "$SETUP"; then
  pass "en-setup installs en-ship-watch.yml from the template"
else
  fail "en-setup must install en-ship-watch.yml from the template"
fi

# --- installs the bin wrapper ---
if grep -qF "bin/en-ship-watch-ci" "$SETUP"; then
  pass "en-setup installs the en-ship-watch-ci wrapper"
else
  fail "en-setup must install the en-ship-watch-ci bin wrapper"
fi

# --- referenced template filename matches U3's actual file ---
if [ -f "$TEMPLATE" ]; then
  pass "the referenced en-ship-watch template file exists"
else
  fail "the en-ship-watch template file must exist (U3)"
fi

# --- idempotent install documented ---
if grep -qiE "[Ii]dempotent|overwrite only when content differs" "$SETUP"; then
  pass "en-setup documents an idempotent install"
else
  fail "en-setup must document an idempotent install"
fi

# --- reuses en-sweep secrets: NO new secret ---
if grep -qiE "NO new secret|no new secret|reuse.*secret" "$SETUP"; then
  pass "en-setup states the watcher reuses en-sweep's secrets (no new secret)"
else
  fail "en-setup must state that no new secret is needed"
fi

# --- auto-merge prerequisite noted ---
if grep -qiE "Allow auto-merge|allow auto-merge" "$SETUP"; then
  pass "en-setup notes the auto-merge repo prerequisite"
else
  fail "en-setup must note the auto-merge prerequisite for --auto-merge"
fi

# --- verification table + summary include the new artifacts ---
if grep -qE "\.github/workflows/en-ship-watch\.yml" "$SETUP"; then
  pass "en-setup verification/summary lists the en-ship-watch workflow"
else
  fail "en-setup must list en-ship-watch.yml in verification/summary"
fi

report
