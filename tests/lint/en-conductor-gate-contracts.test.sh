#!/usr/bin/env bash
# tests/lint/en-conductor-gate-contracts.test.sh
#
# /en-conductor branches on other skills' output, and its gates quote their
# spellings back. Rename `status: open` in en-plan and the conductor gates on a
# value that never appears, so the run stalls or an agent reasons past the gate.
# The contracts exist so a caller can depend on a promise; this pins that the
# caller quotes them accurately. Carried over from en-flow-gate-contracts.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-conductor gate contracts"

SK="$REPO_ROOT/skills/en-conductor/SKILL.md"

# Contracts state these as table rows, so field and value share a line but are
# never adjacent. Require the pair on one line.
# <producer>|<field>|<value>|<the form the conductor writes>
while IFS='|' read -r producer field value quoted; do
  [ -n "$producer" ] || continue
  contract="$REPO_ROOT/skills/$producer/CONTRACT.md"
  if grep -F -- "$field" "$contract" | grep -qF -- "$value"; then
    pass "$producer's contract pairs '$field' with '$value'"
  else
    fail "$producer's contract no longer pairs '$field' with '$value'" "/en-conductor gates on it"
  fi
  grep -qF -- "$quoted" "$SK" && pass "/en-conductor quotes '$quoted'" || fail "/en-conductor must quote '$quoted'"
done <<'GATES'
en-plan|status|open|status: open
en-build|audit verdict|ok|verdict: ok
GATES

# Every outcome line is both published by the callee and handled by the caller.
for line in 'en-fix: shipped <pr-url> <exit-state>' 'en-fix: ready <branch>' 'en-fix: needs-plan clean <condition>' \
            'en-fix: needs-plan edited <condition>' 'en-fix: needs-decision <question>' \
            'en-fix: split <concern>; <concern>' 'en-fix: stopped <reason>'; do
  grep -qF -- "$line" "$REPO_ROOT/skills/en-fix/CONTRACT.md" \
    && pass "en-fix's contract lists: $line" || fail "en-fix's contract must list: $line"
  grep -qF -- "$line" "$SK" \
    && pass "/en-conductor handles: $line" || fail "/en-conductor must handle: $line"
done

for line in 'gate_required: U<N>' 'needs-decision: U<N>: <question>'; do
  grep -qF -- "$line" "$REPO_ROOT/skills/en-build/CONTRACT.md" \
    && pass "en-build's contract lists: $line" || fail "en-build's contract must list: $line"
  grep -qF -- "$line" "$SK" \
    && pass "/en-conductor handles: $line" || fail "/en-conductor must handle: $line"
done

# What the conductor says en-build's review is, against what en-build invokes.
# A restated callee internal has no reason to change when the original does.
EN_BUILD="$REPO_ROOT/skills/en-build/SKILL.md"
invoked=$(grep -oE '/en-review --(cross|peer|host)' "$EN_BUILD" | head -1)
if [ -z "$invoked" ]; then
  fail "en-build must invoke /en-review with an explicit mode at its post-build review"
elif grep -qF -- "$invoked" "$SK"; then
  pass "/en-conductor names the flag en-build invokes (${invoked#/en-review })"
else
  fail "/en-conductor describes a different review than en-build runs" "en-build invokes '$invoked'"
fi

report
