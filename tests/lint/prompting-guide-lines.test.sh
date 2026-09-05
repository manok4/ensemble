#!/usr/bin/env bash
# tests/lint/prompting-guide-lines.test.sh
#
# D99: the one-sentence rules placed where a behaviour the prompting guide names
# could cost a run. Each anchored on the sentence itself, in the file that must
# carry it; the shared research-dispatch copies are covered by the parity guard,
# so one carrier is checked here. Negative control at authoring: removing the
# search line from en-plan's copy turned its clause red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="prompting-guide lines (D99)"
cd "$REPO_ROOT"

has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $1"; }

# search triggering: recognition is not knowledge
has skills/en-plan/references/research-dispatch.md 'Recognising the name is not knowing its current state' "research-dispatch: recognised names are searched"
has skills/en-plan/SKILL.md       'a reason to fire, not to skip'                        "en-plan: the web-research trigger carries the search line"
has skills/en-brainstorm/SKILL.md 'a trigger, not a reason to skip'                      "en-brainstorm: the web-research item carries the search line"

# research does not block the first round
has skills/en-plan/SKILL.md 'Do not wait for research before round 1'                   "en-plan: round 1 is asked while research runs"
has skills/en-plan/references/research-dispatch.md 'carries on with whatever does not depend on them' "research-dispatch: the orchestrator does not await"

# targeted edits where a long existing file is edited
has skills/en-simplify/SKILL.md 'Never rewrite a file to apply a finding'                "en-simplify: findings are surgical edits"
has skills/en-plan/SKILL.md     'never a rewrite of it'                                  "en-plan: finalize-loop applications are surgical"
has skills/en-learn/SKILL.md    'Surgical edits only, never regenerate.'                 "en-learn: the foundation sync is surgical"
has skills/en-sweep/SKILL.md    '`Edit` on existing files, `Write` only for new ones'    "en-sweep: Edit on existing docs"

# long deliverables: settle in reasoning, write once
has skills/en-plan/SKILL.md       'write the file once'   "en-plan: the plan is written once"
has skills/en-foundation/SKILL.md 'write the document once' "en-foundation: the foundation is written once"
has skills/en-brainstorm/SKILL.md 'write the file once'   "en-brainstorm: a Deep design doc is written once"

# quoting: copied text is marked
has skills/en-learn/references/templates/learning-template.md 'Mark what you copied' "en-learn: copied source text is a marked quotation"

# base64 stays out of context
has skills/en-debug/SKILL.md 'Strip any base64 run longer than 200 characters' "en-debug: base64 runs are stripped from fetched logs"

report
