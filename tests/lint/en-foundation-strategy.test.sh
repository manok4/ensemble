#!/usr/bin/env bash
# Pins /en-foundation's Strategy flow. references/strategy-mode.md is prose an
# agent follows, and its gates are the contract: the 20-commit history gate,
# the one-at-a-time stress-test, explicit approval, delta mode keeping the
# baseline, append-only ST-IDs, and closing the strategy-missing debt. The
# behaviour itself is checked by the manual procedure in tests/evals/ledger.md.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-foundation strategy"

F="$REPO_ROOT/skills/en-foundation"
MODE="$F/references/strategy-mode.md"

HISTORY='This repo has <N> commits; a strategy drawn from that little history would be guesswork.'
SILENCE='Silence, or approving one card, is not approval.'

# Prints the clauses a strategy-mode file is missing; nothing when complete.
missing() {
  local f="$1"
  grep -qF 'bash "$SKILL_DIR/scripts/ensemble-strategy-section"' "$f" || echo "reader call"
  grep -qF "$HISTORY" "$f" || echo "history gate"
  grep -qF 'Under 20, stop with:' "$f" || echo "20-commit threshold"
  grep -qF 'Replace any whose answer you can predict' "$f" || echo "predictable hypotheticals"
  grep -qF 'Ask them one at a time with `QUESTION_TOOL`' "$f" || echo "one at a time"
  grep -qF '/tmp/ensemble/en-foundation/<run-id>/strategy-evidence.md' "$f" || echo "evidence sheet path"
  grep -qF "$SILENCE" "$f" || echo "silence is not approval"
  grep -qF 'That section is the baseline. The run
  keeps it and proposes only line-level changes' "$f" || echo "delta keeps baseline"
  grep -qF '`(retired YYYY-MM-DD)`, with its number never reused' "$f" || echo "retire rule"
  grep -qF 'rule key
`strategy-missing`' "$f" || echo "close strategy-missing debt"
}

assert_eq "" "$(missing "$MODE")" "strategy-mode.md carries every gate"

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
grep -vF "$HISTORY" "$MODE" > "$tmp"
assert_contains "$(missing "$tmp")" "history gate" "removing the history gate turns the pin red"
grep -vF "$SILENCE" "$MODE" > "$tmp"
assert_contains "$(missing "$tmp")" "silence is not approval" "removing the approval sentence turns the pin red"

flags=$(awk '/^## Flags/{f=1; next} f&&/^## /{exit} f' "$F/SKILL.md")
assert_contains "$flags" '`--strategy`' "SKILL.md's Flags table names --strategy"
step3=$(awk '/^3\. \*\*Detect mode/{f=1} f&&/^4\. \*\*/{exit} f' "$F/SKILL.md")
assert_contains "$step3" 'references/strategy-mode.md' "step 3 routes --strategy to strategy-mode.md"
assert_contains "$(cat "$F/CONTRACT.md")" '`--strategy`' "CONTRACT.md lists --strategy"

report
