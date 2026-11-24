#!/usr/bin/env bash
# Pins en-plan's Strategy read in references/plan-intake.md: it runs the
# reader, names ST-IDs or "none touched", and skips the whole step when the
# repo has no Strategy section. The behaviour is prose an agent follows, so the
# wording is the contract; tests/evals/behavioral/plan-strategy-* exercise it
# in real sessions, on demand.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-plan strategy intake"

INTAKE="$REPO_ROOT/skills/en-plan/references/plan-intake.md"

# Prints the clauses a file is missing, one per line; nothing when complete.
missing() {
  local f="$1"
  grep -qF '"$SKILL_DIR/scripts/ensemble-strategy-section"' "$f" || echo "reader call"
  grep -qF 'When it prints nothing, the repo has no Strategy section: skip this step, and write no `Strategy:` line.' "$f" || echo "skip-when-empty clause"
  grep -qF '`Strategy: ST<N>, ST<M>`' "$f" || echo "ST-ID line form"
  grep -qF '`Strategy: none touched`' "$f" || echo "none-touched form"
  grep -qF 'says so under `## Decisions, assumptions & risks`, naming the ST-ID' "$f" || echo "resisted clause"
}

gap=$(missing "$INTAKE")
assert_eq "" "$gap" "plan-intake.md carries the reader call, both line forms, the skip clause and the resisted clause"

# Negative control: without the skip clause the pin goes red.
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
grep -vF 'When it prints nothing, the repo has no Strategy section' "$INTAKE" > "$tmp"
assert_contains "$(missing "$tmp")" "skip-when-empty clause" "deleting the skip clause turns the pin red"

for t in skills/en-plan/references/templates/plan-template.md skills/en-foundation/references/templates/plan-template.md; do
  grep -qF 'Omit the line when the foundation has no Strategy section.' "$REPO_ROOT/$t" \
    && pass "$t names the Strategy line and when it is omitted" \
    || fail "$t names the Strategy line and when it is omitted"
done

report
