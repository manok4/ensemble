#!/usr/bin/env bash
# tests/lint/en-build-linear-intake.test.sh
#
# EN18 U4. `/en-build ENG-412` fetches a plan from Linear and materializes it
# as a plan file, so everything downstream (the sub-state matrix, the hash
# baseline, the 9f checkpoint) stays untouched.
#
# The centre of this file is not a prose clause, it is the round-trip in
# section 1: U1's real capture, materialized per the documented rules, must
# canonicalize identically to the plan it was published from. That assertion
# is why the fixtures exist. Everything else guards the prose around it.
#
# Why it needs a negative control of its own: a plan materialized WITHOUT the
# marker normalization still hashes. It hashes seven EMPTY fields per unit, so
# every unit's digest is identical and the 9f checkpoint compares two
# meaningless values. A test that only asserted "hashing succeeded" would be
# green against exactly that bug.

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

# --- 1. the round-trip, against U1's real capture ----------------------------
# Materializes tests/fixtures/linear/EN18-readback.json per the format doc's
# rules and compares `ensemble-plan-hash --canon` against the plan it came
# from. Run twice: once normalized (must match) and once as-returned (must
# not), so the clause cannot pass for the wrong reason.
if ! command -v python3 >/dev/null 2>&1; then
  pass "SKIPPED: python3 not installed; the round-trip is unchecked on this machine"
else
  rt=$(python3 - "$REPO_ROOT" <<'PY'
import json, re, subprocess, sys, tempfile, os
root = sys.argv[1]
src = open(f"{root}/tests/fixtures/linear/EN18-sample-plan.md").read()
fm  = src.split('---', 2)[1]
cap = json.load(open(f"{root}/tests/fixtures/linear/EN18-readback.json"))

# U1 is the full-equality case. U2's captured description carries no Approach
# field, so it exercises ordering below but cannot prove field equality; the
# README records that only two of the source's four units were published.
expected = [s.rstrip() for s in re.split(r'(?m)^(?=### U)', src) if re.match(r'### U1\.', s)][0]
unit = [s for s in cap['sub_issues'] if s['u_id'] == 'U1'][0]

def wrap(body):
    return '---' + fm + '---\n\n# X\n\n## Implementation units\n\n' + body + '\n'

def canon(text):
    f = tempfile.NamedTemporaryFile('w', suffix='.md', delete=False)
    f.write(text); f.close()
    out = subprocess.run(['bash', f"{root}/skills/en-build/scripts/ensemble-plan-hash",
                          '--canon', f.name], capture_output=True, text=True).stdout
    os.unlink(f.name)
    return out

def materialize(normalize):
    body = re.sub(r'(?m)^\* \*\*', '- **', unit['description']) if normalize else unit['description']
    title = re.sub(r' \(U\d+\)$', '', unit['title'])
    return wrap('### ' + unit['u_id'] + '. ' + title + '\n\n' + body.rstrip())

want = canon(wrap(expected))
got_norm = canon(materialize(True))
got_raw  = canon(materialize(False))

# Ordering: list_issues returned updatedAt-descending, U2 before U1. A build
# that trusted that order would run the units backwards.
by_uid = [s['u_id'] for s in sorted(cap['sub_issues'], key=lambda s: int(s['u_id'][1:]))]
returned = cap['list_issues_order']

print('normalized_matches=' + ('yes' if got_norm == want else 'no'))
print('raw_matches=' + ('yes' if got_raw == want else 'no'))
print('raw_is_empty_fields=' + ('yes' if 'Goal:0:' in got_raw else 'no'))
print('uid_order=' + ','.join(by_uid))
print('returned_order=' + ','.join(returned))
PY
)
  assert_eq "yes" "$(printf '%s\n' "$rt" | sed -n 's/^normalized_matches=//p')" \
    "a materialized plan canonicalizes identically to the plan it was published from"
  # The control, asserted rather than assumed: without the normalization the
  # canonical form must NOT match. This is the clause that makes the one above
  # mean something.
  assert_eq "no" "$(printf '%s\n' "$rt" | sed -n 's/^raw_matches=//p')" \
    "skipping the marker normalization breaks the round-trip"
  assert_eq "yes" "$(printf '%s\n' "$rt" | sed -n 's/^raw_is_empty_fields=//p')" \
    "and it breaks it silently: the un-normalized form hashes seven empty fields"
  assert_eq "U1,U2" "$(printf '%s\n' "$rt" | sed -n 's/^uid_order=//p')" \
    "units order by their U-ID suffix"
  assert_eq "EMB-3,EMB-2" "$(printf '%s\n' "$rt" | sed -n 's/^returned_order=//p')" \
    "which is not the order Linear returned them in (updatedAt descending)"
fi

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
has_near "$PRE" 'Refuse[^#]{0,40}description still carrying that marker' \
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
