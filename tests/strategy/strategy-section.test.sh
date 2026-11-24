#!/usr/bin/env bash
# tests/strategy/strategy-section.test.sh
#
# ensemble-strategy-section is the one definition of a repo's Strategy section:
# the heading (outside fenced code), the boundary (the next # or ## heading),
# and the author-approved marker that makes it count. Every consumer reads the
# section through it, so a wrong boundary here is wrong everywhere.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="strategy section reader"

READER="$REPO_ROOT/skills/en-foundation/scripts/ensemble-strategy-section"
FX="$SELF_DIR/fixtures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

run() { out=$("$READER" "$@" 2>"$WORK/err"); rc=$?; err=$(cat "$WORK/err"); }

# Happy path: the section, from its heading to the line before the next ## heading.
run "$FX/numbered.md"
expected='## 1. Strategy

<!-- strategy: author-approved 2026-11-01 -->

Demo exists so that reports stay readable.

### ST1. Output stays plain text

Every command prints plain text.

### ST2. No network calls

The CLI never opens a socket.

A change aligns when it keeps output plain.
A change should be resisted when it adds a network dependency.
'
assert_eq "$expected" "$out
" "a marked section prints from its heading to the line before the next ## heading"
assert_exit_code 0 "$rc" "a found section exits 0"

run --ids "$FX/numbered.md"
assert_eq "ST1
ST2" "$out" "--ids prints the declared ST-IDs in file order"

run --ids "$FX/unnumbered.md"
assert_eq "ST1" "$out" "an unnumbered ## Strategy heading is found the same way"

run "$FX/no-marker.md"
assert_eq "" "$out" "a Strategy heading without the marker counts as absent"
assert_exit_code 0 "$rc" "an unmarked section exits 0"

run "$FX/marker-outside.md"
assert_eq "" "$out" "a marker outside the section does not make it count"

run "$WORK/missing.md"
assert_eq "" "$out" "a missing foundation prints nothing"
assert_exit_code 0 "$rc" "a missing foundation exits 0"

# Default path: docs/foundation.md under the current directory.
mkdir -p "$WORK/repo/docs" && cp "$FX/numbered.md" "$WORK/repo/docs/foundation.md"
out=$(cd "$WORK/repo" && "$READER" --ids); assert_eq "ST1
ST2" "$out" "with no path argument it reads docs/foundation.md"

run "$FX/fenced.md"
assert_eq "" "$out" "a Strategy heading inside a fenced block is ignored"

run --ids "$FX/last.md"
assert_eq "ST1" "$out" "a section that ends the file is found"
run "$FX/last.md"
assert_contains "$out" "Lines." "the last section runs to end of file"

run --ids "$FX/outside-decl.md"
assert_eq "ST1" "$out" "an ST heading declared outside the section is not listed"

run "$FX/duplicate.md"
assert_exit_code 3 "$rc" "two Strategy headings exit 3"
assert_eq "" "$out" "two Strategy headings print nothing on stdout"
assert_contains "$err" "more than one Strategy section in $FX/duplicate.md" "two Strategy headings name the file on stderr"

run --bogus "$FX/numbered.md"
assert_exit_code 2 "$rc" "an unknown flag exits 2"

report
