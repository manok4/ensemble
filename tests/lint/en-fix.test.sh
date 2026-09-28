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
#   NO SILENT MERGE        --auto-merge only when the user gave it.
#
# Negative controls at authoring: removing disable-model-invocation, moving the
# ship step above the receipt step, moving the /en-debug invoke into the
# improvement bullet, and deleting the post-review risk re-check each turned
# its assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-fix flow contract"

SK="$REPO_ROOT/skills/en-fix/SKILL.md"
assert_file_exists "$SK" "the skill exists"

# The number of the first Process step whose line matches a pattern.
step_of() { awk -v pat="$1" '/^## Process/{on=1; next} /^## /{on=0} on && /^[0-9]+\. / && $0 ~ pat {sub(/\..*/, ""); print; exit}' "$SK"; }
# The whole text of Process step N, sub-bullets included, on one line.
step_text() { awk -v n="$1" '/^## Process/{on=1; next} /^## /{on=0} on && /^[0-9]+\. /{cur=$0; sub(/\..*/, "", cur)} on && cur==n' "$SK" | tr '\n' ' '; }

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
if [ "$(printf '%s\n' $order | grep -c .)" -eq 10 ] && [ "$(printf '%s\n' $order | sort -n | tr '\n' ' ')" = "$order " ]; then
  pass "the ten steps run in order: $order"
else
  fail "the steps must run preflight, triage, branch, understand, change, risk, commit, review, receipt, ship" "got: $order"
fi

grep -qF 'ENSEMBLE_PEER_REVIEW=true' <<<"$(step_text "$pre")" \
  && pass "the preflight refuses to run inside a peer subprocess" \
  || fail "step $pre must stop under ENSEMBLE_PEER_REVIEW=true"

# --- /en-fix "login 500s when email is null": the bug path invokes /en-debug ---
und_text=$(step_text "$und")
first_debug=$(awk -v n="$und" '/^## Process/{on=1; next} /^## /{on=0} on && /^[0-9]+\. /{cur=$0; sub(/\..*/, "", cur)} on && cur==n && /invoke `\/en-debug`/{print; exit}' "$SK")
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
grep -qF '`<IDENT>-<slug>`' <<<"$(step_text "$brn")" \
  && pass "a Linear request branches as <IDENT>-<slug>" \
  || fail "step $brn must name the branch <IDENT>-<slug> for a Linear issue"

# --- /en-fix "make the CSV export include a header row": no /en-debug up front ---
impr=$(awk -v n="$und" '/^## Process/{on=1; next} /^## /{on=0} on && /^[0-9]+\. /{cur=$0; sub(/\..*/, "", cur)} on && cur==n && /\*\*Improvement:\*\*/{print; exit}' "$SK")
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

# --- stops ---
grep -qF 'Three failed attempts' <<<"$(step_text "$chg")" \
  && pass "a third failed attempt stops the run" \
  || fail "step $chg must stop after three failed attempts"
grep -qF 'stop with the change uncommitted' <<<"$(step_text "$rsk")" \
  && pass "a risk surface in the real diff stops before the commit" \
  || fail "step $rsk must stop with the change uncommitted"
rev_text=$(step_text "$rev")
grep -qF '/en-review --lite --mode headless' <<<"$rev_text" \
  && pass "the review is /en-review --lite --mode headless" \
  || fail "step $rev must invoke /en-review --lite --mode headless"
grep -qF 'At most two rounds' <<<"$rev_text" && grep -qF 'A P0 in either envelope' <<<"$rev_text" \
  && pass "a P0 or a second blocked round stops the run" \
  || fail "step $rev must cap review at two rounds and stop on a P0"
grep -qF 'run the step 7 risk check again' <<<"$rev_text" \
  && pass "review edits re-run the risk check" \
  || fail "step $rev must re-run the risk check after review edits"
rcp_text=$(step_text "$rcp")
grep -qF 'ensemble-verification-receipt" verify' <<<"$rcp_text" && grep -qF 'do not invoke `/en-ship`' <<<"$rcp_text" \
  && pass "a failed receipt stops the run before the ship" \
  || fail "step $rcp must verify the receipt and not invoke /en-ship on failure"
[ -x "$REPO_ROOT/skills/en-fix/scripts/ensemble-verification-receipt" ] \
  && pass "the receipt script is carried and executable" \
  || fail "skills/en-fix/scripts/ensemble-verification-receipt must be carried and executable"

grep -qF -- '`--auto-merge` only when the user gave them' <<<"$(step_text "$shp")" \
  && pass "--auto-merge reaches /en-ship only when given" \
  || fail "step $shp must pass --auto-merge only when the user gave it"
grep -qF 'never a host substitution such as `$ARGUMENTS`' "$SK" \
  && pass "sub-skills receive the user's words, not \$ARGUMENTS (D70)" \
  || fail "SKILL.md must pass words, never \$ARGUMENTS (D70)"

report
