#!/usr/bin/env bash
# tests/parity/peer-contract-parity.test.sh
#
# EN13 U9. The one guard that must outlive scripts/sync-shared.
#
# references/peer-contract.md is what two ends of a peer exchange agree on: a
# peer emits P1 and a host parses P1. If one skill's copy drifts, findings stop
# being comparable and /en-review's reconciliation buckets become meaningless —
# and nothing else fails. That silence is why this test exists: every other
# consequence of drift here is invisible.
#
# Deliberately narrower than sync-shared --check, which enforced the whole
# generated tree. U10 deletes that tool. This asserts only the wire contract,
# and it depends on nothing being deleted.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="peer contract parity"

CONTRACT="references/peer-contract.md"

# Carriers are discovered, not listed: a skill that starts exchanging findings
# and copies the contract is covered without anyone remembering to add it here.
carriers=()
for d in "$REPO_ROOT"/skills/*/; do
  [ -f "$d$CONTRACT" ] && carriers+=("$(basename "${d%/}")")
done

[ "${#carriers[@]}" -ge 2 ] \
  && pass "the contract is carried by ${#carriers[@]} skills: ${carriers[*]}" \
  || fail "the contract is carried by at least two skills" "found ${#carriers[@]}"

# --- every copy byte-identical to the first ---
ref="$REPO_ROOT/skills/${carriers[0]}/$CONTRACT"
drifted=""
for s in "${carriers[@]}"; do
  cmp -s "$ref" "$REPO_ROOT/skills/$s/$CONTRACT" || drifted="$drifted $s"
done
assert_eq "" "$(echo $drifted)" "every copy of the contract is byte-identical"

# --- a skill that declares it must carry it, and vice versa ---
mismatch=""
for d in "$REPO_ROOT"/skills/*/; do
  s="$(basename "${d%/}")"
  declares=$(grep -cF "  - $CONTRACT" "$d/SKILL.md" 2>/dev/null || true)
  carries=$([ -f "$d$CONTRACT" ] && echo 1 || echo 0)
  [ "$declares" = "$carries" ] || mismatch="$mismatch $s(declares=$declares,carries=$carries)"
done
assert_eq "" "$(echo $mismatch)" "declaring the contract and carrying it agree, both ways"

# --- the values callers branch on are present in every copy ---
# Absence is the failure mode that matters: a copy missing a reason value still
# parses as markdown and still looks like a contract.
for v in P0 P1 P2 P3 safe_auto gated_auto manual advisory \
         cross-agent single-agent-fallback default-on recursion-guard \
         peer-failed:retry-exhausted dropped-effort-fragment \
         applied deferred disagreed superseded; do
  missing=""
  for s in "${carriers[@]}"; do
    grep -qF "$v" "$REPO_ROOT/skills/$s/$CONTRACT" || missing="$missing $s"
  done
  assert_eq "" "$(echo $missing)" "contract value present everywhere: $v"
done

# --- policy must NOT be in the contract ---
# The split is the point. These phrases are host behaviour and belong in each
# skill's own brief; their presence here would mean the fusion came back.
for phrase in "re-run unit tests" "Pause and ask" "tech-debt-tracker" "effort ladder"; do
  found=""
  for s in "${carriers[@]}"; do
    grep -qiF "$phrase" "$REPO_ROOT/skills/$s/$CONTRACT" && found="$found $s"
  done
  assert_eq "" "$(echo $found)" "policy has not leaked back into the contract: '$phrase'"
done

# --- a brief differing between skills is CORRECT and must not fail ---
briefs=()
for d in "$REPO_ROOT"/skills/*/; do
  [ -f "$d/references/peer-brief.md" ] && briefs+=("$d/references/peer-brief.md")
done
if [ "${#briefs[@]}" -ge 2 ]; then
  identical=0
  for ((i=1;i<${#briefs[@]};i++)); do cmp -s "${briefs[0]}" "${briefs[$i]}" && identical=$((identical+1)); done
  assert_eq "0" "$identical" "briefs are per-skill and differ; only the contract is pinned"
else
  fail "at least two skills carry a peer brief" "found ${#briefs[@]}"
fi

report
