#!/usr/bin/env bash
# Drift guards for en-qa browser-phase detector (FR01 U6).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-qa browser detector"

EN_QA="$REPO_ROOT/skills/en-qa/SKILL.md"

# --- detector step present ---
if grep -qiE "Browser-phase detector" "$EN_QA"; then
  pass "en-qa has a browser-phase detector step"
else
  fail "en-qa missing browser-phase detector step"
fi

# --- uses the shared signal reference ---
if grep -qF "diff-signal-detection.md" "$EN_QA"; then
  pass "detector uses diff-signal-detection reference"
else
  fail "detector must use diff-signal-detection reference"
fi

# --- needs_browser gating ---
if grep -qF "needs_browser" "$EN_QA"; then
  pass "detector gates on needs_browser"
else
  fail "detector must gate on needs_browser"
fi

# --- --browser flag documented ---
if grep -qF -- "--browser" "$EN_QA"; then
  pass "--browser flag documented"
else
  fail "--browser flag missing"
fi

# --- fail-closed (unclassifiable diff → run browser) ---
if grep -qiE "fail closed" "$EN_QA"; then
  pass "detector states fail-closed (run browser when unclassifiable)"
else
  fail "detector must state fail-closed behavior"
fi

# --- system-only still skips and wins over --browser ---
if grep -qiE "system-only.*win|wins over .*browser|--system-only.* always skip" "$EN_QA"; then
  pass "--system-only wins over --browser"
else
  fail "--system-only must win over --browser"
fi

# --- auto-skip reason listed in skip section ---
if grep -qiE "[Nn]o frontend files changed" "$EN_QA"; then
  pass "no-frontend auto-skip reason documented"
else
  fail "no-frontend auto-skip reason must be documented"
fi

# --- driver policy: en-qa was locked to one stack (2026-09-02) ---------------
# It named Playwright 16 times and skipped Phase 2 entirely when that MCP was
# absent — including on hosts with a perfectly good native browser. The order is
# the whole rule, so it is asserted structurally, not just by presence.
QS="$REPO_ROOT/skills/en-qa/SKILL.md"
QD="$REPO_ROOT/skills/en-qa/references/browser-driver.md"

qhas() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "not in $(basename "$1")"; }

[ -f "$QD" ] && pass "the driver reference is driver-neutral, not playwright-helpers" \
             || fail "the driver reference is driver-neutral, not playwright-helpers"
[ -e "$REPO_ROOT/skills/en-qa/references/playwright-helpers.md" ] \
  && fail "the Playwright-named reference is gone" \
  || pass "the Playwright-named reference is gone"

qhas "$QS" "host-native browser surface" "a host-native driver is preferred"
qhas "$QS" "Never introduce a third stack" "no third browser stack may be installed"
qhas "$QS" "One driver for the whole run"  "the driver does not change mid-run"
qhas "$QD" "do not survive a switch"       "the reason mixing drivers is forbidden is recorded"

# Host-native must be listed BEFORE Playwright, or the preference is decorative.
native=$(grep -n "host-native browser surface" "$QS" | head -1 | cut -d: -f1)
pw=$(grep -n "Playwright MCP" "$QS" | head -1 | cut -d: -f1)
if [ -n "$native" ] && [ -n "$pw" ] && [ "$native" -lt "$pw" ]; then
  pass "host-native is preferred before Playwright, in that order"
else
  fail "host-native is preferred before Playwright, in that order" "native=$native playwright=$pw"
fi

# --- QA is scoped to the change, not a regression sweep ----------------------
qhas "$QS" "browser QA of what was implemented" "Phase 2 is scoped to the change"
qhas "$QS" "Exercise only those flows"          "only attributed flows run"
qhas "$QS" "not a release regression sweep"     "the skill says what it is not"
qhas "$QS" "do not fall back to everything"     "incomplete attribution does not expand the run"
qhas "$QS" "impact undetermined"                "unattributed files are reported, not swept up"
qhas "$QS" "--all-flows"                        "the sweep has an explicit opt-in"

# --- every flow gets an outcome ----------------------------------------------
qhas "$QS" "Pass, Fail, or Skip with its reason" "every in-scope flow ends with an outcome"
qhas "$QS" "an absent flow reads as a flow that passed" \
                                                 "the reason a flow may not vanish is recorded"
qhas "$QS" "needs external interaction"          "un-drivable flows are skipped with a reason"

# --- the orchestrated seam ---------------------------------------------------
qhas "$QS" "none of those three may block"       "pre-flow questions do not block a driven run"
qhas "$QS" "it waits, which is worse"            "the reason names waiting, not failing"

# --- regression tests assert behaviour, not source text ----------------------
# D85 folded qa-flows.md into the skill; the rule now lives in the bug protocol.
qhas "$QS" "through a real interface"            "a regression test exercises a real interface"
qhas "$QS" "can be dead or commented out"        "the source-grep anti-pattern is named"
[ -e "$REPO_ROOT/skills/en-qa/references/qa-flows.md" ] && fail "qa-flows.md is gone (D85 folded it into the skill)" || pass "qa-flows.md is gone (D85 folded it into the skill)"
grep -qF "peer_mode_override" "$QS" && fail "en-qa no longer cites the peer key as a browser skip reason" || pass "en-qa no longer cites the peer key as a browser skip reason"

report
