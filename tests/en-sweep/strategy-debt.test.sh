#!/usr/bin/env bash
# tests/en-sweep/strategy-debt.test.sh
#
# /en-sweep files strategy debt through ensemble-td-append with fixed rule keys,
# so a weekly run files a missing section once and drift once per ST-ID. These
# run the exact commands references/sweep-checks.md §G prescribes.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-sweep strategy debt"

APPEND="$REPO_ROOT/skills/en-sweep/scripts/ensemble-td-append"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
TR="$WORK/tech-debt-tracker.md"
cat > "$TR" <<'MD'
---
type: tech-debt-tracker
generated: false
created: 2026-11-24
updated: 2026-11-24
---

# Tech debt tracker

## Open

## Resolved
MD

missing() {
  "$APPEND" --tracker "$TR" --rule-key strategy-missing --source /en-sweep --severity P3 --confidence 10 \
    --enforce-at "L4 skill" --location docs/foundation.md --title "No Strategy section" \
    --why "No review can check a change against the project's principles" --fix "Run /en-foundation --strategy"
}
drift() {  # $1 = N
  "$APPEND" --tracker "$TR" --rule-key "strategy-drift-st$1" --source /en-sweep --severity P3 --confidence 7 \
    --enforce-at "L4 skill" --location docs/foundation.md --title "ST$1 no longer matches the repo" \
    --why "ST$1 says the CLI has 3 commands; bin/ has 4" --fix "Run /en-foundation --strategy"
}

out=$(missing 2>&1); rc=$?
assert_exit_code 0 "$rc" "the first strategy-missing entry is filed"
out=$(missing 2>&1); rc=$?
assert_exit_code 4 "$rc" "a second sweep's strategy-missing is refused by its rule key"
assert_eq "1" "$(grep -c 'No Strategy section' "$TR")" "the tracker holds one strategy-missing entry"

drift 1 >/dev/null 2>&1; drift 2 >/dev/null 2>&1; rc=$?
assert_exit_code 0 "$rc" "drift on a second ST-ID is its own entry"
assert_eq "2" "$(grep -cE '^### TD[0-9]+\. ST[12] no longer matches the repo' "$TR")" "drift is keyed per ST-ID"
drift 1 >/dev/null 2>&1; rc=$?
assert_exit_code 4 "$rc" "repeat drift on the same ST-ID is refused"

report
