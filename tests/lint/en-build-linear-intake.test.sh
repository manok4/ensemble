#!/usr/bin/env bash
# tests/lint/en-build-linear-intake.test.sh
#
# EN18 U4. `/en-build ENG-412` fetches a plan from Linear and materializes it
# as a plan file, so everything downstream (the sub-state matrix, the hash
# baseline, the 9f checkpoint) stays untouched.
#
# The round-trip that used to sit here moved with the transform itself: EN19
# U1 put materialization in ensemble-linear-plan, and tests/linear-plan/
# exercises it against U1's real capture with its negative controls. This file
# now guards the routing: that intake fetches, hands the result to the script,
# and refuses on its exit code, rather than rebuilding the plan by hand.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build linear intake"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
PRE="$REPO_ROOT/skills/en-build/references/build-preflight.md"
FMT="$REPO_ROOT/skills/en-build/references/linear-plan-format.md"
IGNORE="$REPO_ROOT/.gitignore"
FIX="$REPO_ROOT/tests/fixtures/linear"

has()   { grep -qiE -- "$2" "$1" && pass "$3" || fail "$3" "missing from $(basename "$1"): $2"; }
# Across line breaks, so a clause can require two facts TOGETHER. BSD grep -z
# does not match across newlines despite the flag, and rejects intervals over
# 255; flattening with tr avoids both.
has_near() { tr '\n' ' ' < "$1" | grep -qiE -- "$2" && pass "$3" || fail "$3" "not found together in $(basename "$1"): $2"; }

# --- 1. intake runs the script, never a hand-built plan (EN19 U2, D119) ----
has "$PRE" 'ensemble-linear-plan" materialize' "intake materializes through the script"
has "$PRE" 'Refuse on a non-zero exit, before any' "and refuses on its non-zero exit before any build work"
has "$PRE" 'D119' "the preflight doc cites D119"
has "$FMT" 'ensemble-linear-plan` is the one implementation' "the format doc names the script as its one implementation"
pre_line() { grep -n -- "$1" "$PRE" | head -1 | cut -d: -f1; }
f=$(pre_line 'list_issues` with its `parentId`'); m=$(pre_line 'ensemble-linear-plan" materialize')
if [ -n "$f" ] && [ -n "$m" ] && [ "$f" -lt "$m" ]; then pass "the fetch is described before the materialize call"
else fail "the fetch is described before the materialize call" "fetch=${f:-none} materialize=${m:-none}"; fi
hasnt() { grep -qiE -- "$2" "$1" && fail "$3" "present in $(basename "$1"): $2" || pass "$3"; }
hasnt "$PRE" 'Normalize `\* \*\*` back to `- \*\*` at the start' \
  "the preflight no longer tells the model to normalize markers itself"
[ -x "$REPO_ROOT/skills/en-build/scripts/ensemble-linear-plan" ] && pass "en-build carries the script" \
  || fail "en-build carries the script"
[ -f "$REPO_ROOT/tests/linear-plan/linear-plan.test.sh" ] && pass "the round-trip lives in tests/linear-plan/" \
  || fail "the round-trip lives in tests/linear-plan/"

# The fixtures the round-trip stands on must stay present and real.
for f in EN18-readback.json EN18-sample-plan.md README.md; do
  [ -s "$FIX/$f" ] && pass "fixture present: $f" || fail "fixture missing: $f"
done

# --- 2. mode comes from plan_store, not from the argument's shape ------------
# Selecting on shape alone lets `/en-build ENG-412` reach Linear in a repo
# configured local, which is the one thing the per-repo switch exists to
# prevent. All four combinations are named, and the refusal happens before any
# fetch and before the branch is created.
has "$SKILL" 'plan_store' "en-build resolves the mode from plan_store"
has "$PRE" 'plan_store' "the preflight doc carries the mode matrix"
has "$PRE" 'refuse' "a disallowed combination refuses"
has "$PRE" 'before any fetch|no fetch, no branch|before the branch is created' \
  "the refusal lands before any fetch and before the branch is created"
has "$PRE" 'mid-migration|still has plans on disk' \
  "a path under plan_store: linear is built rather than refused, and the prose says why"
has "$PRE" 'provenance' "the resolved mode is recorded as build provenance"

# --- 3. materialization, and what it is not ---------------------------------
has "$PRE" '\.ensemble/materialized-plans' "materialized plans land in .ensemble/materialized-plans/"
has "$PRE" 'overwritten|never merged' "a materialized file is overwritten, never merged"
has "$PRE" 'normali[sz]' "materialization normalizes the markers"
has "$FMT" 'normali[sz]' "the format doc owns the normalization rule both sides share"
has "$PRE" 'get_issue' "fetching is one list call plus a get_issue per unit"
has "$PRE" 'truncat' "because list_issues truncates descriptions"
has_near "$PRE" 'refuses a description still carrying Linear.s truncation marker' \
  "a description still carrying the truncation marker refuses"
has "$PRE" 'ensemble-plan-hash --full` against `plan_full_hash' \
  "intake compares the --full digest, not only the seven-field hash"
has "$PRE" '`repo` is not this repo' "intake refuses another repo's parent"
has "$FMT" 'plan_full_hash' "the format doc carries plan_full_hash in the Verification Contract"
has "$FMT" 'specified, not measured' "the format doc says the parent encoding is unmeasured"
has "$PRE" 'U-ID|U<N>' "units order by their U-ID suffix, not Linear's ordering"
has "$PRE" 'git tracked.*no|not git-tracked|never git-tracked' \
  "a materialized plan reads as untracked and must not trigger the auto-commit offer"

# --- 3b. malformed Linear data refuses, naming what is wrong ---------------
# All three are the ordinary result of someone hand-editing a parent in Linear,
# and guessing which sub-issue was meant is worse than stopping. The plan
# declared these scenarios; none had an assertion until the branch review.
has "$PRE" 'duplicate' "duplicate U-IDs refuse, naming the duplicate"
has "$PRE" 'unparseable|missing its `\(U<N>\)` suffix|does not resolve' \
  "an unresolvable identifier or a missing (U<N>) suffix refuses"
has "$PRE" 'write no file|writes no file' "and no materialized file is written"

# --- 3c. the config read is fail-closed, with the flags spelled out --------
# ensemble-config-get is fail-soft unless the caller opts in. U2 built --strict
# and --required for exactly this key and no call site asked for them, so
# `plan_store: Linear` fell through to local and the operator shipped believing
# a plan was published. Asserting the KEY NAME appears is not enough; the flags
# are the whole mechanism.
has "$PRE" 'allowed local,linear' "plan_store is read with --allowed local,linear"
has "$PRE" '\-\-strict' "and --strict, so a present-but-invalid value cannot fall through"
has "$PRE" 'linear_team' "linear_team is resolved"
has "$PRE" '\-\-required' "with --required, since it has no sensible default"
has_near "$PRE" 'linear_team[^#]{0,240}before any Linear call|before any Linear call[^#]{0,240}linear_team' \
  "and resolved before any Linear call, not after a parent exists"

# --- 4. the branch carries the identifier -----------------------------------
# This is the only thing that makes Linear's GitHub integration associate the
# PR with the plan. U5 hands the parent over assuming the link exists, and
# nothing else establishes it, so it is asserted here rather than there.
has "$SKILL" 'identifier' "the branch name carries the Linear identifier in linear mode"
has "$PRE" 'GitHub integration|associate the PR' \
  "the prose records why the branch name matters"

# --- 5. .gitignore, owned by the unit that writes there ----------------------
has "$IGNORE" '^\.ensemble/materialized-plans/' ".gitignore ignores .ensemble/materialized-plans/"
if git -C "$REPO_ROOT" check-ignore -q .ensemble/materialized-plans/ENG-412.md; then
  pass "git check-ignore confirms a materialized plan is ignored"
else
  fail "git check-ignore must ignore .ensemble/materialized-plans/"
fi

report
