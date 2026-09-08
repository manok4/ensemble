#!/usr/bin/env bash
# tests/parity/script-parity.test.sh
#
# EN16 U2. Skills are self-contained (EN12), so a helper two skills need is
# copied into both. Copies drift silently: one skill fixes a bug, the other
# keeps it, and nothing fails until a run hits the stale copy. Carriers are
# discovered, not listed, so a skill that starts carrying a helper is covered
# without anyone remembering to add it here. The same discovery catches the
# inverse defect: a skill whose SKILL.md names a helper it does not carry.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="script parity"

for script in ensemble-config-get ensemble-peer-flags ensemble-agent-model; do
  copies=$(ls "$REPO_ROOT"/skills/*/scripts/"$script" 2>/dev/null)
  n=$(printf '%s\n' "$copies" | grep -c . )
  if [ "$n" -eq 0 ]; then
    if [ "$script" = ensemble-agent-model ]; then
      pass "SKIPPED — $script not yet shipped (EN16 U3)"; continue
    fi
    fail "$script has at least one carrier" "none found"; continue
  fi
  distinct=$(for f in $copies; do hash_file "$f"; done | sort -u | wc -l | tr -d ' ')
  assert_eq "1" "$distinct" "$script: $n copies are byte-identical ($(printf '%s\n' "$copies" | xargs -n1 dirname | xargs -n1 dirname | xargs -n1 basename | tr '\n' ' '))"
  for f in $copies; do [ -x "$f" ] || fail "$script copy is executable" "$f"; done
  pass "$script: every copy is executable"

  # A skill that names the helper in its SKILL.md must carry it.
  uncarried=""
  for d in "$REPO_ROOT"/skills/*/; do
    s=$(basename "${d%/}")
    grep -qF "scripts/$script" "$d/SKILL.md" 2>/dev/null || continue
    [ -f "$d/scripts/$script" ] || uncarried="$uncarried $s"
  done
  assert_eq "" "$(echo $uncarried)" "$script: every skill that names it carries it"
done

# Anything that carries ensemble-peer-flags must also carry the config reader
# it is fed from; the translator reads no config itself.
missing_reader=""
for f in "$REPO_ROOT"/skills/*/scripts/ensemble-peer-flags; do
  d=$(dirname "$f"); [ -f "$d/ensemble-config-get" ] || missing_reader="$missing_reader $(basename "$(dirname "$d")")"
done
assert_eq "" "$(echo $missing_reader)" "every carrier of ensemble-peer-flags also carries ensemble-config-get"

report
