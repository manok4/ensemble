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
# EN18 U8 moved the finalize loop's policy out of SKILL.md to buy headroom
# under the 24576-byte budget. The single-file run went with it; the promotion
# run did not. That split is now what the ordering rule is expressed as.
F="$REPO_ROOT/skills/en-plan/references/finalize-loop.md"
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "missing: $2"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$3" "present but should not be: $2" || pass "$3"; }

has "$F" 'bin/ensemble-lint --scope <plan-path>' "the finalize loop lints the plan file alone between passes"
has "$S" 'bin/ensemble-lint --scope docs/plans/active' "promotion still runs the directory scope once"
# Separation replaces the old line-number comparison, and is the stronger test:
# two runs in the same step would have passed an ordering check as long as the
# lines happened to fall the right way round. The single-file run must live in
# the finalize loop's own file, and the promotion run must not follow it there.
hasnt "$S" 'bin/ensemble-lint --scope <plan-path>' \
  "the single-file run sits in the finalize loop, not in the promotion step"
hasnt "$F" 'bin/ensemble-lint --scope docs/plans/active' \
  "the directory run stays at promotion and does not leak into the finalize loop"
has "$S" 'plan-ID collision with a sibling' "the reason the directory run survives is recorded"

report
