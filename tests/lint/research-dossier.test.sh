#!/usr/bin/env bash
# Drift guards for the research evidence-dossier pattern (FR01 U10).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="research evidence dossier"

DISPATCH="$REPO_ROOT/references/research-dispatch.md"

# --- central protocol documented ---
if grep -qiE "Evidence dossier" "$DISPATCH"; then
  pass "research-dispatch documents the evidence-dossier pattern"
else
  fail "research-dispatch must document the evidence-dossier pattern"
fi

# --- scratch path + gist + read-on-demand ---
if grep -qF "/tmp/ensemble/" "$DISPATCH"; then
  pass "dossier scratch path documented"
else
  fail "dossier scratch path must be documented"
fi
if grep -qiE "gist" "$DISPATCH" && grep -qF "dossier_path" "$DISPATCH"; then
  pass "gist + dossier_path return contract documented"
else
  fail "gist + dossier_path contract must be documented"
fi

# --- degraded fallback ---
if grep -qiE "Degraded fallback|inline.*fail|dossier_path: null" "$DISPATCH"; then
  pass "degraded inline fallback documented"
else
  fail "degraded inline fallback must be documented"
fi

# --- each of the three agents references the protocol ---
for agent in repo-research learnings-research web-research; do
  f="$REPO_ROOT/agents/$agent.md"
  if grep -qiE "Evidence dossier" "$f" && grep -qF "dossier_path" "$f"; then
    pass "$agent documents the dossier contract"
  else
    fail "$agent must document the dossier contract"
  fi
done
