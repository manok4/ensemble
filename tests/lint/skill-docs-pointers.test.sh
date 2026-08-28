#!/usr/bin/env bash
# tests/lint/skill-docs-pointers.test.sh
#
# `setup` installs `skills/*/` only. A relative `docs/...` path read from an
# installed skill therefore resolves against the USER'S project, not the Ensemble
# repo — so a skill citing docs/en-plan-default-branch-spec.md sends its reader to
# a file that does not exist wherever the skill actually runs.
#
# Some docs/ paths are fine: foundation.md, architecture.md, plans/, learnings/,
# decisions/, CONTEXT.md and friends are artifacts the skills CREATE in the user's
# project. The spec files at docs/ root are not — they are development history
# that stays in this repo.
#
# Found by auditing the docs folder: one skill reference called such a spec its
# "canonical" source, deferring authority to a file its readers cannot open.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill docs pointers"

# The rule is objective: flag a docs/ path that EXISTS in this repo but is not one
# of the artifacts a skill creates in the user's project. A path that does not
# exist here is either an external URL fragment (prisma's docs/orm/...) or already
# broken for a different reason — neither is this check's business.
SHIPPING='^docs/(foundation|architecture|CONTEXT|README)\.md$|^docs/(plans|learnings|decisions|designs|generated|references)(/|$)'

offenders=""
for f in $(find "$REPO_ROOT/skills" -type f 2>/dev/null); do
  # URLs are stripped first: the tail of
  # https://github.com/.../docs/integrations/x.md is not a relative path, and
  # matching it flagged files that had just been correctly fixed.
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    # Only real files in this repo can be "here but not there".
    [ -e "$REPO_ROOT/$hit" ] || continue
    printf '%s' "$hit" | grep -qE "$SHIPPING" && continue
    # An explicitly qualified mention is fine: it tells the reader not to expect
    # the file where the skill runs.
    ln=$(grep -n -F -- "$hit" "$f" | head -1 | cut -d: -f1)
    ctx=$(sed -n "${ln},$((ln + 2))p" "$f")
    printf '%s' "$ctx" | grep -qi 'does not ship\|not ship with the skill\|in the Ensemble repo' && continue
    offenders="$offenders $(printf '%s' "$f" | sed "s|$REPO_ROOT/||")->$hit"
  done <<EOF
$(sed 's|https\{0,1\}://[^ )\"'"'"']*||g' "$f" 2>/dev/null | grep -ohE 'docs/[A-Za-z0-9._/-]+' | sed 's/[.,)]*$//' | sort -u)
EOF
done

if [ -z "$offenders" ]; then
  pass "no skill points at a docs/ file that exists here but not where it installs"
else
  fail "no skill points at a docs/ file that exists here but not where it installs" "$offenders"
fi

# The one file that used to defer must now own its contract outright.
CP="$REPO_ROOT/skills/en-plan/references/plan-default-branch-checkpoint.md"
assert_file_exists "$CP" "the default-branch checkpoint reference exists"

if grep -qi 'canonical spec' "$CP"; then
  fail "the checkpoint reference does not defer to a non-shipping spec"
else
  pass "the checkpoint reference does not defer to a non-shipping spec"
fi

grep -qi 'This file is the contract' "$CP" \
  && pass "the checkpoint reference states that it is the contract" \
  || fail "the checkpoint reference states that it is the contract"

# It must actually carry what it claims: every operational element of the checkpoint.
for el in 'gh repo view' 'symbolic-ref' 'no-commit' 'details' 'branch-on-default'; do
  grep -q -- "$el" "$CP" \
    && pass "the checkpoint reference carries: $el" \
    || fail "the checkpoint reference carries: $el"
done

report
