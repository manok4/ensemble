#!/usr/bin/env bash
# Tests for skills/*/scripts/ensemble-verification-receipt (EN15 U1).
#
# This script is the one place that decides whether an expensive check can be
# skipped, so every refusal reason gets its own fixture. A receipt that wrongly
# reads as valid means /en-ship skips lint and tests and ships unverified code —
# the asymmetric failure this plan exists to avoid — so the bias throughout is
# that anything unclear must exit non-zero.
#
# Fixtures are real repos built with `git init` in a temp dir. Nothing here runs
# against the Ensemble checkout itself: a test that wrote a receipt into this
# repo's .git would leak state between runs.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="verification receipt"

R="$REPO_ROOT/skills/en-ship/scripts/ensemble-verification-receipt"
assert_file_exists "$R" "the receipt helper exists"
[ -x "$R" ] && pass "the receipt helper is executable" || fail "the receipt helper is executable"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

new_repo() {  # $1=name -> path; prints the path
  d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q . && git config user.email t@example.com && git config user.name tester \
      && printf 'one\n' > src.txt && git add src.txt && git commit -qm "init" ) >/dev/null 2>&1
  printf '%s\n' "$d"
}

# Runs the helper inside a fixture and reports "<exit> <reason>".
verdict() {  # $1=repo  $2..=args
  d="$1"; shift
  out=$( cd "$d" && "$R" verify --json "$@" 2>/dev/null ); rc=$?
  reason=$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("reason",""))
except Exception: print("UNPARSEABLE")' 2>/dev/null)
  printf '%s %s\n' "$rc" "$reason"
}

# --- happy path --------------------------------------------------------------
A=$(new_repo happy)
( cd "$A" && "$R" write --check full_suite=passed --check lint=passed --by en-build ) >/dev/null
assert_eq "0 ok" "$(verdict "$A" --requires full_suite,lint)" \
  "a fresh receipt satisfies the checks it recorded"

# --- no receipt at all -------------------------------------------------------
B=$(new_repo empty)
assert_eq "2 no-receipt" "$(verdict "$B")" \
  "a missing receipt is exit 2, distinct from an invalid one"

# --- fingerprint: tracked modification ---------------------------------------
C=$(new_repo tracked)
( cd "$C" && "$R" write --check full_suite=passed ) >/dev/null
printf 'two\n' >> "$C/src.txt"
assert_eq "1 fingerprint-mismatch" "$(verdict "$C")" \
  "editing a tracked file invalidates the receipt"

# --- fingerprint: untracked file ---------------------------------------------
# The case a name-only fingerprint would miss, and the one where being wrong is
# worst: a new source file's tests do not exist in the committed tree at all.
D=$(new_repo untracked)
( cd "$D" && "$R" write --check full_suite=passed ) >/dev/null
printf 'new\n' > "$D/added.txt"
assert_eq "1 fingerprint-mismatch" "$(verdict "$D")" \
  "an untracked file appearing invalidates the receipt"

# ...but an IGNORED file must not, or every build artifact would invalidate it.
E=$(new_repo ignored)
( cd "$E" && printf 'build/\n' > .gitignore && git add .gitignore && git commit -qm ignore ) >/dev/null
( cd "$E" && "$R" write --check full_suite=passed ) >/dev/null
mkdir -p "$E/build" && printf 'artifact\n' > "$E/build/out.o"
assert_eq "0 ok" "$(verdict "$E")" \
  "an ignored build artifact does not invalidate the receipt"

# --- fingerprint tracks the TREE, not HEAD -----------------------------------
# Amending only the message leaves the tree identical, so the tests still hold.
# Asserted so a refactor cannot quietly bind validity to head_sha instead.
F=$(new_repo amend)
( cd "$F" && "$R" write --check full_suite=passed ) >/dev/null
( cd "$F" && git commit -q --amend -m "reworded, same tree" ) >/dev/null 2>&1
assert_eq "0 ok" "$(verdict "$F")" \
  "rewording a commit does not invalidate an unchanged tree"

# --- base moved --------------------------------------------------------------
G=$(new_repo base)
( cd "$G" && git branch -q base-ref && "$R" write --check full_suite=passed --base base-ref ) >/dev/null
( cd "$G" && git checkout -q base-ref && printf 'moved\n' > other.txt \
    && git add other.txt && git commit -qm "base advances" && git checkout -q - ) >/dev/null 2>&1
assert_eq "1 base-moved" "$(verdict "$G")" \
  "the base advancing invalidates the receipt"

# A receipt written without a base makes no claim about one, so a moving base
# must not invalidate it. Otherwise every caller would be forced to pass --base.
H=$(new_repo nobase)
( cd "$H" && git branch -q base-ref && "$R" write --check full_suite=passed ) >/dev/null
( cd "$H" && git checkout -q base-ref && printf 'moved\n' > other.txt \
    && git add other.txt && git commit -qm "base advances" && git checkout -q - ) >/dev/null 2>&1
assert_eq "0 ok" "$(verdict "$H")" \
  "a receipt with no recorded base is not invalidated by the base moving"

# --- dependency changed ------------------------------------------------------
I=$(new_repo deps)
printf 'lock-v1\n' > "$I/uv.lock"
( cd "$I" && git add uv.lock && git commit -qm lock ) >/dev/null
( cd "$I" && "$R" write --check full_suite=passed --dep uv.lock ) >/dev/null
printf 'lock-v2\n' > "$I/uv.lock"
res=$(verdict "$I")
case "$res" in
  "1 dependency-changed") pass "a changed lockfile invalidates the receipt" ;;
  # A lockfile edit is also a tracked modification, so fingerprint-mismatch is a
  # correct refusal too — both are non-zero, which is what actually matters.
  "1 fingerprint-mismatch") pass "a changed lockfile invalidates the receipt (via fingerprint)" ;;
  *) fail "a changed lockfile invalidates the receipt" "got: $res" ;;
esac

# A DELETED dependency must not vanish from the comparison.
J=$(new_repo depgone)
printf 'lock\n' > "$J/uv.lock"
( cd "$J" && git add uv.lock && git commit -qm lock && "$R" write --check full_suite=passed --dep uv.lock ) >/dev/null
( cd "$J" && git rm -q uv.lock && git commit -qm "drop lock" ) >/dev/null
res=$(verdict "$J")
case "$res" in
  1\ *) pass "a deleted dependency invalidates the receipt ($res)" ;;
  *) fail "a deleted dependency invalidates the receipt" "got: $res" ;;
esac

# The two cases above both ALSO move the fingerprint, so either refusal is
# correct and neither proves the dependency comparison itself runs. Isolate it:
# a gitignored lockfile is excluded from the fingerprint by construction, so only
# the dependency check can refuse here. Without this the whole dependency path
# could be dead code and every test above would still pass.
I2=$(new_repo depisolated)
( cd "$I2" && printf 'vendor.lock\n' > .gitignore && git add .gitignore && git commit -qm ignore ) >/dev/null
printf 'lock-v1\n' > "$I2/vendor.lock"
( cd "$I2" && "$R" write --check full_suite=passed --dep vendor.lock ) >/dev/null
assert_eq "0 ok" "$(verdict "$I2")" "an unchanged ignored dependency leaves the receipt valid"
printf 'lock-v2\n' > "$I2/vendor.lock"
assert_eq "1 dependency-changed" "$(verdict "$I2")" \
  "a changed dependency is refused by the dependency check specifically"
rm "$I2/vendor.lock"
assert_eq "1 dependency-changed" "$(verdict "$I2")" \
  "a deleted dependency is refused by the dependency check specifically"

# --- wrong repo --------------------------------------------------------------
# A receipt copied into another checkout describes a tree this one cannot vouch
# for, even when the fingerprints coincidentally agree — which they do here,
# because both fixtures were built identically.
K=$(new_repo origin-repo)
L=$(new_repo other-repo)
( cd "$K" && "$R" write --check full_suite=passed ) >/dev/null
mkdir -p "$L/.git/ensemble" && cp "$K/.git/ensemble/receipt.json" "$L/.git/ensemble/receipt.json"
assert_eq "1 wrong-repo" "$(verdict "$L")" \
  "a receipt from another checkout is refused"

# --- expired -----------------------------------------------------------------
# Backdated rather than slept: deterministic, and the clock is the point.
M=$(new_repo expiry)
( cd "$M" && "$R" write --check full_suite=passed ) >/dev/null
python3 - "$M/.git/ensemble/receipt.json" <<'PY'
import json, sys, time, calendar
p = sys.argv[1]
r = json.load(open(p))
r['written_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - 7200))
json.dump(r, open(p, 'w'), indent=2, sort_keys=True)
PY
assert_eq "1 expired" "$(verdict "$M" --ttl 60)" \
  "a receipt older than the TTL is refused"
assert_eq "0 ok" "$(verdict "$M" --ttl 600)" \
  "the same receipt is accepted under a longer TTL"

# --- required check not recorded ---------------------------------------------
N=$(new_repo requires)
( cd "$N" && "$R" write --check full_suite=passed ) >/dev/null
assert_eq "1 check-not-recorded" "$(verdict "$N" --requires lint)" \
  "asking for a check the receipt never recorded is refused"
assert_eq "0 ok" "$(verdict "$N" --requires full_suite)" \
  "asking only for what was recorded succeeds"

# --- malformed ---------------------------------------------------------------
# Must never crash and must never pass. A half-written or hand-edited receipt is
# the case where a false positive is silent.
O=$(new_repo malformed)
( cd "$O" && "$R" write --check full_suite=passed ) >/dev/null
printf '{"schema": 1, "source_fing' > "$O/.git/ensemble/receipt.json"
assert_eq "1 malformed" "$(verdict "$O")" "a truncated receipt is refused, not crashed on"
printf 'not json at all\n' > "$O/.git/ensemble/receipt.json"
assert_eq "1 malformed" "$(verdict "$O")" "a non-JSON receipt is refused"
printf '{"schema": 99}\n' > "$O/.git/ensemble/receipt.json"
assert_eq "1 malformed" "$(verdict "$O")" "an unknown schema version is refused"

# --- only `passed` is recordable ---------------------------------------------
# Keeps "a receipt exists" and "something passed" the same statement, so no
# consumer has to check both.
P=$(new_repo failed)
if ( cd "$P" && "$R" write --check full_suite=failed ) >/dev/null 2>&1; then
  fail "recording a failed check is refused"
else
  pass "recording a failed check is refused"
fi

# --- --json shape ------------------------------------------------------------
Q=$(new_repo jsonshape)
( cd "$Q" && "$R" write --check full_suite=passed --by en-ship ) >/dev/null
shape=$( cd "$Q" && "$R" verify --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(",".join(k for k in ("valid","reason","checks","age_seconds","written_by") if k in d))')
assert_eq "valid,reason,checks,age_seconds,written_by" "$shape" \
  "verify --json carries the documented fields"

# --- the plan's stated assumption, checked -----------------------------------
# EN15 assumes hashing untracked non-ignored files is cheap. A repo with many
# large untracked files falsifies it. This is a sanity bound, not a benchmark:
# it fails only if the cost has become obviously wrong.
T=$(new_repo timing)
i=0; while [ "$i" -lt 200 ]; do printf 'padding line %s\n' "$i" > "$T/untracked-$i.txt"; i=$((i + 1)); done
start=$(date +%s)
( cd "$T" && "$R" write --check full_suite=passed ) >/dev/null
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -le 20 ]; then
  pass "fingerprinting 200 untracked files stays within a sane bound (${elapsed}s)"
else
  fail "fingerprinting 200 untracked files stays within a sane bound" \
       "took ${elapsed}s — EN15's cheap-hashing assumption is falsified; record the set, not the contents"
fi

report
