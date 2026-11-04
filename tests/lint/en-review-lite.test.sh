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

# --- the tier, not a prose classification, decides lite ---
if grep -qF "scripts/ensemble-review-tier" "$EN_REVIEW"; then
  pass "en-review reads the tier script"
else
  fail "en-review must read the tier script"
fi

# --- lite roster persona set ---
if grep -qiE "correctness.*standards|standards.*correctness" "$EN_REVIEW"; then
  pass "lite roster = correctness + standards"
else
  fail "lite roster must be correctness + standards"
fi

# --- fail-closed override stated in skill ---
if grep -qiE "fail closed|full roster regardless|gate wins" "$EN_REVIEW"; then
  pass "en-review --lite states fail-closed override"
else
  fail "en-review --lite must state fail-closed override"
fi

# --- D79, D140: lite is a depth setting in every mode, on a quick diff ---
REPORT_REF="$REPO_ROOT/skills/en-review/references/review-report.md"
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
if ! grep -qE "exec-lines-out-of-range|uncounted-files|unknown-line-count|no-persona-roster" "$EN_REVIEW" "$DIFFSIG" \
   && grep -qF '`diff-unreadable`, `size`, `risk-signal`, `conditional-persona:<names>`' "$EN_REVIEW"; then
  pass "lite is overridden with four reasons, in a fixed order"
else
  fail "the lite gate must override with diff-unreadable, size, risk-signal and conditional-persona, in that order"
fi
# Absence across the whole skill tree: the script replaced these, and a survivor
# is a second definition of the same thing.
if grep -rqE "is_low_risk|is_small_and_safe" "$REPO_ROOT/skills"; then
  fail "no skill may still name is_low_risk or is_small_and_safe" "ensemble-review-tier replaced them"
else
  pass "no skill still names is_low_risk or is_small_and_safe"
fi
if grep -qF 'lite_gate: overridden (risk-signal' "$REPORT_REF" && grep -qF '`applied` is any run at lite depth, including a bare `quick` run' "$REPORT_REF"; then
  pass "the report defines a bare quick run as lite_gate: applied"
else
  fail "the report must define a bare quick run as lite_gate: applied"
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

# --- fast-pass is gone: it had no dispatch, so it could only run in-session ---
if grep -rqF "fast-pass" "$REPO_ROOT/skills/en-review"; then
  fail "fast-pass must be gone from skills/en-review" "D141: every reviewer runs outside the session"
else
  pass "fast-pass is gone from skills/en-review"
fi

report
