#!/usr/bin/env bash
# tests/lint/en-resolve-pr-seam.test.sh
#
# The contract between /en-ship and /en-resolve-pr, and the three rules the
# resolver owes on its own.
#
# D57 wrote this contract into en-ship alone. en-resolve-pr had never heard of
# it: it could block on a question inside an unattended watch loop, cycle three
# times inside each of the caller's two, and arm auto-merge the caller was
# deliberately holding back. A contract stated by one side is a hope.
#
# Every clause is scoped to ONE file and anchored on wording only that file
# carries. Whole-directory greps are what produced ~10 decorative guards earlier
# in this campaign; each was caught only by breaking the target.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-resolve-pr seam"
cd "$REPO_ROOT"

R=skills/en-resolve-pr/SKILL.md
S=skills/en-ship/SKILL.md

# "--" before the pattern: without it grep reads a pattern beginning with a dash
# as its own option, and every clause about a flag name silently fails.
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$(dirname "$1")")/$(basename "$1")"; }

# --- the process has a step 1 ------------------------------------------------
grep -qE '^1\. \*\*Resolve context' "$R" \
  && pass "the process has a step 1" \
  || fail "the process has a step 1" "it opened at step 2, as en-ship's did"

# --- authority is inherited, and stated from BOTH sides ----------------------
has "$R" "Authority is inherited, and narrowable only" "the resolver states its own authority bound"
has "$R" "Being invoked by another skill is not itself authorization" "invocation is not authorization"
has "$R" "never widen it"        "the bound may be narrowed, never widened"
has "$R" "this skill owns the fixes" "the resolver owns the fixes, not its caller"

# Each exclusion individually: a count would pass on four copies of one.
for x in merge rebase force-push "arming auto-merge"; do
  grep -qE "\*\*Excluded:\*\*[^|]*$x" "$R" \
    && pass "resolver exclusion listed: $x" \
    || fail "resolver exclusion listed: $x"
done

# --- unattended mode ---------------------------------------------------------
# The live bug this fixes: a needs-human item inside en-ship's unattended loop
# waited on a human who was not coming.
has "$R" "--orchestrated" "the resolver knows when it is being driven"
has "$R" "never block, and never call a question tool" "an orchestrated run does not ask questions"
has "$R" "stalls the loop indefinitely rather than failing" "the reason names the stall, not just the rule"
has "$R" "an open thread is the escalation ledger" "the open thread carries the escalation"

# --yes must be real consent, and must not be confusable with orchestration.
has "$R" "Standing consent to drive the whole run" "--yes is standing consent"
has "$R" "Only when the user has actually said so" "consent must have been given"
has "$R" "mutually exclusive" "--yes and --orchestrated cannot be combined"

# --- the retry budget does not compound --------------------------------------
has "$R" "do not cycle at all" "an orchestrated run does one pass"
has "$R" "Budgets that compound are budgets nobody can reason about" \
                                 "the compounding reason is recorded"

# --- auto-merge stays with whoever owns the lifecycle ------------------------
has "$R" "is refused under" "auto-merge is refused when orchestrated"
has "$R" "merge policy belongs to whoever owns the PR's lifecycle" "the reason is ownership, not caution"

# --- the caller's half -------------------------------------------------------
# The flag must actually be passed, or the resolver's whole orchestrated path is
# unreachable and every clause above describes behaviour nothing triggers.
has "$S" "/en-resolve-pr --orchestrated" "en-ship passes --orchestrated to the delegate"
has "$S" "Always pass \`--orchestrated\`" "en-ship states the flag is mandatory"

# Both sides must list the same exclusions. Drift here is how the contract went
# one-sided the first time.
for x in merge rebase force-push; do
  grep -qE "\*\*Excluded:\*\*[^|]*$x" "$S" \
    && pass "en-ship's exclusion still lists: $x" \
    || fail "en-ship's exclusion still lists: $x"
done

# --- the three standalone rules ----------------------------------------------
has "$R" "owes a regression test" "a reported bug owes a regression test"
has "$R" "fails before the fix and passes after it" "the regression test's shape is specified"
has "$R" "Convergence, not just count" "escalation reads the trend, not only the round"
has "$R" "prior evidence does not carry"  "a rebase invalidates the evidence around it"
RPF="$REPO_ROOT/skills/en-resolve-pr/references/resolve-pr-failures.md"
RPR="$REPO_ROOT/skills/en-resolve-pr/references/resolve-pr-reporting.md"
RPS="$REPO_ROOT/skills/en-resolve-pr/references/resolve-pr-situations.md"

# --- the two conditional situations, and their reachability ------------------
# Neither is a step: one fires on isOutdated, the other on a mid-review rebase.
# Both were inline and unguarded, so a later edit could have dropped either
# without anything noticing.
has "$RPS" "isOutdated=true"              "the outdated-thread procedure survives"
has "$RPS" "Walk location fields in order" "its location walk is specified, not implied"
has "$RPS" "grep the whole repo"          "an unfound anchor does not become a repo-wide search"
has "$R"   "references/resolve-pr-situations.md" "the flow reaches both situations"
# The rule that binds callers stays in the flow: a reader who never opens the
# reference must not conclude a rebase leaves the evidence standing.
has "$R"   "prior evidence does not carry" "the rebase rule is stated in the flow itself"

# --- the report shape --------------------------------------------------------
has "$RPR" "Merge readiness"              "the summary carries merge readiness"
has "$RPR" "Needs your input"             "needs-human items have their own line"
has "$R"   "references/resolve-pr-reporting.md" "the summary step reaches its shape"
# Routing stays in the flow: it differs per caller and is the part that decides
# whether an unattended run blocks.
has "$R"   "never block, and never call a question tool" \
                                           "--orchestrated never blocks for a decision"

has "$RPF" "Do not invent new behaviour"   "conflict resolution does not invent behaviour"
has "$R" "references/resolve-pr-failures.md" "the failure section reaches the table"

# A DIRTY tree used to be reported with nowhere to go.
grep -qE '\| .merge_state_status. is .DIRTY' "$RPF" \
  && pass "a conflicted merge state has a documented path" \
  || fail "a conflicted merge state has a documented path"

report
