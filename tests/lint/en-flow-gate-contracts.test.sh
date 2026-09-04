#!/usr/bin/env bash
# tests/lint/en-flow-gate-contracts.test.sh
#
# /en-flow is the only skill that branches on four other skills' output. Its
# gates quote their frontmatter values back: a plan at `status: open`, a build
# audit at `verdict: ok`, a learning checkpoint at one of four canonical
# values. Nothing checked that those spellings still exist on the other side.
#
# Written 2026-09-03. The spellings were correct when this was written, so this
# pins a property that already held rather than repairing a drift. The failure
# it guards against is the quiet kind: rename `status: open` in en-plan and
# en-flow gates on a value that never appears, so the pipeline either stalls at
# step 3 forever or an agent decides the gate is unmeetable and reasons past
# it. Neither outcome says what went wrong.
#
# The contracts are the right source. They exist precisely so a caller can
# depend on a promise instead of reading the callee's flow, and
# tests/lint/contract-shape.test.sh already keeps them from naming internal
# paths. This is the other half: the caller must quote them accurately.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-flow gate contracts"

FLOW="$REPO_ROOT/skills/en-flow/SKILL.md"
# The pipeline reference was folded into SKILL.md (D90); the skill is the one file.

# A value en-flow gates on must appear in the contract of the skill that
# produces it. The contracts state these as table rows, `| `status` | `draft` ·
# `open` |`, so the field and the value are on one line but never adjacent: a
# first draft grepped for the literal "status: open" and reported both gates
# broken while both were fine. Require the pair on a single line instead.
#
# Reading both en-flow files, because the reference restates every gate and a
# fix applied to one is not a fix.
#
# <producer>|<field>|<value>|<the form en-flow writes>|<what the gate means>
while IFS='|' read -r producer field value quoted meaning; do
  [ -n "$producer" ] || continue
  contract="$REPO_ROOT/skills/$producer/CONTRACT.md"

  if [ ! -f "$contract" ]; then
    fail "$producer must publish a CONTRACT.md for /en-flow to gate on" "no $contract"
    continue
  fi

  if grep -F -- "$field" "$contract" | grep -qF -- "$value"; then
    pass "$producer's contract still pairs '$field' with '$value' ($meaning)"
  else
    fail "$producer's contract no longer pairs '$field' with '$value'" \
         "/en-flow gates on it for $meaning; update the gate or the contract"
  fi

  # And en-flow must actually be quoting it.
  in_skill=0
  grep -qF -- "$quoted" "$FLOW" && in_skill=1
  if [ "$in_skill" -eq 1 ]; then
    pass "/en-flow quotes '$quoted' in SKILL.md"
  else
    fail "/en-flow must quote '$quoted' in SKILL.md" "SKILL.md:$in_skill"
  fi
done <<'GATES'
en-plan|status|open|status: open|the plan gate at step 3
en-build|audit verdict|ok|verdict: ok|the build evidence audit at step 4
GATES

# The learning checkpoint is a four-value enum, and step 5 now branches on all
# four. Collapsing them is what let en-flow capture over a user who had already
# answered `skip`, so every value has to survive in en-build's contract and be
# named in en-flow.
for v in "captured" "intentionally_skipped" "up_to_date" "ci_environment"; do
  if grep -qF -- "$v" "$REPO_ROOT/skills/en-build/CONTRACT.md"; then
    pass "en-build's contract still lists learning_checkpoint value '$v'"
  else
    fail "en-build's contract dropped learning_checkpoint value '$v'" \
         "/en-flow step 5 branches on it"
  fi
  grep -qF -- "$v" "$FLOW" \
    && pass "/en-flow step 5 names '$v'" \
    || fail "/en-flow step 5 must name '$v'" "collapsing the enum overrides a user's decline"
done

# The decline itself, stated as a rule rather than inferred from the table.
if grep -qiE 'never overrides a decline|not this step.s to revisit|answered .skip' "$FLOW"; then
  pass "/en-flow says an answered decline is not revisited"
else
  fail "/en-flow must say a recorded decline ends step 5" \
       "the enum is only useful if the skill says what it does with it"
fi

# --- what en-flow says en-build's review is, vs what en-build invokes --------
# en-flow described a peer-only post-build review, cited to D35, until
# 2026-09-03. en-build had invoked --cross since D46, whose entire subject was
# that peer-only "discarded every host-only finding" — the standards, testing
# and maintainability categories. A reader of en-flow therefore believed the
# build gate produced none of those.
#
# This is the drift a pipeline skill is most exposed to: en-flow restates a
# callee's internals to explain why it does not re-run them, and that restated
# copy has no reason to change when the original does.
EN_BUILD="$REPO_ROOT/skills/en-build/SKILL.md"

# The flag en-build actually passes at its post-build review.
invoked=$(grep -oE '/en-review --(cross|peer|host)' "$EN_BUILD" | head -1)
if [ -z "$invoked" ]; then
  fail "en-build must invoke /en-review with an explicit mode at its post-build review" "none found"
else
  pass "en-build's post-build review invokes ${invoked#/en-review }"
  if grep -qF -- "$invoked" "$FLOW"; then
    pass "/en-flow names the same flag en-build invokes (${invoked#/en-review })"
  else
    fail "/en-flow describes a different review than en-build runs" \
         "en-build invokes '$invoked'; /en-flow does not name it"
  fi
fi

# The superseded citation specifically. D35's review model survives, but D46
# amended it on this point and D52 amended D46, so a bare "(D35)" against the
# review description is the stale form.
if grep -nE 'review[^.]{0,80}\(D35\)|\(D35\)[^.]{0,80}review' "$FLOW" >/dev/null 2>&1; then
  fail "/en-flow cites D35 as the authority for the post-build review" \
       "D46 amended D35 on exactly that point and D52 amended D46; cite D52"
else
  pass "/en-flow does not cite the superseded D35 for the review model"
fi

report
