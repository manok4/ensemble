#!/usr/bin/env bash
# tests/lint/td-enforce-layer.test.sh
#
# EN22 U2. A TD entry routed to L1 or L2 must name a concrete check, or the
# correction router is prose with extra steps. This runs the real linter over
# tracker fixtures and asserts on what it reports.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="td.enforce-layer lint"

LINT="$REPO_ROOT/skills/en-setup/references/templates/ensemble-lint"
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

# A tracker whose Open section holds the given entry bodies, and whose Resolved
# section holds one L2 entry with no check (which must never fire).
tracker() {
  rm -rf "$TMP/docs"; mkdir -p "$TMP/docs/plans"
  {
    printf -- '---\ntype: tech-debt-tracker\ngenerated: false\ncreated: 2026-09-26\nupdated: 2026-09-26\n---\n\n# Tech debt tracker\n\n## Open\n\n'
    printf '%s\n' "$1"
    printf '\n## Resolved\n\n### TD1. Old\n\n- **Enforce at:** L2 static\n- **Logged:** 2026-09-01\n'
  } > "$TMP/docs/plans/tech-debt-tracker.md"
}

lint() { (cd "$TMP" && "$LINT" --scope docs/plans/tech-debt-tracker.md --json 2>&1); }
fires() { printf '%s' "$1" | grep -F '"rule":"td.enforce-layer"' | grep -F "\"severity\":\"$2\"" | grep -qF "$3"; }

tracker '### TD24. Concrete L2

- **Enforce at:** L2 static
- **Proposed check:** backend/tests/test_architecture_invariants.py: forbid source_system == comparisons
- **Logged:** 2026-09-26'
out=$(lint)
printf '%s' "$out" | grep -qF 'td.enforce-layer' \
  && fail "an L2 entry with a concrete check is accepted" "$out" \
  || pass "an L2 entry with a concrete check is accepted"

tracker '### TD24. No check

- **Enforce at:** L1 structure
- **Logged:** 2026-09-26'
out=$(lint)
fires "$out" P1 TD24 && pass "L1 with no Proposed check is P1, naming the entry" \
  || fail "L1 with no Proposed check is P1, naming the entry" "$out"

tracker '### TD25. No path

- **Enforce at:** L2 static
- **Proposed check:** add a lint
- **Logged:** 2026-09-26'
out=$(lint)
fires "$out" P1 TD25 && pass "a check with no path is P1" \
  || fail "a check with no path is P1" "$out"

tracker '### TD26. Nothing after the colon

- **Enforce at:** L2 static
- **Proposed check:** tests/guard.sh:
- **Logged:** 2026-09-26'
out=$(lint)
fires "$out" P1 TD26 && pass "a check with nothing after the colon is P1" \
  || fail "a check with nothing after the colon is P1" "$out"

tracker '### TD27. Unknown layer

- **Enforce at:** L9
- **Logged:** 2026-09-26'
out=$(lint)
fires "$out" P2 TD27 && pass "an unknown layer is P2" \
  || fail "an unknown layer is P2" "$out"

tracker '### TD28. Unrouted entry

- **Severity:** P3
- **Logged:** 2026-09-26'
out=$(lint)
printf '%s' "$out" | grep -qF 'td.enforce-layer' \
  && fail "an entry without the routing fields is untouched" "$out" \
  || pass "an entry without the routing fields is untouched"

tracker '### TD29. L3 needs no check

- **Enforce at:** L3 rules
- **Logged:** 2026-09-26'
out=$(lint)
printf '%s' "$out" | grep -qF 'td.enforce-layer' \
  && fail "an L3 entry needs no Proposed check" "$out" \
  || pass "an L3 entry needs no Proposed check"

# The repo's own tracker predates the fields and must stay clean.
real=$(cd "$REPO_ROOT" && "$LINT" --scope docs/plans/tech-debt-tracker.md --json 2>&1)
printf '%s' "$real" | grep -qF 'td.enforce-layer' \
  && fail "the real tracker has no td.enforce-layer finding" "$real" \
  || pass "the real tracker has no td.enforce-layer finding"

report
