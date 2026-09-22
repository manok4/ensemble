#!/usr/bin/env bash
# tests/lint/plan-store-config.test.sh
#
# EN18 U2. The Linear plan store is selected per repo by `plan_store`, and the
# cost of getting that wrong is asymmetric: an operator who writes
# `plan_store: Linear` and gets local mode commits a plan they believe was
# published, and nothing tells them. ensemble-config-get is fail-soft BY
# DESIGN: a value outside --allowed falls through to the next layer, which is
# right for a model alias and wrong for a mode switch.
#
# So two generic opt-outs, usable by any skill for any key, rather than
# EN18-specific logic in a shared reader:
#
#   --strict    a value that is PRESENT but outside --allowed is an error,
#               not a fall-through. Absent still falls through.
#   --required  resolving to nothing at all is an error.
#
# Both are opt-in. Every existing call site keeps the fail-soft contract the
# header promises, which is what stops a bad config taking down a review.
#
# Negative controls at authoring: dropping the --strict branch turned the
# invalid-value clauses red while leaving every fail-soft clause green;
# dropping --required turned only its own clause red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="plan store config resolution"

CG="$REPO_ROOT/skills/en-plan/scripts/ensemble-config-get"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/.ensemble" "$T/home/.ensemble"
printf '{}\n' > "$T/home/.ensemble/config.json"

cg() { bash "$CG" "$@" --repo-root "$T/repo" --home "$T/home" 2>"$T/err"; }
set_repo() { printf '%s\n' "$1" > "$T/repo/.ensemble/config.local.yaml"; }

# --- 1. carrier parity: every copy is byte-identical ------------------------
# The reader is duplicated per skill because the anchor test forbids resolving a
# helper outside its own skill directory. Two carriers gain the flags here, so
# the count must rise and the hashes must stay at one.
distinct=$(for f in "$REPO_ROOT"/skills/*/scripts/ensemble-config-get; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
assert_eq "1" "$distinct" "every ensemble-config-get carrier is byte-identical"
[ -x "$REPO_ROOT/skills/en-ship/scripts/ensemble-config-get" ] \
  && pass "en-ship carries the reader, for the provenance-drift check" \
  || fail "en-ship carries the reader"

# en-build DOES carry it, reversing what this clause asserted when U2 shipped.
# U2 argued en-build needed no config read, because a plan path meant local and
# a Linear identifier meant linear, so the argument's own shape carried the
# mode. EN18 U4's peer pass found the hole: shape-only selection lets
# `/en-build ENG-412` reach Linear in a repo configured `local`, which is the
# one thing the per-repo switch exists to prevent. The operator chose the
# carrier over the gap on 2026-09-22.
#
# D52 is not relaxed by this. D52 is about peer and worker dispatch, and
# en-build still dispatches neither; the reader was collateral in the list
# en-build-payload-shape.test.sh kept, and that list moved rather than the
# decision.
[ -x "$REPO_ROOT/skills/en-build/scripts/ensemble-config-get" ] \
  && pass "en-build carries the reader, to resolve plan_store before the argument is read" \
  || fail "en-build must carry ensemble-config-get" \
         "without it the mode falls back to argument shape, and the switch stops switching"

# --- 2. resolution, unchanged ----------------------------------------------
set_repo 'plan_store: linear'
assert_eq "linear" "$(cg plan_store --allowed local,linear --default local)" \
  "an explicit plan_store resolves"
set_repo 'other_key: value'
assert_eq "local" "$(cg plan_store --allowed local,linear --default local)" \
  "an absent plan_store falls to the default"

# --- 3. --strict: present but invalid is an error ---------------------------
# Without this, `plan_store: Linear` reads as local and the operator is never
# told. This is the whole reason the flag exists.
for bad in Linear tracker LOCAL; do
  set_repo "plan_store: $bad"
  out=$(cg plan_store --allowed local,linear --default local --strict); rc=$?
  err=$(cat "$T/err")
  if [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q "plan_store" \
     && printf '%s' "$err" | grep -q "local" && printf '%s' "$err" | grep -q "linear"; then
    pass "--strict rejects plan_store: $bad, naming the key and both accepted values"
  else
    fail "--strict rejects plan_store: $bad" "rc=$rc out=[$out] err=[$err]"
  fi
done

# An ABSENT key is not an invalid one: --strict must not turn a repo that never
# opted in into a failure.
set_repo 'other_key: value'
out=$(cg plan_store --allowed local,linear --default local --strict); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "local" ] \
  && pass "--strict leaves an absent key falling through to the default" \
  || fail "--strict leaves an absent key falling through" "rc=$rc out=[$out]"

# A VALID value is untouched.
set_repo 'plan_store: linear'
assert_eq "linear" "$(cg plan_store --allowed local,linear --default local --strict)" \
  "--strict passes a valid value through unchanged"

# --- 4. --required: resolving to nothing is an error -------------------------
# linear_team has no sensible default: a Linear mode with no team cannot work,
# and failing here beats failing after a parent issue exists.
set_repo 'plan_store: linear'
out=$(cg linear_team --required); rc=$?
err=$(cat "$T/err")
[ "$rc" -ne 0 ] && printf '%s' "$err" | grep -q "linear_team" \
  && pass "--required rejects an unset linear_team, naming the key" \
  || fail "--required rejects an unset linear_team" "rc=$rc out=[$out] err=[$err]"

set_repo 'linear_team: ENG'
assert_eq "ENG" "$(cg linear_team --required)" "--required passes a set value through"

# --- 5. fail-soft is preserved for every existing call site -----------------
# The header promises a config problem never exits non-zero. That promise holds
# for every call that does not opt in, including a malformed global file.
printf '{ this is not json\n' > "$T/home/.ensemble/config.json"
set_repo 'other_key: value'
out=$(cg peer_model_claude --default sonnet); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "sonnet" ] \
  && pass "malformed global JSON still falls through with exit 0 (fail-soft intact)" \
  || fail "malformed global JSON still falls through" "rc=$rc out=[$out]"
assert_contains "$(cat "$T/err")" "not valid JSON" "and still warns once on stderr naming the file"
printf '{}\n' > "$T/home/.ensemble/config.json"
set_repo 'plan_store: nonsense'
out=$(cg plan_store --allowed local,linear --default local); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "local" ] \
  && pass "without --strict an invalid value still falls through, as the header promises" \
  || fail "without --strict an invalid value still falls through" "rc=$rc out=[$out]"

# --- 6. both keys are documented where an operator will find them -----------
for f in "$REPO_ROOT/.ensemble/config.local.example.yaml" \
         "$REPO_ROOT/skills/en-setup/references/templates/config-local-example.yaml"; do
  n=$(basename "$(dirname "$f")")/$(basename "$f")
  grep -q "plan_store" "$f" && pass "$n documents plan_store" || fail "$n documents plan_store"
  grep -q "linear_team" "$f" && pass "$n documents linear_team" || fail "$n documents linear_team"
done

report
