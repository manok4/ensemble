#!/usr/bin/env bash
# Drift guards for the shared diff-signal-detection reference (FR01 U4).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Repointed from en-build: D52 left it dispatching no peer and delegating
# simplification to /en-simplify, so it carries none of this machinery. The
# path now names the skill that owns it.
TEST_NAME="diff-signal detection"

REF="$REPO_ROOT/skills/en-review/references/diff-signal-detection.md"

if [ -f "$REF" ]; then
  pass "diff-signal-detection.md exists"
else
  fail "diff-signal-detection.md missing"
fi

# --- fail-closed contract stated ---
if grep -qiE "fail.closed" "$REF"; then
  pass "states fail-closed contract"
else
  fail "must state fail-closed contract"
fi

# --- frontend patterns present ---
if grep -qF ".tsx" "$REF" && grep -qF "components/" "$REF"; then
  pass "documents frontend/UI patterns"
else
  fail "must document frontend/UI patterns"
fi

# --- risk-surface patterns present ---
if grep -qiE "auth" "$REF" && grep -qiE "migrations/" "$REF" && grep -qiE "payment" "$REF"; then
  pass "documents risk-surface patterns (auth/migrations/payments)"
else
  fail "must document risk-surface patterns"
fi

# --- a pattern names a concept (D139). max_tokens stopped /en-fix as if it were
# auth; a matcher that drops strings would miss SQL. Both directions are pinned.
missing=""
for need in 'A pattern names a concept, not a substring' 'max_tokens' 'only in a comment' 'a string literal' 'Unsure what it refers to:** a signal'; do
  grep -qF "$need" "$REF" || missing="$missing '$need'"
done
if [ -z "$missing" ]; then
  pass "risk patterns match the concept, keep strings, and fail closed when unsure"
else
  fail "the risk-pattern matching rule is incomplete" "missing:$missing"
fi

# --- a frontend path is a candidate. A path rule ran QA on a backend file under
# app/ and skipped a hook under src/hooks/, so both directions are pinned.
missing=""
for need in 'A path match is a candidate, not an answer' 'app/api/' 'robots.txt' 'src/hooks/useCart.ts' 'Unsure what it affects:** a frontend file'; do
  grep -qF "$need" "$REF" || missing="$missing '$need'"
done
if [ -z "$missing" ]; then
  pass "frontend paths are read as candidates, both ways, and fail closed when unsure"
else
  fail "the frontend matching rule is incomplete" "missing:$missing"
fi
if grep -qF 'cannot affect rendered UI' "$REF"; then
  fail "a file outside the patterns can still affect rendered UI"
else
  pass "does not claim a file outside the patterns cannot affect UI"
fi

# --- review depth moved to ensemble-review-tier (D140) ---
if grep -qE "UNCOUNTED_FILES|EXEC_LINES|is_low_risk|is_small_and_safe" "$REF"; then
  fail "the size and depth classifications must stay gone" "ensemble-review-tier owns review depth"
else
  pass "the size and depth classifications are gone"
fi
if grep -qF "ensemble-review-tier" "$REF"; then
  pass "says ensemble-review-tier owns review depth"
else
  fail "must say ensemble-review-tier owns review depth"
fi

# --- the remaining classification ---
if grep -qF "needs_browser" "$REF"; then
  pass "defines needs_browser (en-qa browser gate)"
else
  fail "must define needs_browser"
fi

report
