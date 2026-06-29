#!/usr/bin/env bash
# Drift guards for en-review discrete confidence anchors + quote-the-line gate (EN02 U1).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review confidence anchors"

SCHEMA="$REPO_ROOT/references/finding-schema.md"
PERSONA="$REPO_ROOT/references/persona-dispatch.md"
EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"

# --- 5 discrete anchors documented ---
if grep -qiE "Confidence anchors" "$SCHEMA" && grep -qE "\{0, 25, 50, 75, 100\}" "$SCHEMA"; then
  pass "finding-schema documents the 5 discrete anchors"
else
  fail "finding-schema must document the 5 discrete anchors {0,25,50,75,100}"
fi

# --- quote-the-line gate ---
if grep -qiE "[Qq]uote-the-line gate" "$SCHEMA" && grep -qF "first_evidence" "$SCHEMA"; then
  pass "quote-the-line gate documented (first_evidence)"
else
  fail "quote-the-line gate must require first_evidence"
fi
if grep -qiE "75/100 .*missing .*first_evidence .*demoted to 50|demoted to 50|demote .*to 50" "$SCHEMA"; then
  pass "75/100 without first_evidence demotes to 50"
else
  fail "missing first_evidence at 75/100 must demote to 50"
fi

# --- corroboration promotes one anchor; fast-pass excluded ---
if grep -qiE "promote one anchor|50.*75.*100" "$SCHEMA" && grep -qiE "fast-pass .*never counts|not independent" "$SCHEMA"; then
  pass "corroboration promotes one anchor; fast-pass excluded"
else
  fail "corroboration must promote one anchor and exclude fast-pass"
fi

# --- confidence gate: suppress <75 except P0 at 50+ ---
if grep -qiE "below anchor 75" "$EN_REVIEW" && grep -qiE "P0 at anchor 50" "$EN_REVIEW"; then
  pass "confidence gate suppresses <75 except P0 at 50+"
else
  fail "confidence gate must suppress <75 except P0 at 50+"
fi

# --- sub-threshold still filed as TD (en-review edge) ---
if grep -qiE "filed as TD|files them" "$EN_REVIEW"; then
  pass "sub-threshold findings still filed as TD"
else
  fail "sub-threshold findings must still be filed as TD"
fi

# --- persona-dispatch uses anchor promotion, not +1 boost ---
if grep -qiE "promot.*one .*anchor|Corroboration promotion" "$PERSONA" && ! grep -qiE "boost confidence by \+1" "$PERSONA"; then
  pass "persona-dispatch uses anchor promotion (not +1 boost)"
else
  fail "persona-dispatch must use anchor promotion, not the old +1 boost"
fi

# --- no leftover 1-10 scale language in the schema validation ---
if grep -qE "must be one of .\{0, 25, 50, 75, 100\}" "$SCHEMA"; then
  pass "schema validates anchors (not integer 1-10)"
else
  fail "schema must validate the anchor set, not integer 1-10"
fi

report
