#!/usr/bin/env bash
# tests/en-test-audit/campaign-format.test.sh
#
# A campaign's extra tables are documented once, in references/ledger-format.md,
# and parsed by ensemble-test-ledger-verify. If the two disagree, a campaign
# written exactly as the reference says would be refused as malformed at the
# end of a long run. This builds a campaign ledger from the headers the
# reference documents and requires the verifier to accept it.
#
# Negative control at authoring: renaming "Control evidence" to "Control" in the
# reference's Product defects example turned this red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
. "$SELF_DIR/lib.sh"
TEST_NAME="en-test-audit campaign format"

FMT="$REPO_ROOT/skills/en-test-audit/references/ledger-format.md"
LV="$REPO_ROOT/skills/en-test-audit/scripts/ensemble-test-ledger-verify"

# The header and separator lines of the first table after a heading in the reference.
doc_header() { awk -v h="$1" '$0 == h {on=1; next} on && /^\|/ {print; n++; if (n == 2) exit}' "$FMT"; }
LANES_H=$(doc_header '## Lanes')
DEFECTS_H=$(doc_header '## Product defects')
LEDGER_H=$(doc_header '## Ledger')
[ -n "$LANES_H" ] && [ -n "$DEFECTS_H" ] && [ -n "$LEDGER_H" ] \
  && pass "the reference documents Ledger, Lanes and Product defects tables" \
  || fail "ledger-format.md must document all three campaign tables"

R=$(make_audit_repo)
(
  cd "$R" || exit 1
  mkdir -p tests && printf 'pass "one"\n' > tests/a.test.sh && git add . && git commit -qm c
)
BASE=$(cd "$R" && git rev-parse HEAD)
mkdir -p "$R/docs/test-audits"
{
  printf -- '---\ntype: test-audit\nmode: campaign\nscope: tests\ntest_glob: "*.test.sh"\nbaseline_sha: %s\ncreated: 2026-09-26\npreservation_review: cross-agent\n---\n\n' "$BASE"
  printf '## Ledger\n\n%s\n| tests/a.test.sh::one | R | one | keep | - |\n\n' "$LEDGER_H"
  printf '## Lanes\n\n%s\n| only | tests/a.test.sh |\n\n' "$LANES_H"
  printf '## Product defects\n\n%s\n| rounding | abc1234 | reverting abc1234 turns tests/a.test.sh::one red |\n' "$DEFECTS_H"
} > "$R/docs/test-audits/c.md"
out=$("$LV" "$R/docs/test-audits/c.md" --tree 2>&1); rc=$?
[ "$rc" -eq 0 ] \
  && pass "a campaign ledger built from the reference's documented headers passes the verifier" \
  || fail "the verifier must accept the tables the reference documents" "rc=$rc out=$out"

rm -rf "$R"
report
