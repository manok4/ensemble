#!/usr/bin/env bash
# tests/parity/script-parity.test.sh
#
# Every skill carries its own copy of the scripts it runs (EN12/EN13). A copy
# that drifts is the D44 hazard in a new coat: one fix lands in the carrier
# someone was looking at and the others keep the bug. On 2026-09-04 this guard
# found /en-setup still installing the pre-D65 ensemble-sweep-activity-check
# and a comment drift in ensemble-plan-hash (D84).
#
# DISCOVERED, NOT LISTED, on both axes: every script basename carried by more
# than one skill is hashed (a rewrite on 2026-09-08 listed three names and
# silently dropped seven scripts from the guard; the branch review caught it),
# and carriers are found by the presence of the file. Exceptions are deliberate
# per-skill variants, listed with the reason; a listed name must still have
# more than one copy, or the row is stale.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="script parity across carriers"
cd "$REPO_ROOT"

# name  reason
EXCEPTIONS='
ensemble-build-peer-prompt  three per-artifact variants: plan (u_id field), code, foundation (dimension fallback)
'
is_exception() { printf '%s\n' "$EXCEPTIONS" | grep -qE "^$1 "; }

names=$(ls skills/*/scripts/* 2>/dev/null | xargs -n1 basename | sort | uniq -d)
[ -n "$names" ] && pass "there are scripts carried by more than one skill" || fail "there are scripts carried by more than one skill"

for n in $names; do
  copies=$(ls skills/*/scripts/"$n")
  distinct=$(for f in $copies; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
  if is_exception "$n"; then
    [ "$distinct" -gt 1 ] && pass "$n: deliberate variants ($distinct), listed with a reason" \
                          || fail "$n: listed as an exception but its copies are identical" "delete the row"
  elif [ "$distinct" -eq 1 ]; then
    pass "$n: byte-identical across $(echo "$copies" | wc -l | tr -d ' ') carriers"
  else
    fail "$n: copies differ across carriers" "$(echo "$copies" | tr '\n' ' ') — sync them, or list the name with a reason"
  fi
  for f in $copies; do [ -x "$f" ] || fail "$n: copy is executable" "$f"; done
done

# Every exception names a script that still exists in more than one skill.
printf '%s\n' "$EXCEPTIONS" | grep -E '^[a-z]' | while read -r n _; do
  c=$(ls skills/*/scripts/"$n" 2>/dev/null | wc -l | tr -d ' ')
  [ "$c" -gt 1 ] && pass "exception $n still has $c copies" || fail "exception $n is stale" "$c copies"
done

# --- structural rules (EN16 U2/U3), layered on top of discovery ---
# A skill that names a shared helper in its SKILL.md must carry it.
for script in ensemble-config-get ensemble-peer-flags ensemble-agent-model; do
  uncarried=""
  for d in skills/*/; do
    s=$(basename "${d%/}")
    grep -qF "scripts/$script" "$d/SKILL.md" 2>/dev/null || continue
    [ -f "$d/scripts/$script" ] || uncarried="$uncarried $s"
  done
  assert_eq "" "$(echo $uncarried)" "$script: every skill that names it carries it"
done
# The translator reads no config: whoever carries it must carry the reader it is fed from.
missing_reader=""
for f in skills/*/scripts/ensemble-peer-flags; do
  d=$(dirname "$f"); [ -f "$d/ensemble-config-get" ] || missing_reader="$missing_reader $(basename "$(dirname "$d")")"
done
assert_eq "" "$(echo $missing_reader)" "every carrier of ensemble-peer-flags also carries ensemble-config-get"
# A skill that dispatches agents resolves their model through the resolver,
# which reads through the config reader; both travel with the agents.
no_resolver=""
for d in skills/*/; do
  s=$(basename "${d%/}"); [ -d "$d/agents" ] || continue
  [ -f "$d/scripts/ensemble-agent-model" ] && [ -f "$d/scripts/ensemble-config-get" ] || no_resolver="$no_resolver $s"
done
assert_eq "" "$(echo $no_resolver)" "every skill that carries agents/ carries ensemble-agent-model and ensemble-config-get"
# A skill that carries executables carries the invocation reference its
# SKILL.md preamble points at (std-5: en-learn was the one carrier without it).
no_ref=""
for d in skills/*/; do
  s=$(basename "${d%/}"); ls "$d"scripts/* >/dev/null 2>&1 || continue
  [ -f "$d/references/script-invocation.md" ] || no_ref="$no_ref $s"
done
assert_eq "" "$(echo $no_ref)" "every skill that carries scripts/ carries references/script-invocation.md"

report
