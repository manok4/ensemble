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

# --- fix-agent reuses en-sweep secrets; push needs a workflow-triggering token ---
if grep -qiE "reuses en-sweep|no new secret for the agent" "$SETUP"; then
  pass "en-setup states the fix agent reuses en-sweep's secrets"
else
  fail "en-setup must state the fix agent reuses en-sweep's secrets"
fi
if grep -qF "EN_SHIP_WATCH_TOKEN" "$SETUP" && grep -qiE "does NOT retrigger|not retrigger|GITHUB_TOKEN" "$SETUP"; then
  pass "en-setup documents EN_SHIP_WATCH_TOKEN (GITHUB_TOKEN won't retrigger CI)"
else
  fail "en-setup must document the EN_SHIP_WATCH_TOKEN push-token requirement"
fi

# --- auto-merge prerequisite noted ---
if grep -qiE "Allow auto-merge|allow auto-merge" "$SETUP"; then
  pass "en-setup notes the auto-merge repo prerequisite"
else
  fail "en-setup must note the auto-merge prerequisite for --auto-merge"
fi

# --- verification table + summary include the new artifacts ---
verification_block="$(awk '
  /Required artifacts/ {in_block=1}
  /Optional artifacts/ {in_block=0}
  in_block {print}
' "$SETUP")"
if printf '%s\n' "$verification_block" | grep -qE "\.github/workflows/en-ship-watch\.yml"; then
  pass "en-setup verification lists the en-ship-watch workflow"
else
  fail "en-setup must list en-ship-watch.yml in verification"
fi
if printf '%s\n' "$verification_block" | grep -qF '`./bin/en-ship-watch-ci`'; then
  pass "en-setup verification checks the repo-local en-ship-watch-ci wrapper"
else
  fail "en-setup must verify repo-local ./bin/en-ship-watch-ci"
fi
if grep -qF "./bin/en-ship-watch-ci (chmod +x)" "$SETUP"; then
  pass "en-setup summary lists the repo-local en-ship-watch-ci wrapper"
else
  fail "en-setup summary must list repo-local ./bin/en-ship-watch-ci"
fi

report
