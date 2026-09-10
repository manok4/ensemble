#!/usr/bin/env bash
# tests/lint/skill-description-budget.test.sh
#
# TD2: Codex builds its initial skills list from every installed skill's name and
# description, and that list is capped at "2% of the model's context window, or
# 8,000 characters when the context window is unknown". Over the cap, Codex
# SHORTENS descriptions, and a shortened description may fail to match the
# request that should have triggered its skill.
#
# The failure is discoverability, and it is silent on the host that has it:
# Codex says "descriptions were shortened", not "en-plan will not trigger".
#
# Measured 2026-08-29: 9,705 characters across 17 skills, 1.2x over.
# Measured 2026-09-10: 4,513 across 16, 0.56x. TD2 stopped applying, and this
# guard is why it stays that way — the number drifted down without anyone
# watching it, so it can drift back up the same way.
#
# The budget is a HOST's, not this repo's, so the check is a ceiling with room
# rather than a target: a warn line at 80% gives a rewrite somewhere to land
# before a description is silently truncated on someone's machine.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill description budget"

BUDGET=8000

read -r TOTAL COUNT LARGEST LARGEST_NAME <<EOF
$(python3 - "$REPO_ROOT" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
total = 0
biggest = (0, "none")
files = sorted(glob.glob(os.path.join(root, "skills", "*", "SKILL.md")))
for f in files:
    s = open(f, encoding="utf-8").read()
    head = s.split("---", 2)[1] if s.startswith("---") else s
    name = re.search(r"^name:\s*(.*)$", head, re.M)
    desc = re.search(r"^description:\s*(.*)$", head, re.M)
    n = name.group(1).strip() if name else ""
    d = desc.group(1).strip().strip('"') if desc else ""
    cost = len(n) + len(d)
    total += cost
    if cost > biggest[0]:
        biggest = (cost, n or os.path.basename(os.path.dirname(f)))
print(total, len(files), biggest[0], biggest[1])
PY
)
EOF

[ -n "${TOTAL:-}" ] && [ "$TOTAL" -gt 0 ] \
  && pass "measured $COUNT skill descriptions: $TOTAL chars" \
  || fail "could not measure the descriptions" "got '$TOTAL'"

# Every skill must have one, or it cannot be listed at all.
[ "$COUNT" -ge 10 ] \
  && pass "every skill contributes a name and description" \
  || fail "too few skills measured; the extractor is probably broken" "count=$COUNT"

if [ "$TOTAL" -le "$BUDGET" ]; then
  pass "the initial skills list fits Codex's $BUDGET-char budget ($TOTAL)"
else
  fail "the skills list is over Codex's budget, so descriptions get shortened" \
       "$TOTAL > $BUDGET — front-load trigger words and cut the longest first ($LARGEST_NAME at $LARGEST)"
fi

# Room to move. Crossing this is not a failure, it is the point at which the
# next description added is the one that pushes a host over.
WARN=$(( BUDGET * 80 / 100 ))
if [ "$TOTAL" -le "$WARN" ]; then
  pass "headroom is comfortable ($TOTAL of $BUDGET, warn at $WARN)"
else
  fail "headroom is gone: the next description added likely crosses the budget" \
       "$TOTAL of $BUDGET; largest is $LARGEST_NAME at $LARGEST chars"
fi

report
