#!/usr/bin/env bash
# tests/en-setup/strategy-advisory.test.sh
#
# /en-setup's health walk reports whether docs/foundation.md has a marked
# Strategy section, through the sibling ensemble-strategy-section, so it agrees
# with every other consumer on what counts. It points at /en-foundation
# --strategy and offers no repair: only the author writes the section.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-setup strategy advisory"

CH="$REPO_ROOT/skills/en-setup/scripts/check-health"
FX="$REPO_ROOT/tests/strategy/fixtures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP
P="$WORK/proj"; mkdir -p "$P/docs" "$P/sub"
( cd "$P" && git init -q . && git config user.email t@e && git config user.name t )
# Run from a subdirectory: the runner must find the foundation from the repo root.
health() { ( cd "$P/sub" && ENSEMBLE_ANALYTICS_DIR="$WORK/a" bash "$CH" 2>&1 ); }
row() { printf '%s\n' "$1" | grep -A1 'Strategy section'; }

cp "$FX/numbered.md" "$P/docs/foundation.md"
assert_contains "$(row "$(health)")" "🟢 Strategy section" "a marked Strategy section is green"

cp "$FX/no-marker.md" "$P/docs/foundation.md"
r=$(row "$(health)")
assert_contains "$r" "🟡 Strategy section" "a section without the marker is yellow"
assert_contains "$r" "run /en-foundation --strategy" "and names the command that writes it"

cp "$FX/marker-outside.md" "$P/docs/foundation.md"
assert_contains "$(row "$(health)")" "🟡 Strategy section" "a marker outside the section is yellow, as the reader says"
cp "$FX/fenced.md" "$P/docs/foundation.md"
assert_contains "$(row "$(health)")" "🟡 Strategy section" "a heading only inside a fenced block is yellow"

cp "$FX/duplicate.md" "$P/docs/foundation.md"
r=$(row "$(health)")
assert_contains "$r" "🟡 Strategy section" "two Strategy headings are yellow"
assert_contains "$r" "Two Strategy headings in docs/foundation.md" "and say why"

rm "$P/docs/foundation.md"
assert_not_contains "$(health)" "Strategy section" "with no foundation there is no Strategy row"

report
