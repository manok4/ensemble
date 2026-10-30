#!/usr/bin/env bash
# Tests for bin/ensemble-build-peer-prompt — the slim Outside Voice prompt
# assembler that skills shell out to instead of constructing the prompt by
# reasoning.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
# Repointed from en-build: D52 left it dispatching no peer and delegating
# simplification to /en-simplify, so it carries none of this machinery. The
# path now names the skill that owns it.
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

# EN24 U3: the peer checks for decisions a unit leaves to the implementer, at
# impact-based severity. A brief that capped H0 at P2 would demote a missing
# cross-unit signature, which is P1 everywhere else in the brief.
h0=$(printf '%s\n' "$out" | grep '^H0\. Decisions left to the implementer\.')
assert_contains "$h0" "P1 when the open choice changes a signature another unit consumes, or is a bet the plan states nowhere" "[plan] H0 is P1 for a cross-unit signature or an unstated bet"
assert_contains "$h0" "P2 otherwise" "[plan] H0 is P2 otherwise"

# EN24 U5: check H flags over-building. A goal-less unit is check A's, at A's
# severity, so H must not carry a cap that would demote it.
hh=$(printf '%s\n' "$out" | grep '^H\. Builds more than the goal needs\.')
assert_contains "$hh" "caching, queues or partitioning with no stated bottleneck" "[plan] check H names speculative build-out"
assert_contains "$hh" "A unit that serves no stated goal is not H; report it under A, at A's severity." "[plan] goal-less units route to check A"
assert_not_contains "$hh" "never P1" "[plan] check H carries no cap"

# EN24 U6: a plan peer's summary is a paraphrase the host checks against the
# goals; a code peer's is still an assessment.
assert_contains "$out" "is what this plan builds, in your own words" "[plan] summary is a paraphrase of the plan"

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
assert_not_contains "$out2" "is what this plan builds, in your own words" "[code] summary stays an assessment"

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

# --- Regression: the canonical template uses $VAR not {VAR} (P1 from Codex) ---
# Codex flagged that envsubst silently leaves {CURLY_BRACES} placeholders
# as literals, which would ship a literal template to the peer instead of
# the artifact. The template lived in outside-voice.md until 2026-09-04;
# since D50 the script's heredoc is the canonical text and the doc no longer
# duplicates it, so this reads the heredoc. Same guard, one source.
TEMPLATE_DOC="$REPO_ROOT/skills/en-review/scripts/ensemble-build-peer-prompt"

# Extract the heredoc body (cat <<PROMPT_EOF ... PROMPT_EOF).
template=$(awk '
  /^cat <<PROMPT_EOF/ { capture=1; next }
  capture && /^PROMPT_EOF/ { exit }
  capture { print }
' "$TEMPLATE_DOC")

if [ -z "$template" ]; then
  fail "[envsubst-doc] could not extract the prompt template heredoc from ensemble-build-peer-prompt"
else
  pass "[envsubst-doc] prompt template heredoc extractable from the script"
fi

# Any {CURLY_BRACES} placeholders in the extracted template would silently
# pass through envsubst as literals — that's the P1 bug. Reject them.
if echo "$template" | grep -qE '\{[A-Z_][A-Z_]*\}'; then
  bad=$(echo "$template" | grep -oE '\{[A-Z_][A-Z_]*\}' | sort -u | tr '\n' ' ')
  fail "[envsubst-doc] template contains {CURLY_BRACE} placeholders that envsubst will NOT substitute" "found: $bad"
else
  pass "[envsubst-doc] template has no {CURLY_BRACE} placeholders (envsubst-compatible)"
fi

# Every substituted variable must be referenced in the template. (The artifact
# type is a literal per copy since D50, not a variable.)
for v in '$PROJECT_CONTEXT' '$GOAL' '$ARTIFACT_BODY' '$PEER_MODE' '$SINGLE_AGENT_NOTE' '$PLAN_REVIEW_DIMENSIONS' '$ITERATION_CONTEXT'; do
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

# --- code variant: a large diff is capped at file boundaries (D134) ----------
CBIN="$REPO_ROOT/skills/en-review/scripts/ensemble-build-peer-prompt"
CBRIEF="$REPO_ROOT/skills/en-review/references/peer-brief.md"
mkdiff() {  # <files> <lines per file>
  local i j
  for i in $(seq 1 "$1"); do
    printf 'diff --git a/src/f%s.js b/src/f%s.js\n--- a/src/f%s.js\n+++ b/src/f%s.js\n@@ -1 +1,%s @@\n' "$i" "$i" "$i" "$i" "$2"
    for j in $(seq 1 "$2"); do printf '+const line_%s_%s = %s;\n' "$i" "$j" "$j"; done
  done
}
cprompt() { "$CBIN" --brief "$CBRIEF" --project-context P --goal G --artifact-stdin "$@"; }
# The cap leaves a file out only when the peer can read it from the tree, so
# these run in a real repo where the post-image hashes can be checked.
CREPO=$(mktemp -d)
git -C "$CREPO" init -q
git -C "$CREPO" config user.email t@example.com; git -C "$CREPO" config user.name t
mkdir -p "$CREPO/src" "$CREPO/docs"
for i in 1 2 3 4 5 6; do seq 1 200 | sed "s/^/const line_${i}_/; s/\$/ = 1;/" > "$CREPO/src/f$i.js"; done
seq 1 300 | sed 's/^/x/' > "$CREPO/docs/a b.md"
seq 1 2000 | sed 's/^/gone /' > "$CREPO/src/old.js"
git -C "$CREPO" add -A; git -C "$CREPO" commit -qm base
for i in 1 2 3 4 5 6; do seq 1 200 | sed "s/^/const line_${i}_/; s/\$/ = 2;/" > "$CREPO/src/f$i.js"; done
seq 1 300 | sed 's/^/y/' > "$CREPO/docs/a b.md"
git -C "$CREPO" rm -q src/old.js
git -C "$CREPO" add -A; git -C "$CREPO" commit -qm change
CBASE=$(git -C "$CREPO" rev-parse HEAD~1); CTIP=$(git -C "$CREPO" rev-parse HEAD)
cdiff() { git -C "$CREPO" diff "$CBASE" "$CTIP" -- "$@"; }
cin() { ( cd "$CREPO" && cprompt "$@" ); }

big=$(cdiff src/f1.js src/f2.js src/f3.js src/f4.js src/f5.js src/f6.js | cin --max-diff-bytes 12000)
assert_contains "$big" "NOT INLINED" "a diff over the cap says what it left out"
assert_contains "$big" "src/f1.js" "the first files are inlined"
printf '%s\n' "$big" | grep -q '^  src/f6.js (+200 -200)$' && pass "a left-out file is listed with its size" || fail "a left-out file is listed with its size" "$(printf '%s' "$big" | grep -A8 'NOT INLINED')"
inlined=$(printf '%s\n' "$big" | grep -c '^+const line_' || true)
[ $((inlined % 200)) -eq 0 ] && [ "$inlined" -gt 0 ] && pass "files are inlined whole, never cut mid-hunk ($inlined lines)" || fail "files are inlined whole" "$inlined lines"
# A path with a space makes the header ambiguous; the summary must still name it.
spaced=$(cdiff src/f1.js "docs/a b.md" | cin --max-diff-bytes 1000)
printf '%s\n' "$spaced" | grep -qF '  docs/a b.md (+300 -300)' && pass "a left-out path with a space is named" || fail "a left-out path with a space is named" "$(printf '%s' "$spaced" | grep -A4 'NOT INLINED')"
# Codex review on PR #132: a left-out hunk the tree cannot show is lost to the
# peer. A deleted file is absent from the tree, so it stays inline past the cap.
gone=$(cdiff src/f1.js src/old.js | cin --max-diff-bytes 5000)
printf '%s\n' "$gone" | grep -q '^-gone 2000$' && pass "a deleted file over the cap stays inline" || fail "a deleted file over the cap stays inline" "$(printf '%s' "$gone" | grep -A4 'NOT INLINED')"
# Reviewing a ref that is not checked out: the tree holds other content, so
# the hunk is inlined rather than pointed at.
git -C "$CREPO" checkout -q "$CBASE"
stale=$(cdiff src/f1.js src/f2.js | cin --max-diff-bytes 5000)
case "$stale" in *"NOT INLINED"*) fail "a file whose tree content differs is not left out" "$(printf '%s' "$stale" | grep -A4 'NOT INLINED')" ;; *) pass "a file whose tree content differs is not left out" ;; esac
git -C "$CREPO" checkout -q -
# Outside any repo nothing is readable, so a synthetic diff is never cut.
synth=$(mkdiff 6 200 | ( cd "$(mktemp -d)" && cprompt --max-diff-bytes 12000 ))
case "$synth" in *"NOT INLINED"*) fail "a diff with no readable tree is never cut" ;; *) pass "a diff with no readable tree is never cut" ;; esac
rm -rf "$CREPO"
small=$(mkdiff 2 5 | cprompt)
case "$small" in *"NOT INLINED"*) fail "a small diff is not capped" ;; *) pass "a small diff is not capped" ;; esac
plain=$(seq 1 5000 | sed 's/^/prose line /' | cprompt --max-diff-bytes 1000)
case "$plain" in *"NOT INLINED"*) fail "an artifact that is not a diff is never cut" ;; *) pass "an artifact that is not a diff is never cut" ;; esac
off=$(mkdiff 6 200 | cprompt --max-diff-bytes 0)
case "$off" in *"NOT INLINED"*) fail "--max-diff-bytes 0 disables the cap" ;; *) pass "--max-diff-bytes 0 disables the cap" ;; esac
assert_contains "$small" "stop well short of your turn limit" "the code peer is told to stop before its turn cap"
if mkdiff 1 1 | cprompt --max-diff-bytes lots >/dev/null 2>&1; then fail "a non-numeric cap is refused"; else pass "a non-numeric cap is refused"; fi


# --- --plan-before: the re-review sees what the fixes changed (EN24 U7) ---
# Counts alone cannot tell an added section from a rewritten one, so the
# builder renders the counts and a capped unified diff, and only on a re-review.
PB=$(mktemp -d)
printf '## Previous review context (iteration 1)\nApplied: 1-1 — Missing test\n' > "$PB/ctx"
printf '# Plan\n\n### U1. One\n\nbody\n' > "$PB/before"
printf '# Plan\n\n### U1. One\n\nbody\n\n## Rollout\n\nship it\n' > "$PB/after"
pb() { "$BIN" --brief "$REPO_ROOT/skills/en-plan/references/peer-brief.md" --project-context X --goal Y "$@"; }

grown=$(pb --artifact-file "$PB/after" --iteration-context-file "$PB/ctx" --plan-before "$PB/before")
assert_contains "$grown" "## Plan changes since the last pass" "[plan-before] the section is rendered"
assert_contains "$grown" "Units: 1 before, 1 now." "[plan-before] unit counts before and after"
assert_contains "$grown" "+## Rollout" "[plan-before] the diff shows the added section"
assert_contains "$grown" "no applied finding required. Severity P2." "[plan-before] the growth instruction is P2"

same=$(pb --artifact-file "$PB/before" --iteration-context-file "$PB/ctx" --plan-before "$PB/before")
assert_contains "$same" "No changes." "[plan-before] an identical plan says no changes"

# Same byte length, no unit added: counts are equal, so only the diff shows it.
printf '# Plan\n\n### U1. One\n\nydob\n' > "$PB/swapped"
swapped=$(pb --artifact-file "$PB/swapped" --iteration-context-file "$PB/ctx" --plan-before "$PB/before")
assert_contains "$swapped" "Bytes: 26 before, 26 now." "[plan-before] a same-size rewrite has equal counts"
assert_contains "$swapped" "+ydob" "[plan-before] and the diff still shows the replaced line"

seq 1 450 | sed 's/^/line /' > "$PB/long-before"; seq 1 450 | sed 's/^/LINE /' > "$PB/long-after"
long=$(pb --artifact-file "$PB/long-after" --iteration-context-file "$PB/ctx" --plan-before "$PB/long-before")
total=$(diff -u "$PB/long-before" "$PB/long-after" | wc -l | tr -d ' ')
assert_contains "$long" "($((total - 200)) lines not shown)" "[plan-before] a long diff is capped at 200 lines and says how much was cut"
assert_eq 200 "$(printf '%s\n' "$long" | sed -n '/^```diff$/,/^```$/p' | sed '1d;$d' | wc -l | tr -d ' ')" "[plan-before] exactly 200 diff lines are rendered"

pb --artifact-file "$PB/after" --iteration-context-file "$PB/ctx" --plan-before /nonexistent/plan.md >/dev/null 2>"$PB/err"
assert_exit_code 2 $? "[plan-before] an unreadable before-file exits 2"
assert_contains "$(cat "$PB/err")" "/nonexistent/plan.md" "[plan-before] the error names the path"
pb --artifact-file "$PB/after" --plan-before "$PB/before" >/dev/null 2>&1
assert_exit_code 2 $? "[plan-before] without --iteration-context-file exits 2"

plain=$(pb --artifact-file "$PB/after" --iteration-context-file "$PB/ctx")
assert_not_contains "$plain" "Plan changes since" "[plan-before] no flag, no section"
rm -rf "$PB"

report
