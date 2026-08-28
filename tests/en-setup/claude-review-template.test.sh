#!/usr/bin/env bash
# Tests the Claude Code Review GitHub Action template — verifies it has the
# fields /en-setup will substitute and is structurally a valid GitHub Actions
# workflow.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="claude-review action template"

TEMPLATE="$REPO_ROOT/skills/en-setup/references/templates/github-workflow-claude-review.yml"

# --- Template exists ---
if [ -f "$TEMPLATE" ]; then
  pass "template file exists at $TEMPLATE"
else
  fail "template file missing" "expected: $TEMPLATE"
  report
  exit 1
fi

# --- Has the workflow name ---
if grep -q "^name: Claude Code Review" "$TEMPLATE"; then
  pass "workflow has 'name: Claude Code Review'"
else
  fail "workflow name missing or wrong"
fi

# --- Triggers on pull_request ---
if grep -q "pull_request:" "$TEMPLATE"; then
  pass "workflow triggers on pull_request"
else
  fail "workflow does not trigger on pull_request"
fi

# --- Includes opened and synchronize event types ---
if grep -qE "types:\s*\[opened, synchronize\]" "$TEMPLATE"; then
  pass "workflow handles opened and synchronize events"
else
  fail "workflow missing 'opened, synchronize' types"
fi

# --- Skips draft PRs ---
if grep -q "github.event.pull_request.draft == false" "$TEMPLATE"; then
  pass "workflow skips draft PRs"
else
  fail "workflow does not skip drafts (rate-limit risk)"
fi

# --- Has correct permissions ---
if grep -q "pull-requests: write" "$TEMPLATE" && grep -q "contents: read" "$TEMPLATE"; then
  pass "workflow has minimum permissions (contents:read, pull-requests:write)"
else
  fail "workflow permissions missing or incorrect"
fi

# --- Uses anthropics/claude-code-action ---
if grep -q "anthropics/claude-code-action" "$TEMPLATE"; then
  pass "workflow uses anthropics/claude-code-action"
else
  fail "workflow does not reference anthropics/claude-code-action"
fi

# --- v1: uses claude_code_oauth_token input (NOT anthropic_api_key for OAuth) ---
if grep -q "claude_code_oauth_token: " "$TEMPLATE"; then
  pass "workflow uses v1 claude_code_oauth_token input for OAuth"
else
  fail "workflow does not use v1 claude_code_oauth_token input — likely passing OAuth via anthropic_api_key (broken in v1)"
fi

# --- Defaults to OAuth secret CLAUDE_CODE_OAUTH_TOKEN ---
if grep -q "CLAUDE_CODE_OAUTH_TOKEN" "$TEMPLATE"; then
  pass "workflow references CLAUDE_CODE_OAUTH_TOKEN secret"
else
  fail "workflow does not reference CLAUDE_CODE_OAUTH_TOKEN secret"
fi

# --- Comment explains how to switch to API key auth ---
if grep -qi "ANTHROPIC_API_KEY" "$TEMPLATE"; then
  pass "comment shows how to switch to ANTHROPIC_API_KEY"
else
  fail "no documentation for switching to API key auth"
fi

# --- v1: does NOT use the removed `mode: review` input ---
if grep -qE "^[[:space:]]*mode: review" "$TEMPLATE"; then
  fail "workflow uses removed v0.x 'mode: review' input — must use prompt-based automation in v1"
else
  pass "workflow does not use removed 'mode: review' input"
fi

# --- v1: uses prompt-based automation with REPO and PR NUMBER context ---
if grep -q "prompt: " "$TEMPLATE" \
   && grep -q "REPO: \${{ github.repository }}" "$TEMPLATE" \
   && grep -q "PR NUMBER: \${{ github.event.pull_request.number }}" "$TEMPLATE"; then
  pass "workflow uses v1 prompt-based automation with REPO + PR NUMBER context"
else
  fail "workflow missing v1 prompt-based automation context"
fi

# --- fetch-depth: 0 for diff context ---
if grep -q "fetch-depth: 0" "$TEMPLATE"; then
  pass "checkout uses fetch-depth: 0 for full history"
else
  fail "checkout does not include fetch-depth: 0 (diff context will be incomplete)"
fi

# --- Reference to setup docs ---
if grep -q "docs/integrations/anthropic-code-review-action.md" "$TEMPLATE"; then
  pass "template references the setup docs"
else
  fail "template does not link to docs/integrations/anthropic-code-review-action.md"
fi

# --- Setup doc exists ---
if [ -f "$REPO_ROOT/docs/integrations/anthropic-code-review-action.md" ]; then
  pass "setup doc exists at docs/integrations/anthropic-code-review-action.md"
else
  fail "setup doc referenced but not found"
fi

# --- /en-setup SKILL.md mentions claude-code-review.yml ---
SKILL="$REPO_ROOT/skills/en-setup/SKILL.md"
if grep -q "claude-code-review.yml" "$SKILL"; then
  pass "/en-setup mentions claude-code-review.yml"
else
  fail "/en-setup does not mention claude-code-review.yml"
fi

# --- /en-setup SKILL.md describes the install prompt ---
if grep -q "Anthropic's Claude Code Review GitHub Action" "$SKILL"; then
  pass "/en-setup includes install prompt for Anthropic action"
else
  fail "/en-setup does not include install prompt"
fi

# --- /en-setup references the template path ---
if grep -q "references/templates/github-workflow-claude-review.yml" "$SKILL"; then
  pass "/en-setup references the template path"
else
  fail "/en-setup does not reference the template path"
fi

report
