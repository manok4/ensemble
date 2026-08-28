#!/usr/bin/env bash
# Tests for bin/ensemble-build-peer-prompt — the slim Outside Voice prompt
# assembler that skills shell out to instead of constructing the prompt by
# reasoning.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-build-peer-prompt"

BIN="$REPO_ROOT/skills/en-plan/scripts/ensemble-build-peer-prompt"

# --- Required-arg validation ---
if "$BIN" 2>/dev/null; then
  fail "no args should error" "exit 0 unexpectedly"
else
  pass "no args exits non-zero"
fi

if "$BIN" --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" --project-context X --goal Y 2>/dev/null; then
  fail "missing artifact source should error"
else
  pass "missing --artifact-file/--artifact-stdin exits non-zero"
fi

if "$BIN" --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" --project-context X --goal Y --artifact-stdin --peer-mode bogus </dev/null 2>/dev/null; then
  fail "invalid --peer-mode should error"
else
  pass "invalid --peer-mode exits non-zero"
fi

# --- Cross-agent + plan: smoke ---
out=$(echo "fake plan body" | "$BIN" \
  --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" \
  --project-context "Test project" \
  --goal "Test goal" \
  --artifact-stdin \
  --peer-mode cross-agent)

if echo "$out" | grep -q "Peer review of a plan"; then
  pass "[cross-agent/plan] header includes artifact type"
else
  fail "[cross-agent/plan] header missing" "$(echo "$out" | head -3)"
fi

if echo "$out" | grep -q "PROJECT: Test project"; then
  pass "[cross-agent/plan] project context substituted"
else
  fail "[cross-agent/plan] project context missing"
fi

if echo "$out" | grep -q "GOAL: Test goal"; then
  pass "[cross-agent/plan] goal substituted"
else
  fail "[cross-agent/plan] goal missing"
fi

if echo "$out" | grep -q "Plan review dimensions:"; then
  pass "[cross-agent/plan] plan-specific block included for artifact-type=plan"
else
  fail "[cross-agent/plan] plan-specific block missing"
fi

if echo "$out" | grep -q "fake plan body"; then
  pass "[cross-agent/plan] artifact body included"
else
  fail "[cross-agent/plan] artifact body missing"
fi

if echo "$out" | grep -q 'echo "cross-agent"'; then
  pass "[cross-agent/plan] PEER_MODE substituted in echo instruction"
else
  fail "[cross-agent/plan] PEER_MODE substitution missing"
fi

if echo "$out" | grep -q "Single-agent fallback"; then
  fail "[cross-agent/plan] single-agent note should NOT appear in cross-agent mode"
else
  pass "[cross-agent/plan] single-agent note suppressed"
fi

# --- Code artifact + single-agent fallback ---
# EN13 U5-U7: there is no artifact-type mode any more. Each peer skill owns a
# builder and a brief, so the code case is en-review's builder, not a flag on
# en-plan's.
out2=$(echo "function foo() {}" | "$REPO_ROOT/skills/en-review/scripts/ensemble-build-peer-prompt" \
  --brief "$REPO_ROOT/skills/en-review/references/peer-brief.md" \
  --project-context "X" \
  --goal "Y" \
  --artifact-stdin \
  --peer-mode single-agent-fallback)

if echo "$out2" | grep -q "Peer review of a code"; then
  pass "[code/single] header reflects artifact type code"
else
  fail "[code/single] header missing"
fi

if echo "$out2" | grep -q "Single-agent fallback"; then
  pass "[code/single] single-agent note included"
else
  fail "[code/single] single-agent note missing"
fi

# Before U6 this block was the empty string for code review. The assertion
# inverts: the code dimensions must be PRESENT, and the plan ones absent.
if echo "$out2" | grep -q "### correctness"; then
  pass "[code/single] code dimensions present (they were empty before U6)"
else
  fail "[code/single] code dimensions missing"
fi
if echo "$out2" | grep -q "Plan review dimensions:"; then
  fail "[code/single] plan dimensions leaked into a code review"
else
  pass "[code/single] plan dimensions absent from a code review"
fi

if echo "$out2" | grep -q 'echo "single-agent-fallback"'; then
  pass "[code/single] PEER_MODE substituted to single-agent-fallback"
else
  fail "[code/single] PEER_MODE substitution wrong"
fi

# --- Iteration-context file ---
TMP_IT=$(mktemp)
cat > "$TMP_IT" <<'EOF'
## Previous review context (iteration 1)
Applied: 1-1 — Race in refresh path
Deferred: 1-2 — Edge case (rationale: low conf)
EOF

out3=$(echo "fake plan v2" | "$BIN" \
  --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" \
  --project-context "X" \
  --goal "Y" \
  --artifact-stdin \
  --iteration-context-file "$TMP_IT")

if echo "$out3" | grep -q "Previous review context (iteration 1)"; then
  pass "[iter-context] iteration context section appears in output"
else
  fail "[iter-context] iteration context missing" "$(echo "$out3" | tail -10)"
fi

if echo "$out3" | grep -q "Applied: 1-1"; then
  pass "[iter-context] iteration context body included"
else
  fail "[iter-context] iteration context body missing"
fi

rm -f "$TMP_IT"

# --- Iteration-context file missing → should error ---
if "$BIN" --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" --project-context X --goal Y --artifact-stdin --iteration-context-file /nonexistent/path </dev/null 2>/dev/null; then
  fail "missing iteration context file should error"
else
  pass "missing --iteration-context-file path exits non-zero"
fi

# --- File-based artifact input ---
TMP_PLAN=$(mktemp)
cat > "$TMP_PLAN" <<'EOF'
# FR99 - Test plan
### U1. Drop legacy table
- **Goal:** cleanup
- **Risk:** destructive
EOF
out4=$("$BIN" \
  --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" \
  --project-context "X" \
  --goal "Y" \
  --artifact-file "$TMP_PLAN" \
  --peer-mode cross-agent)

if echo "$out4" | grep -q "Drop legacy table"; then
  pass "[file-input] artifact-file content included"
else
  fail "[file-input] artifact-file content missing"
fi
rm -f "$TMP_PLAN"

# --- Output token-count is meaningfully smaller than the old template ---
# The slim template scaffold (excluding ARTIFACT_BODY) stays well under the old
# verbose template. Ceiling raised 200 -> 300 in D50, deliberately and once:
# the scaffold now carries the severity definitions (the finalize-loop re-run
# gate keys off P0/P1, so the peer cannot be left to guess the scale) and the
# coverage field. Measured cost of the move: ~90 tokens per peer call against a
# ~5,600-token plan artifact — under 2% — for a peer that grades to a stated
# scale instead of an invented one. The guard stays live at the new ceiling;
# raise it again only with the same kind of justification, never to fit a diff.
# Empty-artifact stress test.
#
# This guard used to read 270 words, and only because it passed
# --artifact-type code, which produced an EMPTY dimensions block. It was
# measuring the scaffold by accident, and the accident was the defect U6
# removed: code review really was going out with no dimensions.
#
# So it measures the scaffold deliberately now — the prompt minus whatever the
# brief contributes. That number is comparable to the old one (308 vs 270; the
# growth is the peer-contract reference and the brief pointer) and it still
# fails if the boilerplate creeps, which is what the guard is for. The
# dimensions themselves are budgeted by the brief's own review, not here.
out5=$(echo "" | "$BIN" \
  --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" \
  --project-context "P" \
  --goal "G" \
  --artifact-stdin \
  --peer-mode cross-agent)
dims_words=$(echo "$out5" | sed -n '/Plan review dimensions/,/Do NOT flag/p' | wc -w | tr -d ' ')
total_words=$(echo "$out5" | wc -w | tr -d ' ')
scaffold_words=$(( total_words - dims_words ))
if [ "$scaffold_words" -lt 350 ]; then
  pass "[size] prompt scaffold is under 350 words ($scaffold_words, excluding $dims_words of dimensions)"
else
  fail "[size] prompt scaffold too large" "$scaffold_words words excluding dimensions (target <350)"
fi

# And the dimensions must actually be there — a zero-word block would make the
# scaffold check pass while reproducing the bug it replaced.
if [ "$dims_words" -gt 50 ]; then
  pass "[size] the dimensions block is non-empty ($dims_words words)"
else
  fail "[size] dimensions block empty or missing" "$dims_words words"
fi

# --- Regression: the doc template uses $VAR not {VAR} (P1 from Codex) ---
# Codex flagged that envsubst silently leaves {CURLY_BRACES} placeholders
# as literals, which would ship a literal template to the peer instead of
# the artifact. Fix: the template now uses shell-style $VAR placeholders so
# both `bin/ensemble-build-peer-prompt` (HEREDOC) and raw envsubst work.
# This test guards against drift back to the {VAR} form.
TEMPLATE_DOC="$REPO_ROOT/skills/en-build/references/outside-voice.md"

# Extract just the prompt template block (the first ```text ... ``` fence).
template=$(awk '
  /^```text/ { capture=1; next }
  capture && /^```/ { exit }
  capture { print }
' "$TEMPLATE_DOC")

if [ -z "$template" ]; then
  fail "[envsubst-doc] could not extract prompt template from outside-voice.md"
else
  pass "[envsubst-doc] prompt template block extractable from doc"
fi

# Any {CURLY_BRACES} placeholders in the extracted template would silently
# pass through envsubst as literals — that's the P1 bug. Reject them.
if echo "$template" | grep -qE '\{[A-Z_][A-Z_]*\}'; then
  bad=$(echo "$template" | grep -oE '\{[A-Z_][A-Z_]*\}' | sort -u | tr '\n' ' ')
  fail "[envsubst-doc] template contains {CURLY_BRACE} placeholders that envsubst will NOT substitute" "found: $bad"
else
  pass "[envsubst-doc] template has no {CURLY_BRACE} placeholders (envsubst-compatible)"
fi

# All seven documented variables must be referenced in the template.
for v in '$ARTIFACT_TYPE' '$PROJECT_CONTEXT' '$GOAL' '$ARTIFACT_BODY' '$PEER_MODE' '$SINGLE_AGENT_NOTE' '$PLAN_REVIEW_DIMENSIONS'; do
  if echo "$template" | grep -qF "$v"; then
    pass "[envsubst-doc] template references $v"
  else
    fail "[envsubst-doc] template missing reference to $v"
  fi
done

# Optional functional smoke: only runs if envsubst is installed (gettext
# package; not on macOS by default). When available, we verify substitution
# actually replaces the placeholders.
if command -v envsubst >/dev/null 2>&1; then
  substituted=$(echo "$template" | env -i \
    ARTIFACT_TYPE=plan PROJECT_CONTEXT="Test project" GOAL="Test goal" \
    ARTIFACT_BODY="ARTIFACT-MARKER-12345" PEER_MODE=cross-agent \
    SINGLE_AGENT_NOTE="" PLAN_REVIEW_DIMENSIONS="" envsubst)
  if echo "$substituted" | grep -q "ARTIFACT-MARKER-12345"; then
    pass "[envsubst-doc] envsubst substitutes ARTIFACT_BODY into template (functional smoke)"
  else
    fail "[envsubst-doc] envsubst did not produce substituted output" "$(echo "$substituted" | head -5)"
  fi
else
  pass "[envsubst-doc] envsubst not installed; static checks above are sufficient"
fi

report
