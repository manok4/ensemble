#!/usr/bin/env bash
# Pins /en-sweep's Strategy category: both rule keys, the reader call, and the
# rule that sweep never edits the section. ensemble-doc-only-check enforces the
# last at runtime (tests/en-sweep/doc-only-enforcement/doc-only.test.sh); this
# keeps the instruction in front of the agent too.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-sweep strategy"

CHECKS="$REPO_ROOT/skills/en-sweep/references/sweep-checks.md"
SKILL="$REPO_ROOT/skills/en-sweep/SKILL.md"
NEVER='Sweep never edits the Strategy section, in its fix-up PRs or anywhere else'

missing() {  # $1 = sweep-checks.md copy
  local g; g=$(awk '/^### G\. Strategy/{f=1; next} f&&/^##/{exit} f' "$1")
  printf '%s' "$g" | grep -qF 'scripts/ensemble-strategy-section' || echo "reader call"
  printf '%s' "$g" | grep -qF -- '--rule-key strategy-missing' || echo "strategy-missing key"
  printf '%s' "$g" | grep -qF -- '--rule-key strategy-drift-st<N>' || echo "strategy-drift key"
  printf '%s' "$g" | grep -qF "$NEVER" || echo "never-edits clause"
}

assert_eq "" "$(missing "$CHECKS")" "sweep-checks.md §G carries the reader call, both rule keys and the never-edits clause"
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
grep -vF "$NEVER" "$CHECKS" > "$tmp"
assert_contains "$(missing "$tmp")" "never-edits clause" "deleting the never-edits clause turns the pin red"

step=$(awk '/^8c\. \*\*Strategy/{f=1} f&&/^9\. \*\*/{exit} f' "$SKILL")
assert_contains "$step" "references/sweep-checks.md" "the sweep step points at sweep-checks.md"
assert_contains "$step" "Sweep never edits the Strategy section" "the sweep step states the never-edits rule"

report
