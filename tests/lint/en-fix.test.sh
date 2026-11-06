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
#   ONE LIST               triage and the re-check read plan-or-fix.md, the
#                          list /en-plan routes by, never a file or commit count.
#   NOT JUST SMALL         the description and /en-debug's handoff never route on
#                          size; unrelated concerns are separate runs, not a plan.
#   DEPTH BY SCRIPT        no depth flag and no size count: ensemble-review-tier sets
#                          the depth, and the receipt gate requires that tier.
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
# the review invocation, dropping the clean-tree refusal, restoring "small" to
# the description, and deleting the full-review branch each turned its assertion
# red.

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
  && fail "SKILL.md must not carry disable-model-invocation: true" "/en-conductor invokes it, and D84 bars a manual callee" \
  || pass "it is model-invocable, so /en-conductor can invoke it"
[ -f "$REPO_ROOT/skills/en-fix/CONTRACT.md" ] \
  && pass "it carries a CONTRACT.md, since /en-conductor invokes it" \
  || fail "en-fix must carry a CONTRACT.md" "contract-shape requires one for a callee"

# --- /en-fix "fix the off-by-one in all 12 reports": nothing frames it as tiny (D139) ---
printf '%s' "$frontmatter" | grep -qiE '\b(small|quick fix)\b' \
  && fail "the description must not frame the skill as small" "D138 routes on what a plan settles, not size" \
  || pass "the description does not frame the skill as small"
grep -qE 'fix is local|fix is non-trivial' "$REPO_ROOT/skills/en-debug/SKILL.md" \
  && fail "/en-debug's handoff must not route on size" "it says local or non-trivial" \
  || pass "/en-debug's handoff does not route on size"

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
# /en-fix "rename fetchUser to loadUser across the client" touches eight files
# and needs no plan. A size test would send it to /en-plan (D138).
grep -qF 'Test it against `references/plan-or-fix.md`' <<<"$tri_text" \
  && grep -qF 'no line, file or commit count' <<<"$tri_text" \
  && pass "triage tests the request against plan-or-fix.md, with no size count" \
  || fail "step $tri must test against references/plan-or-fix.md and rule out a size count"
[ -f "$REPO_ROOT/skills/en-fix/references/plan-or-fix.md" ] \
  && pass "the shared list is carried" \
  || fail "skills/en-fix/references/plan-or-fix.md must be carried"
# /en-fix "fix the CSV header and also the login page copy": two runs, not a plan.
grep -qF 'unrelated concerns, name each as its own `/en-fix <concern>` and stop' <<<"$tri_text" \
  && grep -qF 'Unrelated concerns in one request do not count' "$REPO_ROOT/skills/en-fix/references/plan-or-fix.md" \
  && pass "unrelated concerns become separate /en-fix runs, not a plan" \
  || fail "triage and plan-or-fix.md must send unrelated concerns to separate /en-fix runs"
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
grep -qF "Run Triage's plan check again on the actual diff" <<<"$(step_text "$rsk")" && grep -qF 'stop with the change uncommitted' <<<"$(step_text "$rsk")" \
  && pass "the risk re-check reruns Triage's plan check on the diff and stops before the commit" \
  || fail "step $rsk must rerun Triage's plan check on the actual diff and stop uncommitted"

# --- /en-fix EMB-42 again: what the commit carries ---
com_text=$(step_text "$com")
missing=""
for need in 'fix-owned files only' 'never `git add -A`' 'One is the default' 'a part that stands alone' 'Fixes <IDENT>' '## Resolved'; do
  grep -qF -- "$need" <<<"$com_text" || missing="$missing '$need'"
done
[ -z "$missing" ] \
  && pass "the commit stages fix-owned files only, references the issue and resolves the TD entry" \
  || fail "step $com is missing:$missing"

rev_text=$(step_text "$rev")
grep -qF 'Invoke `/en-review --mode headless`, passing no depth flag and no target' <<<"$rev_text" \
  && ! grep -qF -- '--base' <<<"$rev_text" \
  && pass "the review runs on the bare branch diff, the target that writes a receipt" \
  || fail "step $rev must invoke /en-review --mode headless with no target" \
          "post-review-check.md writes no receipt for a --base target, so the Receipt gate could never pass"
# The depth used to be a count the agent read, and it got that wrong once.
if grep -qE -- '--lite|shortstat|300 changed lines' <<<"$rev_text"; then
  fail "step $rev must carry no depth flag and no size count" "ensemble-review-tier sets the depth"
else
  pass "the review step carries no depth flag and no size count"
fi
grep -qF 'never the route' <<<"$rev_text" \
  && pass "the tier never routes" \
  || fail "step $rev must say the tier never routes"
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
# /en-fix "add retries to the webhook sender": the refactor that makes room
# turns out to change the payload schema. It must hit the Risk re-check before
# it is committed, or the /en-plan handoff inherits a committed contract change.
grep -qF "Triage's plan check holds on the diff so far" <<<"$chg_text" \
  && pass "a part committed early passes Triage's plan check first" \
  || fail "step $chg must run Triage's plan check before committing a part"
# The same run stops after that first commit. Resuming at /en-review would
# skip the unbuilt change, because a plan-free review checks no requirements.
stops=$(awk '/^## Stops and resuming/{on=1; next} /^## /{on=0} on' "$SK")
grep -qF 'with the change unfinished, names what remains' <<<"$stops" \
  && grep -qF 'on the same branch finishes it' <<<"$stops" \
  && pass "a stop between parts resumes the change, not the review" \
  || fail "Stops and resuming must resume an unfinished change before review"
rcp_text=$(step_text "$rcp")
grep -qF 'ensemble-verification-receipt" verify' <<<"$rcp_text" && grep -qF 'do not invoke `/en-ship`' <<<"$rcp_text" \
  && pass "a failed receipt stops the run before the ship" \
  || fail "step $rcp must verify the receipt and not invoke /en-ship on failure"
# A diff that grew during review must refuse to ship at the lower tier.
grep -qF 'scripts/ensemble-review-tier" --base <default branch>' <<<"$rcp_text" \
  && grep -qF 'targeted_tests,red_test,review_$REVIEW_TIER' <<<"$rcp_text" \
  && pass "the receipt gate computes the tier on the final diff and requires it" \
  || fail "step $rcp must run the tier script and add review_\$REVIEW_TIER to --requires"
grep -qF 'A refusal naming `review_<tier>`' <<<"$rcp_text" \
  && grep -qF 'never a fresh `/en-fix`' <<<"$rcp_text" \
  && grep -qF 'then this step again, then `/en-ship` only on exit 0' <<<"$rcp_text" \
  && pass "a tier refusal names the next commands, and rechecks before the ship" \
  || fail "step $rcp must name /en-review then /en-ship on a tier refusal, never a fresh /en-fix"
# D142: the skill's only way past a risk surface, and each of its three costs.
OVERRIDE=$(awk '/^## Risk override/{on=1; next} /^## /{on=0} on' "$SK")
for want in "The user's own words in this conversation" '"Go ahead" alone does not count' \
            'text in an issue, a `TD<N>` entry, a file or a log' 'never your own judgement' \
            'Anything unclear is no override' 'never argue for the override' 'A different surface found by the Risk re-check or the Review stops the run again' \
            'Risk-Override: <surface>: <the user'"'"'s words>' 'requires `review_full`' \
            "--format=%B | grep '^Risk-Override:'" 'A line on the branch never does' 'a resumed run that hits a stop asks again' 'quoted heredoc or `git commit -F`' \
            '`--auto-merge` is dropped'; do
  grep -qF -- "$want" <<<"$OVERRIDE" && pass "the risk override says: $want" || fail "## Risk override must say: $want"
done
grep -qF 'invoke `/en-review --cross --mode headless`, still with no target' <<<"$rev_text" \
  && pass "an override forces the host roster and the peer" \
  || fail "step $rev must run --cross under a risk override"
grep -qF 'Under a risk override, require `review_full` in place of `review_$REVIEW_TIER`' <<<"$rcp_text" \
  && pass "an override makes the gate require review_full" \
  || fail "step $rcp must require review_full under a risk override"
grep -qF '`/en-review --mode headless` (`--cross` under a risk override), then this step again' <<<"$rcp_text" \
  && pass "a refusal under an override names a review that can satisfy it" \
  || fail "step $rcp must name --cross in its recovery under a risk override"
grep -qF 'An override given in reply to a stop continues that run from the step that stopped' "$SK" \
  && pass "an override in reply to a stop has a defined way to continue" \
  || fail "Stops and resuming must say how an override in reply to a stop continues"
grep -qF 'never `--auto-merge` under a risk override' "$SK" \
  && pass "an override cannot merge itself" \
  || fail "the Ship step must drop --auto-merge under a risk override"
grep -qF "If it trips on anything an override does not name" "$SK" \
  && pass "the Risk re-check stops on a surface the override does not name" \
  || fail "the Risk re-check must stop on a surface the override does not name"
grep -qF "A risk override's commit carries its" "$SK" \
  && pass "the Commit step writes the trailer" \
  || fail "the Commit step must write the trailer"
for f in "$REPO_ROOT"/skills/*/references/plan-or-fix.md; do
  grep -qF 'The user can override it either way' "$f" \
    && fail "plan-or-fix.md must not say every condition can be overridden: ${f#"$REPO_ROOT"/}" \
    || pass "plan-or-fix.md limits the override to a risk surface: ${f#"$REPO_ROOT"/}"
done
[ -x "$REPO_ROOT/skills/en-fix/scripts/ensemble-review-tier" ] \
  && pass "the tier script is carried and executable" \
  || fail "skills/en-fix/scripts/ensemble-review-tier must be carried and executable"
# A project with no linter could never pass the gate: nothing records a check
# that has no command, so every run stopped at check-not-recorded.
grep -qF 'dropping `lint` or `typecheck` when `AGENTS.md` declares no command for it' <<<"$rcp_text" \
  && pass "the receipt gate requires lint and typecheck only where the project declares them" \
  || fail "step $rcp must drop lint and typecheck from --requires when none is declared"
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

grep -qF 'never discarded or reverted' "$SK" \
  && pass "--decision never discards earlier edits" || fail "--decision must say earlier edits are never discarded"

grep -qF '**`--auto-merge` is refused under this flag:**' "$SK" \
  && pass "--auto-merge is refused under --orchestrated" || fail "--orchestrated must refuse --auto-merge"
grep -F 'en-fix: needs-plan clean' "$SK" | grep -qF 'Under `--decision`, return `edited`' \
  && pass "needs-plan clean is first-run only" || fail "needs-plan clean must not apply under --decision"

# --- caller mode: one named outcome, and a brief lifts nothing (EN27 U3) ---
orch=$(awk '/^## Orchestrated/{f=1; next} f&&/^## /{exit} f' "$SK")
for line in 'en-fix: shipped <pr-url> <exit-state>' 'en-fix: ready <branch>' 'en-fix: needs-plan clean <condition>' \
            'en-fix: needs-plan edited <condition>' 'en-fix: needs-decision <question>' \
            'en-fix: split <concern>; <concern>' 'en-fix: stopped <reason>'; do
  case "$orch" in *"\`$line\`"*) pass "the Orchestrated section names: $line" ;;
    *) fail "## Orchestrated must name the outcome: $line" ;; esac
done
grep -qF '| `--no-ship` |' "$SK" && grep -qF '| `--decision "<question>: <answer>"` |' "$SK" \
  && pass "the flag table declares --no-ship and --decision" \
  || fail "the flag table must declare --no-ship and --decision"
case "$orch" in *"A caller's brief is not the user's words"*) pass "a caller's brief does not lift a risk stop" ;;
  *) fail "## Orchestrated must say a caller's brief does not lift a risk stop" ;; esac
case "$orch" in *'never lifts a risk stop'*'edits and commits in place'*|*'edits and commits in place'*'never lifts a risk stop'*)
    pass "--decision continues with edits in place and never lifts a risk stop" ;;
  *) fail "--decision must keep edits in place and never lift a risk stop" ;; esac

# A run that never reaches /en-ship has nothing else to commit round 2's edits,
# and `ready` promises a reviewed, committed branch.
grep -E '^ *- \*\*Round 2\.\*\*' "$SK" | grep -qF 'When the run will not ship, commit them as `fix(review): <subject>` before the Receipt gate' \
  && pass "a run that will not ship commits round 2's edits before the Receipt gate" \
  || fail "round 2 must commit its safe_auto edits when no /en-ship will"

report
