#!/usr/bin/env bash
# tests/lint/en-review-adopted.test.sh
#
# Four mechanisms adopted from the external review skills, each covering
# something the persona roster structurally could not.
#
# THE SPEC AXIS. Four personas judge the diff on its own terms — correct,
# tested, maintainable, conventional — and all four can pass on a change that
# implements the wrong thing. Step 5 already read the plan and did nothing with
# it, so the input was there and unused. From matt-pocock's code-review, whose
# central claim is that the axes must not be reranked: merging them is what
# lets one mask the other.
#
# THE SOURCE-GREP ANTI-PATTERN. From no-mistakes, and it indicts this repo:
# eight guards written during this refactor passed while asserting nothing,
# every one a prose grep satisfied by an incidental mention. A test that reads
# source proves nothing, because matched text can be dead and a
# behaviour-preserving refactor breaks it while the behaviour holds.
#
# THE SMELL FLOOR. The maintainability persona had no floor when a repo
# documents nothing, which makes its output taste rather than a finding. Twelve
# named smells, bounded by two rules so the floor cannot override the project.
#
# CLARIFY BEFORE APPLYING. From superpowers/receiving-code-review. The
# two-phase protocol freezes an authorized set before editing; it cannot help if
# the set was frozen around a misread finding.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review adopted mechanisms"

SKILL="$REPO_ROOT/skills/en-review/SKILL.md"
BRIEF="$REPO_ROOT/skills/en-review/references/peer-brief.md"

# --- 1. the spec axis: all three finding kinds, anchored to U-IDs ---
missing=""
for k in 'does this diff do what the plan asked' 'Missing:' 'Unasked-for:' 'Implemented but wrong:' 'U-ID'; do
  grep -qF "$k" "$SKILL" || missing="$missing '$k'"
done
[ -z "$missing" ] \
  && pass "the spec axis asks its three questions and anchors findings to U-IDs" \
  || fail "the spec axis is incomplete" "missing:$missing"

# --- 2. and it is not reranked against the personas ---
# The whole point of a second axis is lost the moment it is merged into one list.
if grep -qiE 'Do not rerank these against persona findings' "$SKILL"; then
  pass "spec findings are not reranked against persona findings"
else
  fail "the spec axis must not be reranked into the persona findings" \
       "merging the axes is what lets clean code mask the wrong feature"
fi

# --- 3. it runs before dispatch, and degrades honestly with no plan ---
axis=$(grep -n 'Requirements coverage (the spec axis)' "$SKILL" | head -1 | cut -d: -f1)
# The dispatch step was renamed when the three review modes landed; anchor on
# the step's number-and-name rather than its old prose.
disp=$(grep -n '^8\. \*\*Dispatch, per review mode' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$axis" ] && [ -n "$disp" ] && [ "$axis" -lt "$disp" ] \
   && grep -qiE 'say so in Coverage rather than silently omitting' "$SKILL"; then
  pass "the spec axis precedes dispatch and discloses its own absence"
else
  fail "the spec axis must precede dispatch and disclose when it is skipped" "axis=$axis dispatch=$disp"
fi

# --- 4. the source-grep anti-pattern, with its carve-outs ---
# Without the carve-outs this flags every legitimate snapshot and golden-file
# test, and a reviewer that cries wolf gets ignored wholesale.
if grep -qiE 'Tests that read source instead of running it' "$BRIEF" \
   && grep -qiE 'matched text can be dead' "$BRIEF" \
   && grep -qiE 'Two carve-outs' "$BRIEF"; then
  pass "the source-grep anti-pattern is flagged, with its carve-outs"
else
  fail "the testing dimension must flag source-grepping tests, and carve out real contracts"
fi

# --- 5. the smell floor, and the two rules that bind it ---
# Unbounded, a smell list overrides the project's own conventions and reports
# taste as violation.
if grep -qiE 'Floor when the repo documents nothing' "$BRIEF" \
   && grep -qiE 'documented repo standard always wins' "$BRIEF" \
   && grep -qiE 'every smell is a judgement call' "$BRIEF"; then
  pass "the maintainability floor is bounded by repo-overrides and judgement-call"
else
  fail "the smell floor needs both binding rules" \
       "unbounded, it reports taste as violation and overrides the project"
fi

# --- 6. clarify before applying ANY finding ---
clar=$(grep -n 'stops the whole phase' "$SKILL" | head -1 | cut -d: -f1)
coll=$(grep -n 'Collect ALL authorizations up front' "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$clar" ] && [ -n "$coll" ] && [ "$clar" -lt "$coll" ] \
   && grep -qiE 'apply nothing until they are answered' "$SKILL"; then
  pass "an ambiguous finding stops the phase before authorizations are collected"
else
  fail "clarification must precede authorization" \
       "freezing a set around a misread finding is what the protocol cannot undo"
fi

report
