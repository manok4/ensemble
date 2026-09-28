#!/usr/bin/env bash
# Drift guards for /en-debug as a diagnosis-only skill (FR01 U9, D62, D89, D124).
#
# D124 moved the fix path to /en-fix. What stays here is the diagnosis: both
# modes, the causal-chain gate, the convergent/divergent verdict, the findings
# written before the question, and the contract a skill caller relies on.
#
# Negative controls at authoring: re-adding a "Fix it now" option, re-adding a
# test-first edit step, and moving the blocking choice above the findings rule
# each turned an assertion red.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-debug diagnosis"

DS="$REPO_ROOT/skills/en-debug/SKILL.md"
CT="$REPO_ROOT/skills/en-debug/CONTRACT.md"
REF="$REPO_ROOT/skills/en-debug/references/debug-investigation.md"
dhas() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$1")"; }
dlacks() { grep -qF -- "$2" "$1" && fail "$3" "still in $(basename "$1")" || pass "$3"; }

# --- two modes, one outcome ---------------------------------------------------
if grep -qiE "Telemetry mode" "$DS" && grep -qiE "Code mode" "$DS"; then
  pass "en-debug documents telemetry mode + code mode"
else
  fail "en-debug must document both telemetry and code modes"
fi
dhas "$DS" "**Never writes code.**"         "neither mode writes code"
grep -qiE "[Cc]ausal.chain gate" "$DS" && pass "the causal-chain gate is stated" || fail "the causal-chain gate is stated"
dhas "$DS" "one change at a time"           "states the one-change-at-a-time principle"
if [ -f "$REF" ] && grep -qF "debug-investigation.md" "$DS"; then
  pass "debug-investigation reference exists and is referenced"
else
  fail "debug-investigation reference must exist and be wired into en-debug"
fi
if grep -qiE "[Aa]nti-pattern" "$REF" && grep -qiE "[Ss]mart escalation" "$REF"; then
  pass "reference documents anti-patterns + smart escalation"
else
  fail "reference must document anti-patterns + smart escalation"
fi

# --- the fix path is gone (D124) ---------------------------------------------
dlacks "$DS" "Fix it now"                   "no 'Fix it now' option remains"
dlacks "$DS" "Fix (only if chosen)"         "no fix step remains"
if grep -qiE "test-first|write a failing test" "$DS"; then
  fail "no step writes a test or edits source" "$(grep -niE 'test-first|write a failing test' "$DS" | head -2)"
else
  pass "no step writes a test or edits source"
fi
dlacks "$DS" "suggest \`/en-ship\`"         "the handoff no longer suggests /en-ship"
grep -qiE 'invok(e|ing) (the )?`?/en-fix' "$DS" \
  && fail "en-debug suggests /en-fix and never invokes it" "a manual-only skill cannot be invoked" \
  || pass "en-debug suggests /en-fix and never invokes it"

# --- /en-debug "checkout total is off by one cent", run by a person ----------
# The findings block is written in full before the choice, and the choice
# offers /en-fix for a convergent diagnosis.
dhas "$DS" "convergent or divergent"        "the diagnosis classifies the fix"
dhas "$DS" "may be asserting the behavior that is correct" \
                                            "a failing test may be the one that is right"
dhas "$DS" "treat it as divergent"          "ambiguity resolves toward divergent"
dhas "$DS" "before the question opens"      "the findings block precedes the question"
dhas "$DS" "Naming the options is not presenting the findings" \
                                            "listing options does not count as presenting"
findings=$(grep -n "Write that block in full" "$DS" | head -1 | cut -d: -f1)
gate=$(grep -n "offer a \*\*blocking choice\*\*" "$DS" | head -1 | cut -d: -f1)
if [ -n "$findings" ] && [ -n "$gate" ] && [ "$findings" -lt "$gate" ]; then
  pass "the presentation rule is stated before the gate it governs"
else
  fail "the presentation rule is stated before the gate it governs" "rule=$findings gate=$gate"
fi
choice=$(awk -v g="${gate:-0}" 'NR>g && /^   [0-9]\. /{print} NR>g && /^[0-9]+\. /{exit}' "$DS")
if [ "$(printf '%s\n' "$choice" | grep -c .)" -eq 3 ] \
   && printf '%s' "$choice" | grep -qF 'Suggest `/en-fix`' \
   && printf '%s' "$choice" | grep -qF 'Diagnosis only' \
   && printf '%s' "$choice" | grep -qF '/en-brainstorm'; then
  pass "the choice is exactly: suggest /en-fix, diagnosis only, rethink the design"
else
  fail "the choice must list exactly three options: /en-fix, diagnosis only, /en-brainstorm" "$choice"
fi
dhas "$DS" "On a \`convergent\` verdict, suggest \`/en-fix\`" \
                                            "the handoff names /en-fix for a convergent verdict"

# --- invoked by /en-fix: no question, a verdict return ------------------------
dhas "$DS" "\`CONTRACT.md\`"                 "SKILL.md points a skill caller at CONTRACT.md"
dhas "$CT" "never calls a"                  "the contract promises no blocking question"
for v in convergent divergent design-problem unresolved; do
  grep -qF "\`$v\`" "$CT" && grep -qF "\`$v\`" "$DS" \
    && pass "verdict '$v' is in both contract and skill" \
    || fail "verdict '$v' is in both contract and skill"
done
dhas "$CT" "never edits a file"             "the contract promises read-only"

# --- investigation techniques ------------------------------------------------
dhas "$DS" "instrument the boundaries before theorising" \
                                            "boundaries are instrumented before hypotheses"
# A bare "which" was the first draft here — a word this file contains a dozen
# times over, which would have passed for any input.
dhas "$DS" "Run once to find out"           "the instrumentation runs once, to locate the seam"
dhas "$DS" "hour in the wrong one"          "the cost of theorising first is named"
dhas "$DS" "Find something that works, and diff it" \
                                            "a working analogue is compared"
dhas "$DS" "that can't matter"              "the filtering instinct is named as the hazard"

# --- the agent that was never dispatched stays gone --------------------------
[ -e "$REPO_ROOT/skills/en-debug/agents/learnings-research.md" ] \
  && fail "en-debug carries no learnings scout" \
  || pass "en-debug carries no learnings scout"

# ...but the scout it DOES dispatch, and the protocol that scout follows, stay.
# Removing research-dispatch.md was this pass's first attempt and it was wrong:
# repo-research follows its evidence-dossier protocol.
for keep in agents/repo-research.md references/research-dispatch.md; do
  [ -e "$REPO_ROOT/skills/en-debug/$keep" ] \
    && pass "en-debug still carries $keep" \
    || fail "en-debug still carries $keep" "repo-research depends on the dossier protocol"
done
grep -qE '^\| .en-debug. \| \(any\) \| fallback only' \
  "$REPO_ROOT/skills/en-debug/references/research-dispatch.md" \
  && pass "the dispatch matrix has en-debug's row" \
  || fail "the dispatch matrix has en-debug's row"

# --- D89, amended by D124: the description says what the skill does ---------
sed -n 3p "$DS" | grep -q "telemetry mode" \
  && pass "the description names telemetry mode" \
  || fail "the description must name telemetry mode"
sed -n 3p "$DS" | grep -qF 'Never writes code' && sed -n 3p "$DS" | grep -qF '/en-fix' \
  && pass "the description says it never writes code and names /en-fix" \
  || fail "the description must say it never writes code and name /en-fix"
CONV="$REPO_ROOT/skills/en-debug/references/observability-conventions.md"
grep -q "logging.unstructured" "$CONV" && fail "the conventions reference no longer promises a lint rule ensemble-lint lacks" || pass "the conventions reference no longer promises a lint rule ensemble-lint lacks"
TPL="$REPO_ROOT/skills/en-setup/references/templates/config-local-example.yaml"
grep -q "allowed_log_commands" "$TPL" && grep -q "max_log_lines" "$TPL" \
  && pass "the config template carries the keys the skill reads" || fail "the config template must carry allowed_log_commands and max_log_lines"
grep -qE '/en-build.*write a fix|/en-build \(write a fix' "$DS" && fail "the telemetry handoff no longer sends a hypothesis to /en-build" || pass "the telemetry handoff no longer sends a hypothesis to /en-build"

report
