#!/usr/bin/env bash
# tests/lint/en-plan-lint-scope.test.sh
#
# EN16 U10. Seven lint runs at about two minutes each cost a 17-unit plan run
# fourteen minutes, and each one linted a directory to check one file the loop
# had just edited. The finalize loop now lints the plan file alone between
# passes; promotion keeps the one directory run, which is also where a plan-ID
# collision with a sibling is caught. Both must stay: dropping the single-file
# run brings the cost back, dropping the directory run loses the collision check.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan lint scope"

S="$REPO_ROOT/skills/en-plan/SKILL.md"
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "missing: $2"; }

has "$S" 'bin/ensemble-lint --scope <plan-path>' "the finalize loop lints the plan file alone between passes"
has "$S" 'bin/ensemble-lint --scope docs/plans/active' "promotion still runs the directory scope once"
# Order: the single-file run belongs to the apply step (16), the directory run
# to promotion (17). A single-file run that only happened at promotion would
# be the old cost with a new spelling.
apply_line=$(grep -n 'bin/ensemble-lint --scope <plan-path>' "$S" | head -1 | cut -d: -f1)
promo_line=$(grep -n 'bin/ensemble-lint --scope docs/plans/active' "$S" | head -1 | cut -d: -f1)
[ -n "$apply_line" ] && [ -n "$promo_line" ] && [ "$apply_line" -lt "$promo_line" ] \
  && pass "the single-file run precedes the promotion run in the process" \
  || fail "the single-file run must sit in the apply step, before promotion" "apply=$apply_line promo=$promo_line"
has "$S" 'plan-ID collision with a sibling' "the reason the directory run survives is recorded"

report
