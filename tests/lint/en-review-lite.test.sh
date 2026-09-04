#!/usr/bin/env bash
# Drift guards for en-review --lite roster (FR01 U5).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review --lite"

EN_REVIEW="$REPO_ROOT/skills/en-review/SKILL.md"
# Reads /en-review's copy: it owns persona dispatch. D52 removed en-build's,
# which arrived through a peer-brief citation rather than anything en-build ran.
PERSONA="$REPO_ROOT/skills/en-review/references/persona-dispatch.md"

# --- flag documented ---
if grep -qF -- "--lite" "$EN_REVIEW"; then
  pass "--lite documented in en-review"
else
  fail "--lite missing from en-review"
fi

# --- references the shared signal detector ---
if grep -qF "diff-signal-detection.md" "$EN_REVIEW"; then
  pass "en-review --lite uses diff-signal-detection reference"
else
  fail "en-review --lite must use diff-signal-detection reference"
fi

# --- lite roster persona set ---
if grep -qiE "correctness.*standards|standards.*correctness" "$EN_REVIEW" && grep -qF "fast-pass" "$EN_REVIEW"; then
  pass "lite roster = correctness + standards + fast-pass"
else
  fail "lite roster must be correctness + standards + fast-pass"
fi

# --- fail-closed override stated in skill ---
if grep -qiE "fail closed|full roster regardless|gate wins" "$EN_REVIEW"; then
  pass "en-review --lite states fail-closed override"
else
  fail "en-review --lite must state fail-closed override"
fi

# --- D79: lite is a depth setting in every mode; size does not gate ---
LITE_BRIEF="$REPO_ROOT/skills/en-review/references/peer-brief-lite.md"
DIFFSIG="$REPO_ROOT/skills/en-review/references/diff-signal-detection.md"
if [ -f "$LITE_BRIEF" ] && grep -qF "references/peer-brief-lite.md" "$EN_REVIEW"; then
  pass "en-review hands the peer a lite brief under --lite"
else
  fail "en-review must carry and cite references/peer-brief-lite.md"
fi
# The builder extracts the block between these two headings; a lite brief
# without them produces "no review dimensions" and exit 2.
if grep -qxF "## What the peer is asked" "$LITE_BRIEF" && grep -qxF "## Where a finding points" "$LITE_BRIEF"; then
  pass "lite brief carries the section markers the prompt builder extracts"
else
  fail "lite brief must carry '## What the peer is asked' and '## Where a finding points'"
fi
# Lite means fewer dimensions. Negative control at authoring: appending a
# '### testing' heading to the lite brief turned this red.
lite_dims=$(sed -n '/^## What the peer is asked$/,/^## Where a finding points$/p' "$LITE_BRIEF")
if printf '%s' "$lite_dims" | grep -q '^### correctness' \
   && ! printf '%s' "$lite_dims" | grep -qE '^### (testing|maintainability|performance|migrations|security)'; then
  pass "lite brief asks for correctness and none of the full brief's other tables"
else
  fail "lite brief must keep correctness and drop testing/maintainability/performance/migrations/security"
fi
if grep -qF "is_low_risk" "$DIFFSIG" && grep -qF "is_low_risk" "$EN_REVIEW" \
   && ! grep -qE "exec-lines-out-of-range|uncounted-files|unknown-line-count|no-persona-roster" "$EN_REVIEW" "$DIFFSIG"; then
  pass "lite gate is is_low_risk; size and uncounted-file reasons are gone"
else
  fail "lite gate must be is_low_risk with only risk-signal and conditional-persona override reasons"
fi
if grep -qF "no-persona-roster" -r "$REPO_ROOT/skills"; then
  fail "no-persona-roster must not survive anywhere: --lite now applies under --peer"
else
  pass "no-persona-roster reason is gone from every skill"
fi

# --- persona-dispatch documents the lite roster ---
if grep -qiE "Lite roster" "$PERSONA"; then
  pass "persona-dispatch documents the lite roster"
else
  fail "persona-dispatch must document the lite roster"
fi

# --- fast-pass confidence cap documented ---
if grep -qiE "anchor 50|cap.*fast-pass|fast-pass.*cap" "$PERSONA"; then
  pass "persona-dispatch documents fast-pass confidence cap"
else
  fail "persona-dispatch must document fast-pass confidence cap"
fi

report
