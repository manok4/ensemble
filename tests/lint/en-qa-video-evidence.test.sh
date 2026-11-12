#!/usr/bin/env bash
# tests/lint/en-qa-video-evidence.test.sh
#
# Wording pins for EN31 (D148). /en-qa's recording is prose a model follows:
# the script's behaviour is tested in ensemble-qa-evidence.test.sh, and this
# file holds the clauses that make the model call it. A live run is the only
# thing that observes the behaviour, and those are on demand, never in CI.
#
# Each path is overridable so a negative control can point the test at a
# scratch copy with a clause deleted and watch it go red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-qa video evidence"

QA_SKILL="${QA_SKILL:-$REPO_ROOT/skills/en-qa/SKILL.md}"
QA_DRIVER="${QA_DRIVER:-$REPO_ROOT/skills/en-qa/references/browser-driver.md}"
QA_CONTRACT="${QA_CONTRACT:-$REPO_ROOT/skills/en-qa/CONTRACT.md}"
CONDUCTOR="${CONDUCTOR:-$REPO_ROOT/skills/en-conductor/SKILL.md}"
FOUNDATION="${FOUNDATION:-$REPO_ROOT/docs/foundation.md}"

has() {  # $1=file  $2=fixed string  $3=label
  grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "'$2' not found in ${1#"$REPO_ROOT"/}"
}

# --- en-qa calls each subcommand at its step ----------------------------------
has "$QA_SKILL" 'ensemble-qa-evidence" video' "step 7 keeps each flow's recording"
has "$QA_SKILL" 'ensemble-qa-evidence" page' "step 9 renders the run page"
has "$QA_SKILL" 'ensemble-qa-evidence" link' "step 9 links the run page"
has "$QA_SKILL" "never changes the flow's outcome" "a recording failure never changes an outcome"
has "$QA_SKILL" "file names relative to the run dir" "ledger media paths are relative to the run dir, as the page resolves them"

# --- the driver reference names each recorder, and the run-dir screenshot path
has "$QA_DRIVER" 'preview_recording_start' "T3 Code records with its preview recorder"
has "$QA_DRIVER" 'page.screencast' "Playwright MCP records with page.screencast"
grep -qF '.test-output/qa-' "$QA_DRIVER" \
  && fail "screenshots go to the run dir, not a flat .test-output/qa-* path" \
  || pass "screenshots go to the run dir, not a flat .test-output/qa-* path"

# --- the contract returns the link, and the conductor relays it ---------------
grep -qE '^\| evidence \|' "$QA_CONTRACT" \
  && pass "the contract returns an evidence field" || fail "the contract returns an evidence field"
grep -E '^\| QA \|' "$CONDUCTOR" | grep -qF "log stage qa ok '<link line>'" \
  && pass "the conductor's QA stage relays the evidence line" \
  || fail "the conductor's QA stage relays the evidence line"

has "$FOUNDATION" '- **D148.' "the decision is recorded"

report
