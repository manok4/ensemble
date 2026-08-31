#!/usr/bin/env bash
# tests/lint/conditional-pointers.test.sh
#
# A backticked asset path inside a shared reference is a DEPENDENCY CLAIM. The
# self-contained guard resolves those paths, so every skill carrying the
# reference must also carry the target — whether or not that skill needs it.
#
# That turned four informational asides into 2,000 lines of payload. One line in
# peer-model-policy.md said an enum was held to "the same standard
# `references/build-handoff.md` applies" — a comparison, not a dependency — and
# that comparison dragged build-handoff, build-orchestration and
# ensemble-verify-peer-evidence into en-plan, a skill whose first line is a hard
# gate against building anything.
#
# The rule: an UNCONDITIONAL dependency gets a backticked path. A pointer that
# is conditional on which skill is reading — "/en-review reconciles findings
# this way", "the doc lints enforce this separately" — names the file WITHOUT a
# path, so a reader can still find it and the closure walker does not bill every
# carrier for it.
#
# This guards the edges that were cut. It is a regression guard, not a general
# rule: the general form cannot be mechanized, because only a human can tell a
# comparison from a dependency.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="conditional pointers stay unlinked"
cd "$REPO_ROOT"

# --- 1. the cut edges stay cut, in every carrier ---
relinked=""
check() {  # $1=file glob  $2=forbidden backticked path  $3=label
  for f in $1; do
    grep -qF "\`$2\`" "$f" && relinked="$relinked $3($(basename $(dirname $(dirname $f))))"
  done
}
check 'skills/*/references/peer-model-policy.md' 'references/build-handoff.md'        pmp-build
check 'skills/*/references/peer-model-policy.md' 'references/cli-wrappers.md'         pmp-cli
# NOT checked: peer-model-policy's risk-ladder rung 2 links diff-signal-detection
# to define `is_small_and_safe`. That is a real dependency of the ladder, not an
# aside, so it stays linked and the 70-line target rides along with the policy.
# Accuracy over volume: unlinking it would have been the same mistake in reverse.
check 'skills/*/references/peer-model-policy.md' 'references/persona-dispatch.md'     pmp-persona
check 'skills/*/references/finding-schema.md'    'references/persona-dispatch.md'     fs-persona
check 'skills/*/references/stable-ids.md'        'references/doc-lints.md'            sid-lints

[ -z "$relinked" ] \
  && pass "no shared reference re-links a conditional pointer" \
  || fail "no shared reference re-links a conditional pointer" \
          "relinked:$relinked — each forces every carrier to ship the target"

# --- 2. unlinking must not orphan a real consumer ---
# Every skill that genuinely uses one of these targets names it in its own
# SKILL.md body, so it declares the dependency on its own account rather than
# inheriting it. If that stopped being true, unlinking would have broken it.
orphaned=""
body_names() {  # $1=skill dir  $2=needle
  awk '/^requires:/{r=1} r&&/^  - /{next} {print}' "$1/SKILL.md" 2>/dev/null | grep -q -- "$2"
}
while IFS='|' read -r target owners; do
  [ -n "$target" ] || continue
  for o in $owners; do
    body_names "skills/$o" "$target" || orphaned="$orphaned $o->$target"
    [ -e "skills/$o/references/$target.md" ] || [ -e "skills/$o/agents/$target.md" ] \
      || [ -e "skills/$o/scripts/$target" ] || orphaned="$orphaned $o!$target"
  done
done <<'OWNERS'
persona-dispatch|en-review
doc-lints|en-sweep
build-handoff|en-build en-cross-review
diff-signal-detection|en-review
build-orchestration|en-build
ensemble-verify-peer-evidence|en-build en-ship
OWNERS

[ -z "$orphaned" ] \
  && pass "every real consumer names and carries its own dependency" \
  || fail "every real consumer names and carries its own dependency" "$orphaned"

# --- 3. the cut actually reduced carriage, and stays reduced ---
# Pinned counts. A rise means a re-link (or a hand-added declaration) put the
# file back into a skill that does not use it; a drop means a real consumer lost
# its dependency. Either direction is worth a look, so this is an equality
# check rather than a ceiling.
drift=""
while IFS='|' read -r rel expected; do
  [ -n "$rel" ] || continue
  n=$(ls -1 skills/*/"$rel" 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = "$expected" ] || drift="$drift $rel($n!=$expected)"
done <<'COUNTS'
references/build-handoff.md|4
references/build-orchestration.md|4
references/persona-dispatch.md|4
references/cli-wrappers.md|4
agents/dimension-reviewer.md|4
scripts/ensemble-verify-peer-evidence|5
references/doc-lints.md|6
scripts/en-sweep-ci|6
COUNTS

[ -z "$drift" ] \
  && pass "carrier counts hold at their post-cut values" \
  || fail "carrier counts hold at their post-cut values" "$drift"

report
