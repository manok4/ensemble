#!/usr/bin/env bash
# tests/lint/en-brainstorm-linear-intake.test.sh
#
# EN20 U1. /en-brainstorm takes a Linear issue identifier as its request, links
# the design it writes with `linear_issue:`, and comments on the issue. The
# flow is model-followed MCP calls, so this file guards the prose; the one
# deterministic step, finding the design by its link, is tested for real in
# tests/linear-plan/ (find-design).
#
# The clauses that matter most: admission matches /en-plan's (so the chain
# cannot dead-end), the issue's description and state are never edited (en-plan
# depends on both), and a topic match never resumes a design linked to another
# issue (it would overwrite the link and strand that issue).

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-brainstorm linear intake"

SKILL="$REPO_ROOT/skills/en-brainstorm/SKILL.md"
INTAKE="$REPO_ROOT/skills/en-brainstorm/references/brainstorm-from-linear.md"
TEMPLATE="$REPO_ROOT/skills/en-brainstorm/references/templates/design-doc-template.md"
FOUNDATION="$REPO_ROOT/docs/foundation.md"

has()      { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }
hasnt()    { grep -qiE -- "$2" "$1" && fail "$3" "present in $(basename "$1") but should not be: $2" || pass "$3"; }
has_near() { tr '\n' ' ' < "$1" | grep -qiE -- "$2" && pass "$3" || fail "$3" "not found together in $(basename "$1"): $2"; }
section()  { awk -v h="$2" 'index($0, h) == 1 {f=1; next} f && /^## /{exit} f' "$1"; }

assert_file_exists "$INTAKE" "the brainstorm intake reference exists"

# --- 1. routing ------------------------------------------------------------------
resume=$(awk '/^3\. \*\*Resume or start fresh/{f=1} f&&/^4\. \*\*/{exit} f' "$SKILL")
assert_contains "$resume" 'references/brainstorm-from-linear.md' "the resume step routes an identifier to the reference"
write=$(awk '/^15\. \*\*Write the design doc/{f=1} f&&/^16\. \*\*/{exit} f' "$SKILL")
assert_contains "$write" 'linear_issue: <IDENT>' "the write step adds linear_issue to the design"
has_near "$INTAKE" 'mode comes from `plan_store`, never from the argument.s shape' \
  "the mode comes from plan_store, as in /en-plan and /en-build"
has "$INTAKE" 'Under `local` an identifier refuses' "an identifier under plan_store: local refuses"
has "$INTAKE" 'ensemble-config-get" plan_store --allowed local,linear --default local --strict' \
  "plan_store is read fail-closed through the carried reader"

# --- 2. admission, before any Q&A ------------------------------------------------
ADMIT=$(section "$INTAKE" '## Admit the issue')
[ -n "$ADMIT" ] && pass "the admission section exists" || fail "the admission section exists"
assert_contains "$(printf '%s' "$ADMIT" | tr '\n' ' ')" 'team is not `linear_team`' "admission refuses another team"
assert_contains "$ADMIT" 'already has sub-issues' "admission refuses an issue already planned"
assert_contains "$ADMIT" 'started, completed or canceled' "admission refuses a started, completed or canceled issue"
assert_contains "$ADMIT" '/en-plan <IDENT>` admits by' "and says why: the rules match /en-plan's, so the chain cannot dead-end"
admit_line=$(grep -n '^## Admit the issue' "$INTAKE" | cut -d: -f1)
request_line=$(grep -n '^## The issue is the request' "$INTAKE" | cut -d: -f1)
if [ -n "$admit_line" ] && [ -n "$request_line" ] && [ "$admit_line" -lt "$request_line" ]; then
  pass "admission comes before the issue becomes the request"
else
  fail "admission comes before the issue becomes the request" "admit=${admit_line:-none} request=${request_line:-none}"
fi

# --- 3. the issue as the request, and resume by the link -------------------------
has "$INTAKE" 'every line prefixed `> `' "the issue is quoted as a blockquote, so its headings stay content"
RESUME=$(section "$INTAKE" '## Resume by the link first')
assert_contains "$RESUME" 'linear_issue: <IDENT>' "resume looks for the link first"
assert_contains "$(printf '%s' "$RESUME" | tr '\n' ' ')" 'a design already linked to a different issue is never a candidate' \
  "topic-match resume excludes a design linked to another issue"
assert_contains "$RESUME" 'Confirmation before resuming is unchanged' "and still confirms before resuming"

# --- 4. the link and the comment ------------------------------------------------
LINK=$(section "$INTAKE" '## Link the design')
assert_contains "$LINK" 'save_comment' "each write posts a comment on the issue"
assert_contains "$LINK" 'Design: <repo-relative path' "the comment's first line names the design"
assert_contains "$LINK" 'Next: /en-plan <IDENT>' "and its last line names the next step"
assert_contains "$LINK" 'One comment per write' "one comment per write, first or resumed"
assert_contains "$(printf '%s' "$LINK" | tr '\n' ' ')" 'A failed comment warns and does not fail the run' \
  "a failed comment warns rather than failing the run"
assert_contains "$(printf '%s' "$LINK" | tr '\n' ' ')" "Never edit the issue's description or state" \
  "the issue's description and state are never edited"
hasnt "$INTAKE" 'save_issue' "the reference never calls save_issue on the issue"

# --- 5. the worked example pins the shapes -----------------------------------------
has "$INTAKE" 'linear_issue: EMB-7' "the worked example shows the frontmatter key"
has "$INTAKE" '^`Design: docs/designs/2026-09-24-export-timeouts-design.md`' "the worked example shows the comment's first line"
has "$INTAKE" '^`Next: /en-plan EMB-7`' "and its last line"
has_near "$INTAKE" 'EMB-7.s design keeps\s+`linear_issue: EMB-7`' "the second-issue example keeps the first design's link"

# --- 6. template, foundation, budget ---------------------------------------------------
has "$TEMPLATE" '^# linear_issue: ' "the design template documents linear_issue as an optional key"
grep -qE '^- \*\*D120\.' "$FOUNDATION" && pass "D120 is recorded in the foundation" || fail "D120 is recorded in the foundation"
has "$INTAKE" 'D120' "the reference cites D120"

report
