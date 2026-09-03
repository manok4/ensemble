#!/usr/bin/env bash
# Drift guards for en-debug code-mode fix loop (FR01 U9).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-debug fix loop"

EN_DEBUG="$REPO_ROOT/skills/en-debug/SKILL.md"
REF="$REPO_ROOT/skills/en-debug/references/debug-investigation.md"

# --- two modes documented ---
if grep -qiE "Telemetry mode" "$EN_DEBUG" && grep -qiE "Code mode" "$EN_DEBUG"; then
  pass "en-debug documents telemetry mode + code mode"
else
  fail "en-debug must document both telemetry and code modes"
fi

# --- telemetry mode still read-only ---
if grep -qiE "Never writes code in telemetry mode|read-only" "$EN_DEBUG"; then
  pass "telemetry mode preserved as read-only"
else
  fail "telemetry mode must remain read-only"
fi

# --- causal-chain gate ---
if grep -qiE "[Cc]ausal.chain gate" "$EN_DEBUG"; then
  pass "code mode has causal-chain gate"
else
  fail "code mode must have a causal-chain gate"
fi

# --- test-first fix ---
if grep -qiE "test-first" "$EN_DEBUG"; then
  pass "code-mode fix is test-first"
else
  fail "code-mode fix must be test-first"
fi

# --- fix is opt-in (Fix it now / Diagnosis only) ---
if grep -qiE "Fix it now" "$EN_DEBUG" && grep -qiE "Diagnosis only" "$EN_DEBUG"; then
  pass "fix is opt-in (Fix it now / Diagnosis only choice)"
else
  fail "fix must be opt-in with a diagnosis-only choice"
fi

# --- one change at a time / anti-shotgun ---
if grep -qiE "one change at a time" "$EN_DEBUG"; then
  pass "states one-change-at-a-time principle"
else
  fail "must state one-change-at-a-time principle"
fi

# --- investigation reference exists and is wired ---
if [ -f "$REF" ] && grep -qF "debug-investigation.md" "$EN_DEBUG"; then
  pass "debug-investigation reference exists and is referenced"
else
  fail "debug-investigation reference must exist and be wired into en-debug"
fi

# --- reference has anti-patterns + escalation ---
if grep -qiE "[Aa]nti-pattern" "$REF" && grep -qiE "[Ss]mart escalation" "$REF"; then
  pass "reference documents anti-patterns + smart escalation"
else
  fail "reference must document anti-patterns + smart escalation"
fi

# --- convergent vs divergent (2026-09-02) ------------------------------------
# The skill had zero occurrences of this idea. A red test may be asserting the
# guarantee the change broke on purpose; "fixing" it deletes that guarantee.
DS="$REPO_ROOT/skills/en-debug/SKILL.md"
dhas() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$1")"; }

dhas "$DS" "convergent or divergent"       "the fix is classified before it is applied"
dhas "$DS" "is never applied here"         "a divergent fix is surfaced, not applied"
dhas "$DS" "may be asserting the behavior that is correct" \
                                           "a failing test may be the one that is right"
dhas "$DS" "treat it as divergent"         "ambiguity resolves toward not applying"

# --- findings before the gate: ordering is the whole point -------------------
dhas "$DS" "before the question opens"     "the findings block precedes the question"
dhas "$DS" "Naming the options is not presenting the findings" \
                                           "listing options does not count as presenting"
findings=$(grep -n "Write that block in full" "$DS" | head -1 | cut -d: -f1)
gate=$(grep -n "offer a \*\*blocking choice\*\*" "$DS" | head -1 | cut -d: -f1)
if [ -n "$findings" ] && [ -n "$gate" ] && [ "$findings" -lt "$gate" ]; then
  pass "the presentation rule is stated before the gate it governs"
else
  fail "the presentation rule is stated before the gate it governs" "rule=$findings gate=$gate"
fi

# --- pre-fix scope record ----------------------------------------------------
dhas "$DS" "Record the pre-fix scope first" "the pre-fix scope is recorded before editing"
dhas "$DS" "cannot be reconstructed"        "the reason it must be recorded first is given"

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
dhas "$DS" "not a fourth hypothesis"        "three failed fixes is an architecture signal"

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

report
