#!/usr/bin/env bash
# tests/lint/plan-index-generator.test.sh
#
# docs/generated/plan-index.md is marked generated, and the lint fails when a plan
# is missing from it, but nothing used to generate it: `--fix` was a no-op, so each
# shipped plan needed a hand edit to the one kind of file nobody may hand-edit.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="plan index generator"

LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
cd "$WORK" || exit 1
mkdir -p docs/plans/active docs/plans/completed docs/generated

plan() { # <dir> <file> <id> <title> <status> [shipped]
  printf -- '---\ntype: plan\nplan_id: %s\ntitle: %s\nstatus: %s\nshipped: %s\n---\n\n# %s\n' \
    "$3" "$4" "$5" "${6:-}" "$4" > "docs/plans/$1/$2"
}
plan completed EN02-bug_second.md EN02 '"Second, quoted"' completed 2026-02-02
plan completed EN01-feature_first.md EN01 First completed 2026-01-01
plan active EN03-feature_third.md EN03 Third in_progress
printf -- '---\ntype: plan-index\ngenerated: true\ngenerator: en-learn\nupdated: 2020-01-01\n---\n\n# Stale\n' \
  > docs/generated/plan-index.md
IDX=docs/generated/plan-index.md
before=$(cat "$IDX")

bash "$LINT" --scope "$IDX" >/dev/null 2>&1
assert_eq "$before" "$(cat "$IDX")" "without --fix the index is not written"

bash "$LINT" --fix --scope "$IDX" >/dev/null 2>&1
TODAY=$(date +%Y-%m-%d)
expected="---
type: plan-index
generated: true
generator: ensemble-lint
updated: $TODAY
total_entries: 3
---

# Plans — index

> Auto-maintained. Do not hand-edit.

## Active

- [\`EN03-feature_third.md\`](../plans/active/EN03-feature_third.md) — **EN03** Third (in_progress)

## Completed

- [\`EN01-feature_first.md\`](../plans/completed/EN01-feature_first.md) — **EN01** First (shipped 2026-01-01)
- [\`EN02-bug_second.md\`](../plans/completed/EN02-bug_second.md) — **EN02** Second, quoted (shipped 2026-02-02)"
assert_eq "$expected" "$(cat "$IDX")" "--fix builds the index from the plans' frontmatter"

# An unchanged index keeps its date, so a --fix on every ship adds no noise.
awk '/^updated:/ { print "updated: 2020-01-01"; next } { print }' "$IDX" > "$IDX.tmp" && mv "$IDX.tmp" "$IDX"
aged=$(cat "$IDX")
bash "$LINT" --fix --scope "$IDX" >/dev/null 2>&1
assert_eq "$aged" "$(cat "$IDX")" "--fix leaves an index with the same entries alone"

mv docs/plans/active/EN03-feature_third.md docs/plans/completed/
plan completed EN03-feature_third.md EN03 Third completed 2026-03-03
bash "$LINT" --fix --scope "$IDX" >/dev/null 2>&1
grep -qF '../plans/completed/EN03-feature_third.md) — **EN03** Third (shipped 2026-03-03)' "$IDX" \
  && pass "a completed plan moves to Completed" || fail "a completed plan moves to Completed" "$(cat "$IDX")"
grep -qF '_(none)_' "$IDX" && pass "an empty section says so" || fail "an empty section says so"
plan completed EN04-feature_fourth.md EN04 Fourth completed 2026-04-04
bash "$LINT" --scope docs/ 2>&1 | grep -q 'plan-index.md.*EN04\|EN04.*plan-index.md' \
  && pass "the lint still reports a plan the index misses" || fail "the lint still reports a plan the index misses"
out=$(bash "$LINT" --fix --scope docs/ 2>&1)
case "$out" in
  *index-coverage.plan-missing*) fail "--fix clears the coverage finding in the same run" "$out" ;;
  *) pass "--fix clears the coverage finding in the same run" ;;
esac

# Both places that move a plan to completed/ must refresh the index with it.
CMD='bin/ensemble-lint --fix --quiet --scope docs/generated/plan-index.md'
for f in skills/en-ship/references/plan-completion.md skills/en-learn/SKILL.md; do
  grep -qF "$CMD" "$REPO_ROOT/$f" && pass "$f refreshes the index when it moves a plan" \
    || fail "$f refreshes the index when it moves a plan"
done

report
