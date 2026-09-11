#!/usr/bin/env bash
# tests/en-setup/analytics-store-advisory.test.sh
#
# ~/.ensemble/analytics/guardrail.jsonl reached 8.6 MB and 71,171 events before
# anything told the operator it was there, and 97% of it was test noise. PR #108
# stopped it growing; nothing said the old data existed or what it was.
#
# So /en-setup's health walk reports an oversized store. What it must NOT do is
# call any of it safe to delete: the two files that live in that directory earn
# opposite advice, and after EN17 one of them is the only surviving record of
# runs whose per-clone ledgers are gone.
#
#   IT CLASSIFIES        guardrail.jsonl is a hook log; <repo>.jsonl is the
#                        durable rollup with no other copy. Different lines.
#   IT NEVER SAYS SAFE   asserted as an absence, because the phrase is the
#                        failure mode, not the wording.
#   IT NEVER BLOCKS      advisory only; the exit status is unchanged by it.
#   IT NEVER DELETES     the fixture is byte-compared before and after.
#
# Negative controls at authoring: raising the threshold above the fixture turned
# the happy-path assertions red; giving the rollup the guardrail file's advice
# turned the classification assertion red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup analytics store advisory"

CH="$REPO_ROOT/skills/en-setup/scripts/check-health"
assert_file_exists "$CH" "the health runner exists"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
A="$WORK/analytics"
mkdir -p "$A"
P="$WORK/proj"; mkdir -p "$P"
( cd "$P" && git init -q . && git config user.email t@e && git config user.name t )

# 6 MB, over the 5 MB threshold.
big() { dd if=/dev/zero bs=1024 count=6144 2>/dev/null | tr '\0' 'x' > "$1"; }
health() { ( cd "$P" && ENSEMBLE_ANALYTICS_DIR="$A" bash "$CH" 2>&1 ); }

# --- nothing oversized: no advisory at all -----------------------------------
printf '{"a":1}\n' > "$A/guardrail.jsonl"
out=$(health)
assert_not_contains "$out" "analytics:" "a small store produces no advisory"

# --- the hook log ------------------------------------------------------------
big "$A/guardrail.jsonl"
out=$(health)
assert_contains "$out" "analytics: guardrail.jsonl is 6 MB" "an oversized hook log is named, with its size"
assert_contains "$out" "hook-fire records" "and classified as a log of hook fires"
assert_contains "$out" "removing the file loses only that history" "with what removing it costs"
printf '%s' "$out" | grep -qi 'safe to delete' \
  && fail "the advisory calls an analytics file safe to delete" \
          "wrong for the rollup, presumptuous for the rest" \
  || pass "the hook-log advisory never says 'safe to delete', in any casing"

# --- the durable rollup earns the opposite advice ----------------------------
rm -f "$A/guardrail.jsonl"
big "$A/proj.jsonl"
out=$(health)
assert_contains "$out" "analytics: proj.jsonl is 6 MB" "an oversized rollup is named"
assert_contains "$out" "only surviving record" "and classified as the only copy of the data"
assert_contains "$out" "ensemble-metrics --time --json" "with the export command to run first"
printf '%s' "$out" | grep -qi 'safe to delete' \
  && fail "the rollup advisory calls it safe to delete" \
          "it is the only surviving copy of that data" \
  || pass "the rollup advisory never says 'safe to delete', in any casing"
assert_not_contains "$out" "hook-fire records" "the two files do not share advice"

# --- two oversized files, one line each --------------------------------------
big "$A/guardrail.jsonl"
out=$(health)
assert_eq "2" "$(printf '%s\n' "$out" | grep -c 'analytics: ')" "two oversized files get two lines"

# --- an unrecognised file is named and left alone ----------------------------
rm -f "$A/guardrail.jsonl" "$A/proj.jsonl"
big "$A/something-else.log"
out=$(health)
assert_contains "$out" "unrecognised. Left alone" "an unrecognised file gets no advice"

# --- advisory only: it never blocks, and never deletes -----------------------
before=$(shasum "$A/something-else.log" | awk '{print $1}')
rm -f "$A/something-else.log"
rc_clean=$( cd "$P" && ENSEMBLE_ANALYTICS_DIR="$A" bash "$CH" >/dev/null 2>&1; printf '%s' "$?" )
big "$A/proj.jsonl"
sum_before=$(shasum "$A/proj.jsonl" | awk '{print $1}')
rc_big=$( cd "$P" && ENSEMBLE_ANALYTICS_DIR="$A" bash "$CH" >/dev/null 2>&1; printf '%s' "$?" )
assert_eq "$rc_clean" "$rc_big" "the advisory does not change the exit status"
assert_file_exists "$A/proj.jsonl" "the file is still there afterwards"
assert_eq "$sum_before" "$(shasum "$A/proj.jsonl" | awk '{print $1}')" "and byte-identical: nothing was deleted or rewritten"

# --- an absent store is not an error -----------------------------------------
rm -rf "$A"
out=$( cd "$P" && ENSEMBLE_ANALYTICS_DIR="$A" bash "$CH" 2>&1 )
assert_not_contains "$out" "analytics:" "an absent analytics directory produces no advisory"
assert_not_contains "$out" "No such file" "and no error"

# And not anywhere in the skill either, in any casing: the phrase is the defect,
# not one line's wording.
n=$(grep -ril 'safe to delete' "$REPO_ROOT/skills/en-setup/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$n" "the phrase appears nowhere in en-setup"

report
