#!/usr/bin/env bash
# tests/lint/en-fix.test.sh
#
# /en-fix writes code and opens a PR with no plan behind it, so the order of
# its steps and the stops between them are the safety property. Each assertion
# names the request that exercises it.
#
#   USER-INVOKED ONLY      disable-model-invocation; nothing invokes it, so it
#                          carries no CONTRACT.md.
#   ORDER                  preflight, triage, branch, understand, change, risk
#                          re-check, commit, review, receipt, ship.
#   BUG PATH ONLY          /en-debug is invoked for a bug, never up front for an
#                          improvement, and only a convergent verdict proceeds.
#   PRECEDENCE             the user's word beats a Linear Bug label.
#   STOPS                  three failed attempts, a P0 or a second blocked review,
#                          a risk surface after review, a failed receipt.
#   CLEAN START            tracked edits refuse the run, since /en-ship stages
#                          every tracked modification.
#   RECEIPT TARGET         /en-review runs with no target: the bare branch diff is
#                          the only one its post-review check writes a receipt for.
#   NO SILENT MERGE        --auto-merge only when the user gave it.
#
# Steps are referred to by title, never by number, so a reorder cannot leave a
# cross-reference pointing at the wrong step with every assertion green.
#
# Negative controls at authoring: removing disable-model-invocation, moving the
# ship step above the receipt step, moving the /en-debug invoke into the
# improvement bullet, deleting the post-review risk re-check, adding --base to
# the review invocation, and dropping the clean-tree refusal each turned its
# assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-fix flow contract"

SK="$REPO_ROOT/skills/en-fix/SKILL.md"
assert_file_exists "$SK" "the skill exists"

# The number of the first Process step whose line matches a pattern.
step_of() { awk -v pat="$1" '/^## Process/{on=1; next} /^## /{on=0} on && /^[0-9]+\. / && $0 ~ pat {sub(/\..*/, ""); print; exit}' "$SK"; }
# The lines of Process step N, one per output line, sub-bullets included.
step_lines() { awk -v n="$1" '/^## Process/{on=1; next} /^## /{on=0} on && /^[0-9]+\. /{cur=$0; sub(/\..*/, "", cur)} on && cur==n' "$SK"; }
# The whole text of Process step N on one line.
step_text() { step_lines "$1" | tr '\n' ' '; }
# The first line of Process step N that also matches an extended regex.
step_line_matching() { step_lines "$1" | grep -m1 -E "$2"; }

frontmatter=$(awk 'NR==1 && /^---$/{on=1; next} on && /^---$/{exit} on' "$SK")
printf '%s' "$frontmatter" | grep -qx 'disable-model-invocation: true' \
  && pass "it is user-invoked only" \
  || fail "SKILL.md must carry disable-model-invocation: true" \
          "a skill that pushes and opens a PR must not trigger on 'fix this typo'"
[ ! -f "$REPO_ROOT/skills/en-fix/CONTRACT.md" ] \
  && pass "it carries no CONTRACT.md, since no skill invokes it" \
  || fail "en-fix must not carry a CONTRACT.md" "contract-shape requires callers for one"

# --- order: every stop sits before the step it protects ---
pre=$(step_of 'Preflight');        tri=$(step_of 'Triage')
brn=$(step_of 'Branch');           und=$(step_of 'Understand the change')
chg=$(step_of 'Change, test-first'); rsk=$(step_of 'Risk re-check')
com=$(step_of '\\*\\*Commit');     rev=$(step_of '\\*\\*Review')
rcp=$(step_of 'Receipt gate');     shp=$(step_of '\\*\\*Ship')
order="$pre $tri $brn $und $chg $rsk $com $rev $rcp $shp"
# sort -nu drops duplicates, so two titles resolving to one step fail the count.
if [ "$(printf '%s\n' $order | sort -nu | grep -c .)" -eq 10 ] && [ "$(printf '%s\n' $order | sort -nu | tr '\n' ' ')" = "$order " ]; then
  pass "the ten checked steps run in strict order: $order"
else
  fail "the steps must run preflight, triage, branch, understand, change, risk, commit, review, receipt, ship" "got: $order"
fi

grep -qF 'ENSEMBLE_PEER_REVIEW=true' <<<"$(step_text "$pre")" \
  && pass "the preflight refuses to run inside a peer subprocess" \
  || fail "step $pre must stop under ENSEMBLE_PEER_REVIEW=true"
if grep -nE '\bstep [0-9]+|[Ss]teps [0-9]+' "$SK" >/dev/null; then
  fail "SKILL.md refers to steps by title, never by number" "$(grep -nE '\bstep [0-9]+|[Ss]teps [0-9]+' "$SK" | head -3)"
else
  pass "SKILL.md refers to steps by title, never by number"
fi

# --- /en-debug is never invoked before the bug/improvement split ---
early=""
i=1
while [ -n "$und" ] && [ "$i" -lt "$und" ]; do
  grep -qiF 'invoke `/en-debug`' <<<"$(step_text "$i")" && early="$early $i"
  i=$((i + 1))
done
[ -z "$early" ] \
  && pass "no step before Understand invokes /en-debug" \
  || fail "/en-debug must not be invoked before the bug/improvement split" "steps:$early"

# --- /en-fix "login 500s when email is null": the bug path invokes /en-debug ---
und_text=$(step_text "$und")
first_debug=$(step_line_matching "$und" 'invoke `/en-debug`')
printf '%s' "$first_debug" | grep -qF '**Bug:**' \
  && pass "the first /en-debug invoke is on the bug path" \
  || fail "the first 'invoke \`/en-debug\`' in step $und must be the **Bug:** bullet" "$first_debug"
grep -qF 'Only `convergent` proceeds' <<<"$und_text" \
  && pass "only a convergent diagnosis proceeds to an edit" \
  || fail "step $und must proceed only on a convergent verdict"
for v in divergent design-problem unresolved; do
  grep -qF "\`$v\`" <<<"$und_text" \
    && pass "a $v verdict is handled" \
    || fail "step $und must name the $v verdict"
done
grep -qE 'make no edit, and stop' <<<"$und_text" && grep -qF 'suggest `/en-brainstorm`' <<<"$und_text" \
  && pass "a non-convergent diagnosis stops with no edit, and a design problem suggests /en-brainstorm" \
  || fail "step $und must stop with no edit, suggesting /en-brainstorm on design-problem"

# --- /en-fix EMB-42 (Bug label, no other words): the issue text reaches /en-debug ---
grep -qF 'resolved issue or tracker text' <<<"$und_text" \
  && pass "an identifier-only request passes the resolved issue text to /en-debug" \
  || fail "step $und must pass the resolved issue or tracker text to /en-debug"
brn_text=$(step_text "$brn")
grep -qF 'record the pre-fix scope' <<<"$brn_text" && grep -qF 'fix-owned files' <<<"$brn_text" \
  && pass "the pre-fix scope is recorded before any edit (moved from /en-debug, D124)" \
  || fail "step $brn must record the pre-fix scope and track fix-owned files"
grep -qF '`<IDENT>-<slug>`' <<<"$brn_text" && grep -qF '`TD<N>-<slug>`' <<<"$brn_text" \
  && pass "a Linear request branches as <IDENT>-<slug>, a tracker entry as TD<N>-<slug>" \
  || fail "step $brn must name <IDENT>-<slug> and TD<N>-<slug> branches"
grep -qF 'Refuse to start while tracked files carry uncommitted edits' <<<"$brn_text" \
  && pass "a tree with uncommitted tracked edits refuses the run" \
  || fail "step $brn must refuse to start on uncommitted tracked edits" \
          "/en-ship stages every tracked modification, so they would ship with the fix"

# --- /en-fix "make the CSV export include a header row": no /en-debug up front ---
impr=$(step_line_matching "$und" '\*\*Improvement:\*\*')
printf '%s' "$impr" | grep -qF 'no `/en-debug`' && printf '%s' "$impr" | grep -qF 'three-line spec' \
  && printf '%s' "$impr" | grep -qF 'only when triage marked the request ambiguous' \
  && pass "an improvement skips /en-debug and confirms its spec only when ambiguous" \
  || fail "the **Improvement:** bullet must skip /en-debug, print a three-line spec, and confirm only when ambiguous" "$impr"

# --- /en-fix EMB-43 "this is an improvement" with a Bug label: the user wins ---
tri_text=$(step_text "$tri")
grep -qE "explicit word.*beats a Linear \`Bug\` label" <<<"$tri_text" \
  && pass "the user's explicit word outranks a Linear Bug label" \
  || fail "step $tri must rank the user's explicit word above a Linear Bug label"
grep -qF 'references/diff-signal-detection.md' <<<"$tri_text" && grep -qF 'suggest `/en-plan`' <<<"$tri_text" \
  && pass "triage checks the shared risk surface and suggests /en-plan when it fails" \
  || fail "step $tri must use references/diff-signal-detection.md and suggest /en-plan"
grep -qF '**Is it ambiguous?**' <<<"$tri_text" \
  && pass "triage makes the ambiguity call the Improvement bullet depends on" \
  || fail "step $tri must mark whether the request is ambiguous"

# --- stops ---
chg_text=$(step_text "$chg")
grep -qF 'Three failed attempts' <<<"$chg_text" \
  && pass "a third failed attempt stops the run" \
  || fail "step $chg must stop after three failed attempts"
grep -qF 'may be asserting behaviour that is correct' <<<"$chg_text" && grep -qF 'stop and ask' <<<"$chg_text" \
  && grep -qF 'explicitly invalidate the current theory' <<<"$chg_text" \
  && pass "an existing assertion is changed only once it is shown to encode the bug (D62)" \
  || fail "step $chg must guard existing assertions and invalidate failed theories (D62)"
grep -qF "Run Triage's size check again" <<<"$(step_text "$rsk")" && grep -qF 'stop with the change uncommitted' <<<"$(step_text "$rsk")" \
  && pass "the risk re-check reruns Triage's size check and stops before the commit" \
  || fail "step $rsk must rerun Triage's size check and stop uncommitted"

# --- /en-fix EMB-42 again: what the commit carries ---
com_text=$(step_text "$com")
missing=""
for need in 'fix-owned files only' 'never `git add -A`' 'Fixes <IDENT>' '## Resolved'; do
  grep -qF -- "$need" <<<"$com_text" || missing="$missing '$need'"
done
[ -z "$missing" ] \
  && pass "the commit stages fix-owned files only, references the issue and resolves the TD entry" \
  || fail "step $com is missing:$missing"

rev_text=$(step_text "$rev")
grep -qF 'Invoke `/en-review --lite --mode headless` with no target' <<<"$rev_text" \
  && ! grep -qF -- '--base' <<<"$rev_text" \
  && pass "the review runs on the bare branch diff, the target that writes a receipt" \
  || fail "step $rev must invoke /en-review --lite --mode headless with no target" \
          "post-review-check.md writes no receipt for a --base target, so the Receipt gate could never pass"
grep -qF 'At most two rounds' <<<"$rev_text" && grep -qF 'A P0 stops the run here' <<<"$rev_text" \
  && grep -qF 'Apply nothing yourself' <<<"$rev_text" && grep -qF 'never a `conflicting` finding' <<<"$rev_text" \
  && pass "round 1 stops on a P0 and never applies conflicting findings; round 2 applies nothing" \
  || fail "step $rev must cap review at two rounds, stop on a P0, skip conflicting findings, and apply nothing in round 2"
grep -qF 'commit every review edit' <<<"$rev_text" \
  && pass "round-1 review edits are committed before round 2 reviews them" \
  || fail "step $rev must commit round-1 review edits before round 2"
grep -qF 'run the Risk re-check again' <<<"$rev_text" \
  && pass "review edits re-run the risk check" \
  || fail "step $rev must re-run the Risk re-check after review edits"
rcp_text=$(step_text "$rcp")
grep -qF 'ensemble-verification-receipt" verify' <<<"$rcp_text" && grep -qF 'do not invoke `/en-ship`' <<<"$rcp_text" \
  && pass "a failed receipt stops the run before the ship" \
  || fail "step $rcp must verify the receipt and not invoke /en-ship on failure"
grep -qF 'dropping `typecheck` when `AGENTS.md` declares no Typecheck command' <<<"$rcp_text" \
  && pass "the receipt gate requires typecheck only where the project declares one" \
  || fail "step $rcp must drop typecheck from --requires when none is declared"
[ -x "$REPO_ROOT/skills/en-fix/scripts/ensemble-verification-receipt" ] \
  && pass "the receipt script is carried and executable" \
  || fail "skills/en-fix/scripts/ensemble-verification-receipt must be carried and executable"

shp_text=$(step_text "$shp")
grep -qF 'Invoke `/en-ship`' <<<"$shp_text" \
  && pass "the ship step invokes /en-ship" \
  || fail "step $shp must invoke /en-ship"
grep -qF -- '`--auto-merge` only when the user gave them' <<<"$shp_text" \
  && pass "--auto-merge reaches /en-ship only when given" \
  || fail "step $shp must pass --auto-merge only when the user gave it"
grep -qF 'never a host substitution such as `$ARGUMENTS`' "$SK" \
  && pass "sub-skills receive the user's words, not \$ARGUMENTS (D70)" \
  || fail "SKILL.md must pass words, never \$ARGUMENTS (D70)"

report
