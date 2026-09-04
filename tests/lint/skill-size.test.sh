#!/usr/bin/env bash
# tests/lint/skill-size.test.sh
#
# The foundation said a SKILL.md "targets 150-400 lines" and nothing checked it.
# Lines were never the measure anyway: on 2026-09-03 the average line ran from
# 73 to 127 characters across the sixteen skills, so en-simplify at 87 lines was
# 11KB and en-build at 439 lines was 56KB. What the model pays for is bytes.
#
# Budget: 24576 bytes (24KB, about 6K tokens) per SKILL.md.
#
# Five skills were over it when this was written. They are pinned below at
# their size that day, and a pinned skill may shrink but never grow. When a
# skill's review round brings it under budget, delete its row here: the test
# fails on a stale row, so the list can only get shorter. That is the point;
# a report-only version of this test would be decorative.
#
# Negative controls run at authoring: 2,000 bytes appended to en-brainstorm
# (under budget, and enough to cross it) went red; 100 bytes appended to
# en-build (pinned) went red; removing a pinned skill's row while it is still
# over budget went red. A first attempt appended 100 bytes to en-flow, which
# at 8KB cannot cross the budget, and passed: a control that cannot fail
# proves nothing, so it was replaced.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill size budget"

BUDGET=24576

# skill  bytes-on-2026-09-03  (over budget; may only shrink; delete when under)
BASELINE='
en-build 55599
en-plan 40199
en-review 30997
en-setup 31772
en-ship 32409
'

baseline_for() { printf '%s\n' "$BASELINE" | awk -v s="$1" '$1==s {print $2}'; }

over=""; grew=""; stale=""; checked=0
for f in "$REPO_ROOT"/skills/*/SKILL.md; do
  name=$(basename "$(dirname "$f")")
  size=$(wc -c < "$f" | tr -d ' ')
  checked=$((checked + 1))
  base=$(baseline_for "$name")
  if [ -n "$base" ]; then
    [ "$size" -le "$base" ] || grew="$grew $name:$size>$base"
    [ "$size" -gt "$BUDGET" ] || stale="$stale $name:$size"
  else
    [ "$size" -le "$BUDGET" ] || over="$over $name:$size"
  fi
done

[ "$checked" -ge 10 ] && pass "found skills to measure ($checked)" \
                      || fail "found skills to measure" "only $checked"
[ -z "$over" ] && pass "every unpinned SKILL.md is within $BUDGET bytes" \
               || fail "every unpinned SKILL.md is within $BUDGET bytes" "$over"
[ -z "$grew" ] && pass "no pinned SKILL.md grew past its baseline" \
               || fail "no pinned SKILL.md grew past its baseline" "$grew"
[ -z "$stale" ] && pass "every baseline row is still needed" \
                || fail "every baseline row is still needed" "under budget now, delete the row:$stale"

# A row naming a skill that does not exist is a typo that pins nothing.
unknown=""
for name in $(printf '%s\n' "$BASELINE" | awk 'NF {print $1}'); do
  [ -f "$REPO_ROOT/skills/$name/SKILL.md" ] || unknown="$unknown $name"
done
[ -z "$unknown" ] && pass "every baseline row names a skill" \
                  || fail "every baseline row names a skill" "$unknown"

report
