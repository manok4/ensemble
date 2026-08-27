#!/usr/bin/env bash
# Guards the peer prompt's contract with the peer. Each assertion protects a
# property whose absence silently degrades review quality rather than erroring.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="peer prompt contract"

BUILD="$REPO_ROOT/shared/bin/ensemble-build-peer-prompt"
SCHEMA="$REPO_ROOT/shared/references/finding-schema.md"
TMP="${TMPDIR:-/tmp}/enpp.$$"; mkdir -p "$TMP"
printf -- '---\ntype: plan\n---\n# Test plan\n### U1. thing\n' > "$TMP/plan.md"
printf -- '- finding_id: 1-1 (P1) "x" — status: applied.\n' > "$TMP/ctx.md"

P1OUT=$(bash "$BUILD" --artifact-type plan --project-context P --goal G \
  --artifact-file "$TMP/plan.md" --peer-mode cross-agent 2>&1)
P2OUT=$(bash "$BUILD" --artifact-type plan --project-context P --goal G \
  --artifact-file "$TMP/plan.md" --peer-mode cross-agent \
  --iteration-context-file "$TMP/ctx.md" 2>&1)
CODEOUT=$(bash "$BUILD" --artifact-type code --project-context P --goal G \
  --artifact-file "$TMP/plan.md" --peer-mode cross-agent 2>&1)
rm -rf "$TMP"

# --- 1. the section the rules reference must actually be emitted ---
# anchor to line-start: the RULES block quotes the header name mid-line on every
# pass, so a substring match would pass even with the header never emitted.
if printf '%s' "$P2OUT" | grep -qE '^## Previous review context$' \
   && ! printf '%s' "$P1OUT" | grep -qE '^## Previous review context$'; then
  pass "iteration context is emitted under its referenced header, and only on re-review"
else
  fail "rules cite '## Previous review context' — the builder must emit that header on pass 2+"
fi

# --- 2. severity is DEFINED, not just named. The re-loop gate depends on P0/P1. ---
# match the DEFINITION, not its formatting: each level must carry meaning,
# and P0/P1 must be tied to the re-run gate the finalize loop keys off.
sev_ok=1
printf '%s' "$P1OUT" | grep -qiE "P0 +blocking" || sev_ok=0
printf '%s' "$P1OUT" | grep -qiE "P1 +must change before" || sev_ok=0
printf '%s' "$P1OUT" | grep -qiE "P2 +fix soon" || sev_ok=0
printf '%s' "$P1OUT" | grep -qiE "P3 +advisory" || sev_ok=0
printf '%s' "$P1OUT" | grep -qiE "P0/P1 trigger another review round" || sev_ok=0
if [ "$sev_ok" -eq 1 ]; then
  pass "severity levels are defined inline (the re-loop gate reads P0/P1)"
else
  fail "severity must be defined in-prompt; the peer cannot grade to an unstated scale"
fi

# --- 3. plan review covers plan QUALITY, not only safety metadata ---
q_ok=1
for d in "achieve the goal" "Unit decomposition" "Test scenarios" "Stated assumptions"; do
  printf '%s' "$P1OUT" | grep -qF "$d" || q_ok=0
done
for d in "risk: correctness" "Dependency-vs-phase" "gated: correctness"; do
  printf '%s' "$P1OUT" | grep -qF "$d" || q_ok=0
done
if [ "$q_ok" -eq 1 ]; then
  pass "plan dimensions cover goal, decomposition, tests and assumptions as well as risk/gated/phase"
else
  fail "plan review must cover plan quality, not only the safety metadata"
fi

# --- 4. scope boundary keeps findings off prose/formatting noise ---
if printf '%s' "$P1OUT" | grep -qF "Do NOT flag: prose style"; then
  pass "prompt tells the peer what not to spend findings on"
else
  fail "prompt must exclude prose/formatting noise from a plan review"
fi

# --- 5. return path: finding_id reuse and u_id are demanded, coverage is requested ---
r_ok=1
printf '%s' "$P1OUT" | grep -qF "reuse ITS id" || r_ok=0
printf '%s' "$P1OUT" | grep -qF "u_id" || r_ok=0
printf '%s' "$P1OUT" | grep -qF "coverage" || r_ok=0
printf '%s' "$P1OUT" | grep -qF "not_reviewed" || r_ok=0
if [ "$r_ok" -eq 1 ]; then
  pass "return path asks for stable finding_id reuse, u_id anchoring, and a coverage report"
else
  fail "return path must demand finding_id reuse, u_id, and coverage"
fi

# --- 6. u_id is plan-only; a code review must not be asked for unit ids ---
if ! printf '%s' "$CODEOUT" | grep -qF "u_id" \
   && printf '%s' "$CODEOUT" | grep -qF '"<file>:<line>"'; then
  pass "u_id is plan-only; code reviews anchor to file:line"
else
  fail "code artifact must anchor to file:line and not request u_id"
fi

# --- 7. the schema documents what the prompt now demands ---
if grep -qF '"coverage"' "$SCHEMA" && grep -qE '\| .findings\[\]\.finding_id. \| required \|' "$SCHEMA"; then
  pass "finding-schema documents coverage and required finding_id"
else
  fail "finding-schema must match the prompt contract (coverage; finding_id required)"
fi

report
