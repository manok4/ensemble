#!/usr/bin/env bash
# tests/lint/en-review-modes.test.sh
#
# Three mutually exclusive review modes replaced --peer / --no-peer /
# --peer-only, which had accumulated into a surface where --peer was a
# documented no-op, --no-peer meant personas-only, and --peer-only meant the
# thing --peer sounded like.
#
#   --peer   (default)  peer is the sole reviewer          was --peer-only
#   --cross             peer + personas, reconciled        was the default
#   --host              personas only                      was --no-peer
#
# THE RENAME HAZARD is what most of this file guards. /en-build's call was
# spelled --peer and meant peer-plus-personas. After the rename that same
# spelling means peer-SOLE — precisely the mode D46 removed from en-build for
# discarding every standards / testing / maintainability finding. The call had
# to move to --cross, and nothing about its spelling would have shown that.
# /en-loop moved the opposite way for the same reason in reverse.
#
# And the fallback flipped. With --peer as the default the peer is the only
# reviewer, so "no peer CLI" cannot mean "no review": the peer role runs on the
# host model in a fresh subprocess, recorded as single-agent-fallback so a
# same-model pass never reads as a cross-agent one.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review review modes"

SKILL="$REPO_ROOT/skills/en-review/SKILL.md"
BUILD="$REPO_ROOT/skills/en-build/SKILL.md"
LOOP="$REPO_ROOT/skills/en-loop/SKILL.md"

# --- 1. each mode says what it dispatches ---
missing=""
grep -qiE '`--peer`.*Default.*sole reviewer' "$SKILL" || missing="$missing peer-sole"
grep -qiE '`--cross`.*personas \*\*and\*\* the peer' "$SKILL" || missing="$missing cross-both"
grep -qiE '`--host`.*personas only' "$SKILL" || missing="$missing host-only"
[ -z "$missing" ] \
  && pass "all three modes state which sources they dispatch" \
  || fail "a review mode does not state what it dispatches" "missing:$missing"

# --- 2. the callers land on the right side of the rename ---
# This is the clause that would have caught the silent regression.
# Both directions. A presence-only check passed while the actual invocation had
# been switched back to --peer, because en-build names --cross elsewhere in prose
# — the precise failure this clause was written to catch, reproduced inside it.
# The post-build INVOCATION specifically. en-build also suggests an ad-hoc
# `/en-review --peer <sha>` on failing commits, a legitimate peer-sole use and
# not the review step this guards; a blanket ban on the string forbade it too.
if grep -qF -- "/en-review --cross --mode headless" "$BUILD" \
   && ! grep -qF -- "/en-review --peer --mode headless" "$BUILD"; then
  pass "/en-build's post-build review calls --cross, not the peer-sole mode (D46)"
else
  fail "/en-build's post-build review must call --cross" \
       "--peer is now peer-sole, the mode D46 removed for discarding host-only findings"
fi
if grep -qF -- "/en-review --peer --mode headless" "$LOOP" && ! grep -qF -- "/en-review --cross" "$LOOP"; then
  pass "/en-loop calls the peer-sole pass, not --cross"
else
  fail "/en-loop must stay peer-sole" "a persona roster per checkpoint multiplies cost where it compounds"
fi

# --- 3. --cross reports corroborated first, and drops nothing ---
# Reporting only the agreed set would discard peer-only findings, which are the
# reason to run a second model at all.
if grep -qiE 'corroborated. bucket first|corroborated findings reported first' "$SKILL" \
   && grep -qiE 'never dropped' "$SKILL" \
   && grep -qiE 'peer-only. is what the host missed' "$SKILL"; then
  pass "--cross leads with corroborated and still reports the other buckets"
else
  fail "--cross must lead with corroborated without dropping the other buckets" \
       "peer-only is what the host missed; discarding it defeats the second model"
fi

# --- 4. the fallback runs the peer role rather than skipping it ---
if grep -qiE 'single-agent-fallback. is ON' "$SKILL" \
   && grep -qiE 'cannot mean .no review.' "$SKILL" \
   && grep -qiE 'never reads as a cross-agent pass' "$SKILL"; then
  pass "no peer CLI runs the peer role on the host model, recorded as a fallback"
else
  fail "the no-peer-CLI fallback must run the peer role and record the weaker mode"
fi

# --- 5. the retired spellings stay retired ---
back=""
for gone in -- "--no-peer" "--peer-only"; do
  [ "$gone" = "--" ] && continue
  grep -qE "^\| \`$gone\`" "$SKILL" && back="$back $gone"
done
[ -z "$back" ] \
  && pass "the retired flag spellings are gone from the table" \
  || fail "a retired flag spelling is back" "$back"

# --- 5a. and gone from the STEPS, not just the table ------------------------
# The check above scanned only the flags table, and the retired spelling
# survived in the steps for three days short of a month: step 7's short-circuit
# was headed "Peer-only short-circuit (--peer-only)", step 9 labelled the
# --cross behaviour "Default" and the actual default "--peer-only", and two
# Reference-files entries carried it. A flag absent from its own table but
# instructed on in the flow is worse than one that is merely stale: the reader
# looks for it, does not find it, and has to guess which half is current.
#
# Historical prose is allowed and wanted — it is how a reader learns the
# spelling changed — so a line is exempt when it dates or names the change.
HIST='until 202[0-9]|former|renamed|supersed|was the mode|replaced by|no longer'
live=""
for gone in "--no-peer" "--peer-only"; do
  hits=$(grep -nF -- "$gone" "$SKILL" | grep -vE "$HIST" || true)
  [ -n "$hits" ] && live="$live $gone:$(printf '%s' "$hits" | cut -d: -f1 | tr '\n' ',')"
done
[ -z "$live" ] \
  && pass "no step instructs on a retired flag spelling" \
  || fail "a retired flag spelling is instructed on outside the table" "$live"

# The replacement has to be stated where the reader meets it: --peer is the
# default and it is peer-sole, --cross is the opt-in that adds personas. Step 9
# had these two exactly backwards, which no table check could see.
if grep -qE '\*\*`--peer` \(the default\), sole reviewer' "$SKILL" \
   && grep -qE '\*\*`--cross` \(personas \+ peer\)' "$SKILL"; then
  pass "step 9 attributes sole-reviewer to --peer and personas+peer to --cross"
else
  fail "step 9 must attribute sole-reviewer to --peer (the default) and personas+peer to --cross" \
       "these were labelled the other way round until 2026-09-04"
fi

report
