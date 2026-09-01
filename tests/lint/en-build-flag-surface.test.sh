#!/usr/bin/env bash
# tests/lint/en-build-flag-surface.test.sh
#
# en-build had 16 flags and read no config, while shipping ensemble-config-get
# in its payload. Ensemble already has ~35 config keys; en-build was the outlier
# that expressed every policy as a per-run flag.
#
# The line drawn: a flag is for what changes run to run — which units, where to
# resume, whether to skip a gate this once. Standing policy is config, because a
# project either works in worktrees or it does not.
#
# Two flags were deleted rather than moved. --no-finalize declined an offer you
# can decline by answering the prompt. --phasing forced phasing on when none of
# six triggers fired, which is to say when the plan was small.
#
# And --no-peer was renamed. It skipped the WHOLE review, personas included, so
# the name described the wrong half — and it collided with /en-review's own
# --no-peer, which means the opposite: run the personas, skip the cross-agent
# peer. Two skills that call each other, one flag name, two behaviours.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-build flag surface"

SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
CFG="$REPO_ROOT/skills/en-setup/references/templates/config-local-example.yaml"

# --- 1. the removed flags stay removed ---
back=""
for f in -- --no-peer --phasing --pause --strict-destructive --no-finalize --no-learning-checkpoint; do
  [ "$f" = "--" ] && continue
  grep -qE "^\| \`$f\`" "$SKILL" && back="$back $f"
done
[ -z "$back" ] \
  && pass "no removed flag is back in the table" \
  || fail "a removed flag is back in the table" "$back"

# --- 2. their policy has a config home, or the behaviour is simply gone ---
missing=""
for k in "worktree:" "strict_destructive:" "pause_between_phases:" "learning_checkpoint:"; do
  grep -qF "$k" "$CFG" || missing="$missing $k"
done
grep -qE '^# --- en-build standing policy ---' "$CFG" || missing="$missing section-header"
[ -z "$missing" ] \
  && pass "the four moved preferences have config keys" \
  || fail "a moved preference has no config home" "missing:$missing"

# --- 3. a config-set skip is as visible as a flag-set one ---
# This is the condition that made moving them safe. Without it, policy set once
# and forgotten silently degrades every future build.
if grep -qiE 'carries its reason when it is anything but .completed.' "$SKILL" \
   && grep -qiE 'as visible here as a flag typed' "$SKILL"; then
  pass "the audit surfaces why a gate was skipped, config or flag alike"
else
  fail "the audit must surface the reason a gate was skipped" \
       "a silent config-set skip is exactly what makes moving policy out of flags dangerous"
fi

# --- 4. the flag surface stays small ---
# Not a hard cap: a count that drifts up is the signal to re-ask which of them
# is standing policy.
n=$(sed -n '/^## Flags/,/^\*\*Standing/p' "$SKILL" | grep -c '^| `--')
[ "$n" -le 11 ] \
  && pass "the flag surface is $n, within the post-cut budget of 11" \
  || fail "the flag surface has grown back" "$n flags; ask which are standing policy"

report
