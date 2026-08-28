#!/usr/bin/env bash
# Drift guards for the EN08 en-review transparency + mutation gate.
# Two field failures on a --lite interactive run: (1) the fail-closed lite gate
# silently overrode --lite (full roster, no reason surfaced); (2) the agent
# implemented findings wholesale, past the mode's mutation boundary. EN08 pins
# both as auditable contract: a mandatory lite_gate: outcome line (every run)
# and a recorded applied_fixes[] mutation boundary.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review mutation gate"

SKILL="$REPO_ROOT/skills/en-review/SKILL.md"
DIFFSIG="$REPO_ROOT/skills/en-build/references/diff-signal-detection.md"
DISPATCH="$REPO_ROOT/skills/en-build/references/persona-dispatch.md"

# === U1: lite-gate transparency ===

# --- exactly-one lite_gate: line on EVERY run, all three outcomes ---
if grep -qF "lite_gate: applied" "$SKILL" \
   && grep -qF "lite_gate: overridden" "$SKILL" \
   && grep -qF "lite_gate: not-requested" "$SKILL" \
   && grep -qiE "EVERY run emits exactly ONE .?lite_gate" "$SKILL"; then
  pass "lite_gate: line is mandatory on every run with applied/overridden/not-requested"
else
  fail "SKILL must require exactly one lite_gate: line per run (applied|overridden|not-requested)"
fi

# --- never a silent override ---
if grep -qiE "never a silent override" "$SKILL"; then
  pass "silent lite-gate override forbidden"
else
  fail "SKILL must state the override is never silent"
fi

# --- canonical reason enum present in BOTH files ---
enum_ok=1
for rid in "unknown-line-count" "exec-lines-out-of-range" "uncounted-files" "risk-signal" "conditional-persona:"; do
  grep -qF "$rid" "$SKILL" || enum_ok=0
  grep -qF "$rid" "$DIFFSIG" || enum_ok=0
done
if [ "$enum_ok" -eq 1 ]; then
  pass "canonical override-reason enum mirrored in SKILL and diff-signal-detection"
else
  fail "the override-reason enum must appear in both SKILL.md and diff-signal-detection.md"
fi

# --- deterministic multi-reason grammar (order, dedup, separator, persona encoding) ---
grammar_ok=1
grep -qiE "canonical order|fixed table order" "$SKILL" || grammar_ok=0
grep -qiE "dedup" "$SKILL" || grammar_ok=0
grep -qiE "comma\+space" "$SKILL" || grammar_ok=0
grep -qiE "alphabetically.sorted.*\+.*joined" "$SKILL" || grammar_ok=0
grep -qF "conditional-persona:performance+security" "$SKILL" || grammar_ok=0
if [ "$grammar_ok" -eq 1 ]; then
  pass "multi-reason grammar is deterministic (order, dedup, separator, +-joined sorted personas)"
else
  fail "SKILL must define the canonical multi-reason grammar"
fi

# --- structured envelope field; markdown line derived from it ---
if grep -qE '"lite_gate": \{"outcome"' "$SKILL" && grep -qiE "DERIVED from that object|derived from it" "$SKILL"; then
  pass "envelope carries structured lite_gate object; markdown line derives from it"
else
  fail "the JSON envelope must carry the structured lite_gate object and the line must derive from it"
fi

# --- markdown-summary example shows a lite_gate line ---
if sed -n '/## Markdown summary/,/## Reference files/p' "$SKILL" | grep -qF "lite_gate:"; then
  pass "markdown-summary example includes a lite_gate line"
else
  fail "the markdown-summary example must include a lite_gate line"
fi

# === U2: auditable mutation boundary ===

# --- mandatory review_fixes: line, all three forms ---
if grep -qE 'review_fixes: applied <N>|review_fixes: applied [0-9]' "$SKILL" \
   && grep -qF "review_fixes: none" "$SKILL" \
   && grep -qF "review_fixes: none (report-only)" "$SKILL"; then
  pass "review_fixes: line documented with applied/none/none(report-only) forms"
else
  fail "SKILL must document all three review_fixes: forms"
fi

# --- applied_fixes[] envelope field with the entry shape ---
if grep -qF '"applied_fixes"' "$SKILL" && grep -qE '\{finding_id, tier, files\[\]\}|"finding_id": "rev' "$SKILL"; then
  pass "envelope carries applied_fixes[] with {finding_id, tier, files[]} entries"
else
  fail "the JSON envelope must carry applied_fixes[] entries {finding_id, tier, files[]}"
fi

# --- two-phase protocol: baseline + frozen set BEFORE any edit; delta-derived; pre-existing excluded ---
twophase_ok=1
grep -qiE "before ANY edit" "$SKILL" || twophase_ok=0
grep -qiE "freeze the mode-permitted finding set|frozen set" "$SKILL" || twophase_ok=0
grep -qiE "before-vs-after" "$SKILL" || twophase_ok=0
grep -qiE "excluding pre-existing|pre-existing dirty" "$SKILL" || twophase_ok=0
if [ "$twophase_ok" -eq 1 ]; then
  pass "two-phase protocol: baseline + frozen set precede edits; applied_fixes derives from the delta"
else
  fail "SKILL must define the two-phase protocol (baseline, freeze, delta-derived, pre-existing excluded)"
fi

# --- consistency invariants: N == unique entries; line derived; none => empty array ---
invariants_ok=1
grep -qiE "MUST equal the count of unique" "$SKILL" || invariants_ok=0
grep -qiE "DERIVED from the array" "$SKILL" || invariants_ok=0
grep -qiE "ascending ID order" "$SKILL" || invariants_ok=0
grep -qiE 'MUST be `\[\]`|applied_fixes.*MUST be' "$SKILL" || invariants_ok=0
grep -qiE "sorted and deduplicated|sorted \+ dedup" "$SKILL" || invariants_ok=0
if [ "$invariants_ok" -eq 1 ]; then
  pass "consistency invariants: N==unique count, line derived, ascending order, none=>[] , files sorted+deduped"
else
  fail "SKILL must state the review_fixes/applied_fixes consistency invariants"
fi

# --- per-mode boundaries: headless safe_auto-ONLY; manual never without the pick ---
if grep -qiE "safe_auto.*ONLY, silently|safe_auto. ONLY" "$SKILL" \
   && grep -qiE "NEVER applied without the user.s explicit pick" "$SKILL"; then
  pass "per-mode boundaries: headless safe_auto-only; manual never without the user's pick"
else
  fail "SKILL must state headless=safe_auto-only and manual-requires-explicit-pick"
fi

# --- P0 halts ALL automatic mutation (even safe_auto / gated_auto) ---
if grep -qiE "P0 finding halts ALL automatic mutation" "$SKILL" && grep -qiE "including .safe_auto. and .gated_auto." "$SKILL"; then
  pass "P0 halts all automatic mutation until the severity.md pause-and-ask"
else
  fail "SKILL must pin the P0-halts-all-auto-mutation rule"
fi

# --- scoped implementation boundary (not a blanket 'never implements') ---
if grep -qiE "MUST NOT implement findings outside the mode-permitted, announced, and recorded" "$SKILL" \
   && grep -qiE "wholesale implementation .*contract violation" "$SKILL"; then
  pass "scoped boundary: no implementing outside the recorded applied_fixes set; wholesale = violation"
else
  fail "SKILL must carry the scoped implementation boundary (not a blanket prohibition)"
fi

# --- working-tree delta must not exceed the recorded set ---
if grep -qiE "MUST NOT exceed the recorded .applied_fixes" "$SKILL"; then
  pass "working-tree delta bounded by the recorded applied_fixes[]"
else
  fail "SKILL must bound the review-attributable tree delta by applied_fixes[]"
fi

# --- severity.md referenced for tiers (not duplicated); persona-dispatch mirrors the boundary ---
if grep -qiE "severity.md.*referenced, not duplicated|Tier definitions live in" "$SKILL" \
   && grep -qiE "must not implement findings outside the mode-permitted" "$DISPATCH"; then
  pass "severity.md referenced for tiers; persona-dispatch mirrors the mutation boundary"
else
  fail "severity.md must stay the tier source and persona-dispatch must mirror the boundary"
fi

# --- markdown-summary example shows a review_fixes line ---
if sed -n '/## Markdown summary/,/## Reference files/p' "$SKILL" | grep -qF "review_fixes:"; then
  pass "markdown-summary example includes a review_fixes line"
else
  fail "the markdown-summary example must include a review_fixes line"
fi

# === Branch-review hardening (EN08-CR-01..03) ===

# --- CR-01: the baseline must cover untracked file CONTENT (stash create is not enough) ---
if grep -qiE "tracked AND untracked" "$SKILL" \
   && grep -qiE "git stash create. does NOT preserve untracked|not preserve untracked" "$SKILL" \
   && grep -qiE "write-tree|content-hash manifest" "$SKILL"; then
  pass "baseline covers untracked content (temp-index tree / content-hash manifest)"
else
  fail "the Phase-1 baseline must explicitly include untracked file content"
fi

# --- CR-02: authorization precedes mutation; one final frozen set ---
if grep -qiE "Collect ALL authorizations up front|authorizations? .*before touching anything" "$SKILL" \
   && grep -qiE "never changes after mutation begins|freeze one final authorized set" "$SKILL" \
   && grep -qiE "pick always precedes mutation" "$SKILL"; then
  pass "authorization (gated announcements + manual picks) precedes mutation; frozen set is final"
else
  fail "Phase 1 must collect all authorizations BEFORE any edit and freeze one final set"
fi

# --- CR-03: the normative examples are internally coherent ---
# The JSON example's applied_fixes finding IDs must match the markdown example's
# review_fixes line, and applied_safe_auto_count must equal the safe_auto entries.
json_ids=$(sed -n '/## JSON envelope shape/,/## Markdown summary/p' "$SKILL" | grep -oE '"finding_id": "[^"]+"' | grep -oE 'rev-[0-9-]+' | sort)
md_ids=$(sed -n '/## Markdown summary/,/## Reference files/p' "$SKILL" | grep -F "review_fixes:" | grep -oE 'rev-[0-9-]+' | sort)
count_field=$(sed -n '/## JSON envelope shape/,/## Markdown summary/p' "$SKILL" | grep -oE '"applied_safe_auto_count": [0-9]+' | grep -oE '[0-9]+')
json_safe_auto=$(sed -n '/## JSON envelope shape/,/## Markdown summary/p' "$SKILL" | grep -c '"tier": "safe_auto"')
if [ -n "$json_ids" ] && [ "$json_ids" = "$md_ids" ]; then
  pass "example coherence: JSON applied_fixes IDs match the markdown review_fixes line"
else
  fail "the JSON and markdown examples must show the SAME applied finding IDs" "json=[$json_ids] md=[$md_ids]"
fi
if [ -n "$count_field" ] && [ "$count_field" = "$json_safe_auto" ]; then
  pass "example coherence: applied_safe_auto_count ($count_field) equals safe_auto entries ($json_safe_auto)"
else
  fail "applied_safe_auto_count must equal the number of safe_auto applied_fixes entries" "count=$count_field entries=$json_safe_auto"
fi

# === U3: foundation D42 ===

FOUNDATION="$REPO_ROOT/docs/foundation.md"
d42="$(grep -E "^- \*\*D42\." "$FOUNDATION" || true)"
if [ -n "$d42" ] && printf '%s' "$d42" | grep -qF "lite_gate:" && printf '%s' "$d42" | grep -qF "review_fixes:"; then
  pass "foundation D42 names both outcome lines (lite_gate, review_fixes)"
else
  fail "foundation must add D42 naming the lite_gate and review_fixes outcome lines"
fi
if [ -n "$d42" ] && printf '%s' "$d42" | grep -qiE "two-phase" && printf '%s' "$d42" | grep -qiE "P0 finding halts ALL automatic mutation"; then
  pass "D42 records the two-phase boundary + the P0 halt"
else
  fail "D42 must record the two-phase mutation boundary and the P0 halt"
fi
if [ -n "$d42" ] && printf '%s' "$d42" | grep -qF "D41"; then
  pass "D42 cross-references D41's prose-to-auditable-gate pattern"
else
  fail "D42 must cross-reference D41"
fi

report
