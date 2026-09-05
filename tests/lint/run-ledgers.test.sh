#!/usr/bin/env bash
# tests/lint/run-ledgers.test.sh
#
# D98: a skill whose run can outlast its context keeps its in-flight ledger on
# disk and derives its report from the file. Each clause is anchored on the
# path the skill names, in the one file that must carry it. Negative control at
# authoring: removing en-qa's flows.json line turned its clause red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="run ledgers on disk (D98)"
cd "$REPO_ROOT"

has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $1"; }

has skills/en-qa/SKILL.md          '.test-output/qa/<run-id>/flows.json'                 "en-qa writes the flow ledger"
has skills/en-qa/SKILL.md          'from the flow ledger'                                 "en-qa's report is derived from it"
has skills/en-build/SKILL.md       '/tmp/ensemble/en-build/<run-id>/ledger.json'          "en-build writes the unit ledger"
has skills/en-flow/SKILL.md        '/tmp/ensemble/en-flow/<run-id>/state.json'            "en-flow records stage outcomes"
has skills/en-resolve-pr/SKILL.md  '/tmp/ensemble/en-resolve-pr/<run-id>/items.json'      "en-resolve-pr writes the item list"
has skills/en-foundation/SKILL.md  '/tmp/ensemble/en-foundation/<run-id>/ledger.md'       "en-foundation writes the known-facts ledger"

# The scope rule that travels with the ledgers: a found bug is a follow-up,
# not a fix, unless the requested behaviour cannot work without it.
has skills/en-build/SKILL.md       'cannot work without it'                               "en-build: incidental findings are follow-ups"
has skills/en-qa/SKILL.md          'cannot pass without it'                               "en-qa: out-of-scope bugs are follow-ups"
has skills/en-resolve-pr/SKILL.md  'Fix what the comment names'                           "en-resolve-pr: fixes stay on the comment"

report
